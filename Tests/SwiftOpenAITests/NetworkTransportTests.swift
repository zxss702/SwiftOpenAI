import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import SwiftOpenAI

// MARK: - 配置口与错误映射（跨平台）

final class NetworkTransportConfigurationTests: XCTestCase {
    private var originalIdle: TimeInterval = 0

    override func setUp() {
        super.setUp()
        originalIdle = openAINetworkIdleTimeout
    }

    override func tearDown() {
        openAINetworkIdleTimeout = originalIdle
        super.tearDown()
    }

    func testIdleTimeoutRoundTripPropagatesToRequestAndConfiguration() {
        openAINetworkIdleTimeout = 42.5
        XCTAssertEqual(openAINetworkIdleTimeout, 42.5)
        XCTAssertEqual(openAIURLRequestTimeout, 42.5)

        let configuration = openAIURLSessionConfiguration
        XCTAssertEqual(configuration.timeoutIntervalForRequest, 42.5)
        XCTAssertEqual(configuration.timeoutIntervalForResource, openAIURLSessionTimeout)
    }

    func testIdleTimeoutCanBeDisabled() {
        openAINetworkIdleTimeout = 0
        XCTAssertEqual(openAIURLRequestTimeout, 0)
        XCTAssertEqual(openAIURLSessionConfiguration.timeoutIntervalForRequest, 0)
    }

    func testConcurrentIdleTimeoutAccess() {
        DispatchQueue.concurrentPerform(iterations: 200) { index in
            if index % 2 == 0 {
                openAINetworkIdleTimeout = TimeInterval(index)
            } else {
                _ = openAINetworkIdleTimeout
            }
        }
        // 无崩溃即通过；恢复原值由 tearDown 完成。
    }

    func testMapURLSessionTimeoutToIdleError() {
        let mapped = mapURLSessionTransportError(URLError(.timedOut))
        guard case OpenAIError.connectionIdleTimeout = mapped else {
            return XCTFail("timedOut 应映射为 connectionIdleTimeout，实际 \(mapped)")
        }
    }

    func testMapURLSessionOtherErrorsPassThrough() {
        let urlError = URLError(.cannotConnectToHost)
        let mappedURL = mapURLSessionTransportError(urlError) as? URLError
        XCTAssertEqual(mappedURL?.code, .cannotConnectToHost)

        let other = NSError(domain: "test", code: 7)
        let mappedOther = mapURLSessionTransportError(other) as NSError
        XCTAssertEqual(mappedOther.domain, "test")
        XCTAssertEqual(mappedOther.code, 7)
    }
}

// MARK: - 路径守卫（Apple 平台）

#if canImport(Network)
final class NetworkPathGuardTests: XCTestCase {
    func testGuardReturnsOperationValue() async throws {
        let value = try await withNetworkPathGuard { 42 }
        XCTAssertEqual(value, 42)
    }

    func testGuardRethrowsOperationError() async {
        do {
            _ = try await withNetworkPathGuard { () -> Int in
                throw OpenAIError.invalidURL
            }
            XCTFail("应抛出操作错误")
        } catch OpenAIError.invalidURL {
            // 预期
        } catch {
            XCTFail("非预期错误 \(error)")
        }
    }

    func testGuardLetsHealthyOperationRunAcrossPollCycles() async throws {
        // 操作时长超过守卫轮询周期（250ms），健康路径下不得被误杀。
        let value = try await withNetworkPathGuard { () -> String in
            try await Task.sleep(nanoseconds: 600_000_000)
            return "ok"
        }
        XCTAssertEqual(value, "ok")
    }

    func testGuardPropagatesCancellation() async {
        let task = Task {
            try await withNetworkPathGuard { () -> Int in
                try await Task.sleep(nanoseconds: 10_000_000_000)
                return 1
            }
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("应抛出 CancellationError")
        } catch is CancellationError {
            // 预期：用户主动取消保持原语义
        } catch {
            XCTFail("非预期错误 \(error)")
        }
    }
}
#endif

// MARK: - 传输集成（本地 NWListener 服务器 + AHC）

#if canImport(Network) && !os(Windows)
import AsyncHTTPClient
import Network
import NIOCore

