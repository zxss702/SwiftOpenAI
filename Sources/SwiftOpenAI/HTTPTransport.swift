import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if !os(Windows)
import AsyncHTTPClient
import NIOCore
#if canImport(Network)
import Network
#endif
#endif

/// 总时长上限哨兵值：巨大 ≈ 无限。总时长保持“无限”语义，
/// 长流式响应与长思考不应被总时长打断；失活检测交给空闲超时。
nonisolated let openAIURLSessionTimeout = TimeInterval(Int32.max / 1000)

/// 空闲超时（秒）：连接上超过该时长没有任何字节往来即判定失活并失败。
///
/// - 默认 180 秒；收到或发出任意字节即重置，长流式（SSE）与长思考不受影响。
/// - 设为 0 或负值可关闭空闲超时（恢复旧的无限行为）。
/// - NIO 客户端在首次创建时读取本值：请在发起首次请求前设置。
/// - URLSession 在每个请求创建时读取本值。
nonisolated var openAINetworkIdleTimeout: TimeInterval {
    get {
        openAIIdleTimeoutLock.lock()
        defer { openAIIdleTimeoutLock.unlock() }
        return openAIIdleTimeoutStorage
    }
    set {
        openAIIdleTimeoutLock.lock()
        openAIIdleTimeoutStorage = newValue
        openAIIdleTimeoutLock.unlock()
    }
}

private nonisolated let openAIIdleTimeoutLock = NSLock()
private nonisolated(unsafe) var openAIIdleTimeoutStorage: TimeInterval = 180

/// 逐请求超时（空闲语义，全平台一致）：
/// - Apple URLSession：request timeout 为空闲计时，收到数据即重置。
/// - Windows corelibs：由一次性 Dispatch 定时器实现，curl 收/发/头回调均重置计时，
///   同为空闲语义（已核验 corelibs 源码）。注意必须用属性赋值覆盖，init 传参不生效。
nonisolated var openAIURLRequestTimeout: TimeInterval {
    openAINetworkIdleTimeout
}

/// 资源超时保持巨大总时长值（corelibs 不消费该值，Darwin 上为总时长上限）；
/// 请求超时为空闲语义。
nonisolated var openAIURLSessionConfiguration: URLSessionConfiguration {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = openAIURLRequestTimeout
    configuration.timeoutIntervalForResource = openAIURLSessionTimeout
    return configuration
}

nonisolated let openAIURLSession = URLSession(configuration: openAIURLSessionConfiguration)

/// 将 URLSession 空闲超时映射为可识别错误；其余错误原样透传。
nonisolated func mapURLSessionTransportError(_ error: Error) -> Error {
    if let urlError = error as? URLError, urlError.code == .timedOut {
        return OpenAIError.connectionIdleTimeout
    }
    return error
}

#if !os(Windows)
/// NIO ByteBuffer 可表示的最大容量，不再额外限制为 64 MiB。
nonisolated let openAIResponseBodyLimit = Int(UInt32.max)

/// 有限 connect + 读写空闲超时；总时长（deadline）保持无限。
/// 空闲超时在客户端创建时读取一次：如需调整请在首次请求前设置 ``openAINetworkIdleTimeout``。
nonisolated let openAIHTTPClient: HTTPClient = {
    var configuration = HTTPClient.Configuration.singletonConfiguration
    configuration.timeout.connect = .seconds(15)
    let idle = openAINetworkIdleTimeout
    if idle > 0 {
        configuration.timeout.read = .milliseconds(Int64(idle * 1000))
        configuration.timeout.write = .milliseconds(Int64(idle * 1000))
    } else {
        configuration.timeout.read = nil
        configuration.timeout.write = nil
    }
    configuration.decompression = .enabled(limit: .none)
    return HTTPClient(eventLoopGroupProvider: .singleton, configuration: configuration)
}()

/// 仅在响应头到达前做有界重试的请求执行。
///
/// - 可重试：连接类错误（`connectTimeout` / `remoteConnectionClosed` / `uncleanShutdown`，
///   以及 Apple NIOTransportServices / Linux NIOPOSIX 透出的连接重置、中止、不可达等），
///   最多 `maxRetries` 次（默认 2），退避 1s / 2s。
/// - 空闲超时（`readTimeout` / `writeTimeout`）映射为 ``OpenAIError/connectionIdleTimeout``，不重试。
/// - 一旦返回响应头，之后的任何错误都不重试——绝不重放已打开的流。
nonisolated func executeHTTPClientWithRetry(
    _ request: HTTPClientRequest,
    maxRetries: Int = 2,
    client: HTTPClient = openAIHTTPClient
) async throws -> HTTPClientResponse {
    var attempt = 0
    while true {
        do {
            return try await client.execute(request, deadline: .distantFuture)
        } catch let error as HTTPClientError where error == .readTimeout || error == .writeTimeout {
            throw OpenAIError.connectionIdleTimeout
        } catch {
            guard isRetryableConnectionError(error), attempt < maxRetries else {
                throw error
            }
            attempt += 1
            try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
        }
    }
}

/// 响应头前可重试的连接类错误判定。
nonisolated func isRetryableConnectionError(_ error: Error) -> Bool {
    if let clientError = error as? HTTPClientError {
        return clientError == .connectTimeout
            || clientError == .remoteConnectionClosed
            || clientError == .uncleanShutdown
    }
    #if canImport(Network)
    // Apple 上 AHC 走 NIOTransportServices：连接重置等先以 NWError 透出，
    // 再被 AHC 的 NWErrorHandler 包装为 HTTPClient.NWPOSIXError。
    if let nwPOSIXError = error as? HTTPClient.NWPOSIXError {
        return isRetryablePOSIXCode(nwPOSIXError.errorCode)
    }
    if let nwError = error as? NWError, case .posix(let code) = nwError {
        return isRetryablePOSIXCode(code)
    }
    #endif
    // Linux 上 AHC 走 NIOPOSIX，连接错误以 IOError 透出。
    if let ioError = error as? IOError {
        return ioError.errnoCode == ECONNRESET || ioError.errnoCode == ECONNABORTED
            || ioError.errnoCode == ETIMEDOUT || ioError.errnoCode == EPIPE
            || ioError.errnoCode == ENETDOWN || ioError.errnoCode == ENETUNREACH
            || ioError.errnoCode == EHOSTUNREACH
    }
    return false
}

#if canImport(Network)
private nonisolated func isRetryablePOSIXCode(_ code: POSIXErrorCode) -> Bool {
    code == .ECONNRESET || code == .ECONNABORTED || code == .ETIMEDOUT
        || code == .EPIPE || code == .ENETDOWN || code == .ENETUNREACH || code == .EHOSTUNREACH
}
#endif
#endif