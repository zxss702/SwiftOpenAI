#if os(Windows)
import CWinHTTP
import Foundation
import FoundationNetworking

enum WindowsHTTPEvent: Sendable {
    case response(HTTPURLResponse)
    case data(Data)
}

/// WinHTTP avoids the Windows FoundationNetworking upload stall when a socket
/// cannot accept the entire request body in one burst.
nonisolated func makeWindowsHTTPStream(
    for request: URLRequest
) -> (transfer: Task<Void, Never>, stream: AsyncThrowingStream<WindowsHTTPEvent, Error>) {
    let (stream, continuation) = AsyncThrowingStream<WindowsHTTPEvent, Error>.makeStream()
    let transfer = Task {
        do {
            var request = request
            for _ in 0...10 {
                try Task.checkCancellation()
                guard let redirected = try await forwardWindowsHTTP(request, to: continuation) else {
                    continuation.finish()
                    return
                }
                request = redirected
            }
            throw URLError(.httpTooManyRedirects)
        } catch {
            continuation.finish(throwing: error)
        }
    }
    continuation.onTermination = { _ in transfer.cancel() }
    return (transfer, stream)
}

private nonisolated func forwardWindowsHTTP(
    _ request: URLRequest,
    to output: AsyncThrowingStream<WindowsHTTPEvent, Error>.Continuation
) async throws -> URLRequest? {
    let (stream, continuation) = AsyncThrowingStream<WindowsHTTPEvent, Error>.makeStream()
    let transfer = WindowsHTTPTransfer(request: request, continuation: continuation)
    transfer.start()
    defer { transfer.cancel() }
    return try await withTaskCancellationHandler {
        for try await event in stream {
            try Task.checkCancellation()
            if case .response(let response) = event, let redirect = redirectRequest(request, response: response) {
                return redirect
            }
            output.yield(event)
        }
        try Task.checkCancellation()
        return nil
    } onCancel: {
        transfer.cancel()
    }
}

private nonisolated func redirectRequest(_ request: URLRequest, response: HTTPURLResponse) -> URLRequest? {
    let code = response.statusCode
    guard [301, 302, 303, 307, 308].contains(code),
          let source = request.url, let location = response.value(forHTTPHeaderField: "Location"),
          let target = URL(string: location, relativeTo: source)?.absoluteURL,
          let scheme = source.scheme?.lowercased(), let host = source.host?.lowercased(),
          target.scheme?.lowercased() == scheme, target.host?.lowercased() == host,
          (target.port ?? (scheme == "https" ? 443 : 80)) == (source.port ?? (scheme == "https" ? 443 : 80)) else {
        return nil
    }
    var redirected = request
    redirected.url = target
    if (code == 303 && request.httpMethod != "HEAD")
        || ((code == 301 || code == 302) && request.httpMethod == "POST") {
        redirected.httpMethod = "GET"
        redirected.httpBody = nil
        redirected.setValue(nil, forHTTPHeaderField: "Content-Type")
    }
    return redirected
}

nonisolated func windowsHTTPData(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    try Task.checkCancellation()
    let (transfer, stream) = makeWindowsHTTPStream(for: request)
    return try await withTaskCancellationHandler {
        var response: HTTPURLResponse?
        var data = Data()
        for try await event in stream {
            try Task.checkCancellation()
            switch event {
            case .response(let value): response = value
            case .data(let chunk): data.append(chunk)
            }
        }
        try Task.checkCancellation()
        guard let response else { throw URLError(.badServerResponse) }
        return (data, response)
    } onCancel: {
        transfer.cancel()
    }
}

private let windowsHTTPCallback: WINHTTP_STATUS_CALLBACK = { _, context, status, info, length in
    guard let pointer = UnsafeRawPointer(bitPattern: UInt(context)) else { return }
    let owner = Unmanaged<WindowsHTTPTransfer>.fromOpaque(pointer)
    if status == DWORD(WINHTTP_CALLBACK_STATUS_HANDLE_CLOSING) {
        owner.release()
        return
    }
    let transfer = owner.takeUnretainedValue()
    switch status {
    case DWORD(WINHTTP_CALLBACK_STATUS_SENDREQUEST_COMPLETE),
         DWORD(WINHTTP_CALLBACK_STATUS_HEADERS_AVAILABLE),
         DWORD(WINHTTP_CALLBACK_STATUS_READ_COMPLETE):
        transfer.receive(status: status, byteCount: length)
    case DWORD(WINHTTP_CALLBACK_STATUS_DATA_AVAILABLE):
        let available = info?.assumingMemoryBound(to: DWORD.self).pointee ?? 0
        transfer.receive(status: status, byteCount: available)
    case DWORD(WINHTTP_CALLBACK_STATUS_REQUEST_ERROR):
        let error = info?.assumingMemoryBound(to: WINHTTP_ASYNC_RESULT.self).pointee.dwError
            ?? DWORD(ERROR_WINHTTP_INTERNAL_ERROR)
        transfer.fail(code: error)
    default:
        break
    }
}

