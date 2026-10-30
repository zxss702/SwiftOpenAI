import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if !os(Windows)
import AsyncHTTPClient
import NIOCore
#endif

/// 采用 Windows libcurl 的 32 位毫秒上限内可接受的最大整秒数。
nonisolated let openAIURLSessionTimeout = TimeInterval(Int32.max / 1000)

/// 请求与资源超时保持一致，避免会话默认值提前结束长响应。
nonisolated var openAIURLSessionConfiguration: URLSessionConfiguration {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = openAIURLSessionTimeout
    configuration.timeoutIntervalForResource = openAIURLSessionTimeout
    return configuration
}

nonisolated let openAIURLSession = URLSession(configuration: openAIURLSessionConfiguration)

#if !os(Windows)
/// NIO ByteBuffer 可表示的最大容量，不再额外限制为 64 MiB。
nonisolated let openAIResponseBodyLimit = Int(UInt32.max)

/// 保留默认连接配置，取消读写空闲与解压比例限制。
nonisolated let openAIHTTPClient: HTTPClient = {
    var configuration = HTTPClient.Configuration.singletonConfiguration
    configuration.timeout.connect = .nanoseconds(Int64.max)
    configuration.timeout.read = nil
    configuration.timeout.write = nil
    configuration.decompression = .enabled(limit: .none)
    return HTTPClient(eventLoopGroupProvider: .singleton, configuration: configuration)
}()
#endif