final class NetworkTransportIntegrationTests: XCTestCase {
    func testSuccessfulRequestPassesThroughRetryHelper() async throws {
        let body = Data(#"{"ok":true}"#.utf8)
        let head = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        let server = try TransportTestServer(behavior: .respond(Data(head.utf8) + body))
        let port = try await server.start()
        defer { server.stop() }

        let response = try await executeHTTPClientWithRetry(makeRequest(port: port))
        XCTAssertEqual(response.status.code, 200)
        let collected = try await response.body.collect(upTo: 1 << 20)
        XCTAssertEqual(Data(collected.readableBytesView), body)
        XCTAssertEqual(server.connectionCount, 1)
    }

    func testPreHeaderConnectionClosedRetriesTwiceWithBackoff() async throws {
        let server = try TransportTestServer(behavior: .closeImmediately)
        let port = try await server.start()
        defer { server.stop() }

        let client = makeClient(idle: nil)
        defer { Task { try? await client.shutdown() } }

        let start = Date()
        do {
            _ = try await executeHTTPClientWithRetry(makeRequest(port: port), client: client)
            XCTFail("连接被立即关闭应失败")
        } catch let error as HTTPClientError {
            XCTAssertTrue(
                error == .remoteConnectionClosed || error == .uncleanShutdown,
                "应为连接类错误，实际 \(error)"
            )
        } catch let error as HTTPClient.NWPOSIXError {
            // Apple 上 AHC 将 NWError.posix 包装为 NWPOSIXError。
            XCTAssertEqual(error.errorCode, .ECONNRESET)
        } catch let error as NWError {
            guard case .posix(let code) = error else {
                return XCTFail("应为 posix 连接错误，实际 \(error)")
            }
            XCTAssertEqual(code, .ECONNRESET)
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(server.connectionCount, 3, "首次 + 2 次重试")
        XCTAssertGreaterThanOrEqual(elapsed, 2.5, "退避 1s + 2s")
        XCTAssertLessThan(elapsed, 15)
    }

    func testRetryableConnectionErrorClassification() {
        XCTAssertTrue(isRetryableConnectionError(HTTPClientError.connectTimeout))
        XCTAssertTrue(isRetryableConnectionError(HTTPClientError.remoteConnectionClosed))
        XCTAssertTrue(isRetryableConnectionError(HTTPClientError.uncleanShutdown))
        XCTAssertTrue(isRetryableConnectionError(NWError.posix(.ECONNRESET)))
        XCTAssertTrue(isRetryableConnectionError(HTTPClient.NWPOSIXError(.ECONNRESET, reason: "test")))
        XCTAssertTrue(isRetryableConnectionError(IOError(errnoCode: ECONNRESET, reason: "test")))

        XCTAssertFalse(isRetryableConnectionError(HTTPClientError.readTimeout))
        XCTAssertFalse(isRetryableConnectionError(HTTPClientError.writeTimeout))
        XCTAssertFalse(isRetryableConnectionError(HTTPClientError.cancelled))
        XCTAssertFalse(isRetryableConnectionError(NWError.posix(.EACCES)))
        XCTAssertFalse(isRetryableConnectionError(URLError(.timedOut)))
        XCTAssertFalse(isRetryableConnectionError(OpenAIError.invalidURL))
    }

    func testIdleTimeoutMappedAndNotRetried() async throws {
        let server = try TransportTestServer(behavior: .stall)
        let port = try await server.start()
        defer { server.stop() }

        let client = makeClient(idle: 0.5)
        defer { Task { try? await client.shutdown() } }

        let start = Date()
        do {
            _ = try await executeHTTPClientWithRetry(makeRequest(port: port), client: client)
            XCTFail("静默连接应空闲超时")
        } catch OpenAIError.connectionIdleTimeout {
            // 预期：readTimeout 映射为可识别错误
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(server.connectionCount, 1, "空闲超时不得重试")
        XCTAssertLessThan(elapsed, 3, "不应叠加重试退避")
    }

    func testSlowStreamSurvivesIdleTimeout() async throws {
        // 每块间隔 150ms < 空闲 500ms，总时长 ~900ms > 空闲：
        // 证明空闲计时按字节重置，长流式不被误杀。
        let chunks = (0..<6).map { index in Data("data: {\"i\":\(index)}\n\n".utf8) }
        let head = Data("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n".utf8)
        let server = try TransportTestServer(behavior: .drip(head: head, chunks: chunks, interval: 0.15))
        let port = try await server.start()
        defer { server.stop() }

        let client = makeClient(idle: 0.5)
        defer { Task { try? await client.shutdown() } }

        let response = try await executeHTTPClientWithRetry(makeRequest(port: port), client: client)
        XCTAssertEqual(response.status.code, 200)
        var received = Data()
        for try await part in response.body {
            received.append(Data(part.readableBytesView))
        }
        XCTAssertEqual(received, chunks.reduce(Data(), +))
        XCTAssertEqual(server.connectionCount, 1)
    }

    private func makeRequest(port: UInt16) -> HTTPClientRequest {
        var request = HTTPClientRequest(url: "http://127.0.0.1:\(port)/v1/test")
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/json")
        request.body = .bytes(Data("{}".utf8))
        return request
    }

    private func makeClient(idle: TimeInterval?) -> HTTPClient {
        var configuration = HTTPClient.Configuration.singletonConfiguration
        configuration.timeout.connect = .seconds(5)
        configuration.timeout.read = idle.map { .milliseconds(Int64($0 * 1000)) }
        configuration.timeout.write = idle.map { .milliseconds(Int64($0 * 1000)) }
        return HTTPClient(eventLoopGroupProvider: .singleton, configuration: configuration)
    }
}

/// 本地 TCP 测试服务器：按行为应答，统计连接数。
private final class TransportTestServer: @unchecked Sendable {
    enum Behavior {
        case respond(Data)
        case closeImmediately
        case stall
        case drip(head: Data, chunks: [Data], interval: TimeInterval)
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "swiftopenai.transport-test")
    private let lock = NSLock()
    private let behavior: Behavior
    private var ready: CheckedContinuation<UInt16, Error>?
    private var connections = 0

    var connectionCount: Int { lock.withLock { connections } }

    init(behavior: Behavior) throws {
        self.behavior = behavior
        listener = try NWListener(using: .tcp, on: .any)
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock { ready = continuation }
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    if let port = self.listener.port {
                        self.finishStart(.success(port.rawValue))
                    }
                case .failed(let error):
                    self.finishStart(.failure(error))
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { connection.cancel(); return }
                self.lock.withLock { self.connections += 1 }
                connection.start(queue: self.queue)
                self.handle(connection)
            }
            listener.start(queue: queue)
        }
    }

    func stop() { listener.cancel() }

    private func finishStart(_ result: Result<UInt16, Error>) {
        let continuation = lock.withLock { let value = ready; ready = nil; return value }
        continuation?.resume(with: result)
    }

    private func handle(_ connection: NWConnection) {
        switch behavior {
        case .closeImmediately:
            connection.cancel()
        case .respond, .stall, .drip:
            receiveRequest(connection)
        }
    }

    private func receiveRequest(_ connection: NWConnection, buffer: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            var bytes = buffer
            if let data { bytes.append(data) }
            if let separator = bytes.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: bytes[..<separator.lowerBound], as: UTF8.self)
                let length = head.components(separatedBy: "\r\n")
                    .first { $0.lowercased().hasPrefix("content-length:") }
                    .flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) } ?? 0
                if bytes.count >= separator.upperBound + length {
                    self.respond(to: connection)
                    return
                }
            }
            if complete || error != nil { connection.cancel() }
            else { self.receiveRequest(connection, buffer: bytes) }
        }
    }

    private func respond(to connection: NWConnection) {
        switch behavior {
        case .respond(let payload):
            connection.send(content: payload, completion: .contentProcessed { _ in connection.cancel() })
        case .stall:
            break // 收到请求后保持静默，连接不关闭
        case .drip(let head, let chunks, let interval):
            connection.send(content: head, completion: .contentProcessed { [weak self] _ in
                self?.sendChunks(connection, chunks: chunks, interval: interval)
            })
        case .closeImmediately:
            connection.cancel()
        }
    }

    private func sendChunks(_ connection: NWConnection, chunks: [Data], interval: TimeInterval) {
        guard let first = chunks.first else {
            connection.cancel()
            return
        }
        connection.send(content: first, completion: .contentProcessed { [weak self] _ in
            guard let self else { connection.cancel(); return }
            self.queue.asyncAfter(deadline: .now() + interval) {
                self.sendChunks(connection, chunks: Array(chunks.dropFirst()), interval: interval)
            }
        })
    }
}
#endif