/// WinHTTP may call back from any thread. Only the serial queue changes handles
/// or starts an operation. The native callback retains the body and read buffer
/// until HANDLE_CLOSING, including when cancellation interrupts a native call.
private final class WindowsHTTPTransfer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "swiftopenai.winhttp")
    private let request: URLRequest
    private let body: NSData
    private let continuation: AsyncThrowingStream<WindowsHTTPEvent, Error>.Continuation
    private let bufferSize = 16_384
    private let buffer: UnsafeMutableRawPointer
    private var session: HINTERNET?
    private var connection: HINTERNET?
    private var handle: HINTERNET?
    private var finished = false

    init(request: URLRequest, continuation: AsyncThrowingStream<WindowsHTTPEvent, Error>.Continuation) {
        self.request = request
        self.body = (request.httpBody ?? Data()) as NSData
        self.continuation = continuation
        self.buffer = .allocate(byteCount: bufferSize, alignment: 1)
    }

    deinit { buffer.deallocate() }

    func start() {
        queue.async {
            do { try self.open() }
            catch { self.finish(throwing: error) }
        }
    }

    func cancel() {
        queue.async { self.finish(throwing: CancellationError()) }
    }

    fileprivate func fail(code: DWORD) {
        queue.async { self.finish(throwing: Self.error(code)) }
    }

    fileprivate func receive(status: DWORD, byteCount: DWORD) {
        queue.async {
            guard let handle = self.handle, !self.finished else { return }
            do {
                switch status {
                case DWORD(WINHTTP_CALLBACK_STATUS_SENDREQUEST_COMPLETE):
                    try Self.check(WinHttpReceiveResponse(handle, nil))
                case DWORD(WINHTTP_CALLBACK_STATUS_HEADERS_AVAILABLE):
                    self.continuation.yield(.response(try self.response(from: handle)))
                    try Self.check(WinHttpQueryDataAvailable(handle, nil))
                case DWORD(WINHTTP_CALLBACK_STATUS_DATA_AVAILABLE):
                    guard byteCount > 0 else { self.finish(); return }
                    // Read only the bytes already available so a small SSE
                    // event can be delivered before a large buffer fills.
                    let count = min(byteCount, DWORD(self.bufferSize))
                    try Self.check(WinHttpReadData(handle, self.buffer, count, nil))
                case DWORD(WINHTTP_CALLBACK_STATUS_READ_COMPLETE):
                    guard byteCount > 0 else { self.finish(); return }
                    let data = Data(bytes: self.buffer, count: Int(byteCount))
                    self.continuation.yield(.data(data))
                    try Self.check(WinHttpQueryDataAvailable(handle, nil))
                default:
                    break
                }
            } catch {
                self.finish(throwing: error)
            }
        }
    }

    private func open() throws {
        guard !finished, let url = request.url, let host = url.host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let port = UInt16(exactly: components.port ?? (scheme == "https" ? 443 : 80)) else {
            throw OpenAIError.invalidURL
        }
        guard let bodyLength = DWORD(exactly: body.length) else {
            throw OpenAIError.requestBodyTooLarge("请求体超过 Windows HTTP 传输大小限制")
        }

        let agent = request.value(forHTTPHeaderField: "User-Agent") ?? OpenAIConfiguration.defaultUserAgent
        guard let session = agent.withCString(encodedAs: UTF16.self, {
            WinHttpOpen($0, DWORD(WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY), nil, nil, DWORD(WINHTTP_FLAG_ASYNC))
        }) else { throw Self.error(GetLastError()) }
        self.session = session
        guard let connection = host.withCString(encodedAs: UTF16.self, {
            WinHttpConnect(session, $0, port, 0)
        }) else { throw Self.error(GetLastError()) }
        self.connection = connection

        let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        let target = path + (components.percentEncodedQuery.map { "?" + $0 } ?? "")
        let flags = scheme == "https" ? DWORD(WINHTTP_FLAG_SECURE) : 0
        let method = request.httpMethod ?? "GET"
        guard let handle = method.withCString(encodedAs: UTF16.self, { verb in
            target.withCString(encodedAs: UTF16.self) {
                WinHttpOpenRequest(connection, verb, $0, nil, nil, nil, flags)
            }
        }) else { throw Self.error(GetLastError()) }
        self.handle = handle

        let idle = request.timeoutInterval
        let milliseconds: Int32 = idle > 0 && idle.isFinite
            ? Int32(min(max(1, idle * 1_000), Double(Int32.max))) : 0
        try Self.check(WinHttpSetTimeouts(handle, 15_000, 15_000, milliseconds, milliseconds))
        try Self.setOption(handle, DWORD(WINHTTP_OPTION_RECEIVE_RESPONSE_TIMEOUT), DWORD(milliseconds))
        try Self.setOption(handle, DWORD(WINHTTP_OPTION_DECOMPRESSION), DWORD(WINHTTP_DECOMPRESSION_FLAG_ALL))
        // Headers can contain bearer credentials. Handle redirects explicitly.
        try Self.setOption(handle, DWORD(WINHTTP_OPTION_REDIRECT_POLICY), DWORD(WINHTTP_OPTION_REDIRECT_POLICY_NEVER))

        let headers = (request.allHTTPHeaderFields ?? [:]).filter {
            let field = $0.key.lowercased()
            return field != "user-agent" && field != "content-length"
        }.map { "\($0.key): \($0.value)" }.joined(separator: "\r\n")
        if !headers.isEmpty {
            try headers.withCString(encodedAs: UTF16.self) {
                try Self.check(WinHttpAddRequestHeaders(handle, $0, DWORD.max, DWORD(WINHTTP_ADDREQ_FLAG_ADD)))
            }
        }

        let notifications = DWORD(WINHTTP_CALLBACK_STATUS_HANDLE_CLOSING)
            | DWORD(WINHTTP_CALLBACK_STATUS_SENDREQUEST_COMPLETE)
            | DWORD(WINHTTP_CALLBACK_STATUS_HEADERS_AVAILABLE)
            | DWORD(WINHTTP_CALLBACK_STATUS_DATA_AVAILABLE)
            | DWORD(WINHTTP_CALLBACK_STATUS_READ_COMPLETE)
            | DWORD(WINHTTP_CALLBACK_STATUS_REQUEST_ERROR)
        try Self.check(SOAIWinHttpSetCallback(handle, windowsHTTPCallback, notifications))
        let owner = Unmanaged.passRetained(self)
        let context = DWORD_PTR(UInt(bitPattern: owner.toOpaque()))
        do {
            try Self.setOption(handle, DWORD(WINHTTP_OPTION_CONTEXT_VALUE), context)
        } catch {
            owner.release()
            throw error
        }
        try Self.check(WinHttpSendRequest(
            handle, nil, 0, bodyLength == 0 ? nil : UnsafeMutableRawPointer(mutating: body.bytes),
            bodyLength, bodyLength, context
        ))
    }

    private func response(from handle: HINTERNET) throws -> HTTPURLResponse {
        var status: DWORD = 0
        var size = DWORD(MemoryLayout<DWORD>.size)
        try Self.check(WinHttpQueryHeaders(
            handle, DWORD(WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER), nil, &status, &size, nil
        ))
        size = 0
        _ = WinHttpQueryHeaders(handle, DWORD(WINHTTP_QUERY_RAW_HEADERS_CRLF), nil, nil, &size, nil)
        var headers: [String: String] = [:]
        if size > 0 {
            var raw = [UInt16](repeating: 0, count: Int(size) / MemoryLayout<UInt16>.size)
            try raw.withUnsafeMutableBytes {
                try Self.check(WinHttpQueryHeaders(
                    handle, DWORD(WINHTTP_QUERY_RAW_HEADERS_CRLF), nil, $0.baseAddress, &size, nil
                ))
            }
            let lines = String(decoding: raw.prefix { $0 != 0 }, as: UTF16.self).components(separatedBy: "\r\n")
            for line in lines.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let name = line[..<colon].lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                headers[name] = headers[name].map { $0 + ", " + value } ?? value
            }
        }
        guard let url = request.url, let response = HTTPURLResponse(
            url: url, statusCode: Int(status), httpVersion: nil, headerFields: headers
        ) else { throw URLError(.badServerResponse) }
        return response
    }

    private func finish(throwing error: Error? = nil) {
        guard !finished else { return }
        finished = true
        if let handle { WinHttpCloseHandle(handle); self.handle = nil }
        if let connection { WinHttpCloseHandle(connection); self.connection = nil }
        if let session { WinHttpCloseHandle(session); self.session = nil }
        continuation.finish(throwing: error)
    }

    private static func setOption<T>(_ handle: HINTERNET, _ option: DWORD, _ value: T) throws {
        var value = value
        try withUnsafeMutableBytes(of: &value) {
            try check(WinHttpSetOption(handle, option, $0.baseAddress, DWORD($0.count)))
        }
    }

    private static func check(_ result: Bool) throws {
        if !result { throw error(GetLastError()) }
    }

    private static func error(_ code: DWORD) -> Error {
        if code == ERROR_WINHTTP_TIMEOUT { return OpenAIError.connectionIdleTimeout }
        if code == ERROR_WINHTTP_OPERATION_CANCELLED { return CancellationError() }
        return OpenAIError.networkError(NSError(domain: "WinHTTP", code: Int(code)))
    }
}
#endif
