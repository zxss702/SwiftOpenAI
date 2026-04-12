import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if !os(Windows)
import AsyncHTTPClient
import NIOCore
import NIOHTTP1
#endif

// MARK: - OpenAI Client

/// OpenAI API 客户端
///
/// `OpenAI` 提供了与 OpenAI API 交互的核心功能，支持流式和非流式聊天完成。
///
/// ## Overview
///
/// 使用此类可以：
/// - 发送聊天完成请求
/// - 支持流式传输以实时获取响应
/// - 自定义配置（主机、令牌、额外参数等）
///
/// ## Topics
///
/// ### 创建客户端
/// - ``init(configuration:)``
///
/// ### 发送聊天消息
/// - ``chatsStream(query:)``
/// - ``chats(query:)``
///
public class OpenAI {
    private nonisolated let configuration: OpenAIConfiguration
    
    /// 初始化 OpenAI 客户端
    ///
    /// - Parameter configuration: API 配置，默认使用环境变量中的配置
    public init(configuration: OpenAIConfiguration? = nil) {
        self.configuration = configuration ?? OpenAIConfiguration.default
    }
    
    /// 发送聊天消息（流式传输）
    ///
    /// 此方法返回一个异步流，实时接收 AI 模型的响应片段。
    ///
    /// - Parameter query: 聊天查询参数
    /// - Returns: 包含流式响应结果的异步流
    ///
    /// ## Example
    ///
    /// ```swift
    /// let query = ChatQuery(messages: [.user("你好")], model: "gpt-4")
    /// for try await result in openAI.chatsStream(query: query) {
    ///     print(result.choices.first?.delta.content ?? "")
    /// }
    /// ```
    public nonisolated func chatsStream(query: ChatQuery) -> AsyncThrowingStream<ChatStreamResult, Error> {
        AsyncThrowingStream { continuation in
            let configuration = self.configuration
            let task = Task { [configuration] in
                do {
                    let envelopeStream = createChatStreamEnvelopeStream(query: query, configuration: configuration)
                    for try await envelope in envelopeStream {
                        continuation.yield(envelope.result)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
    
    /// 发送聊天消息（非流式传输）
    ///
    /// 此方法等待完整响应后一次性返回结果。
    ///
    /// - Parameter query: 聊天查询参数
    /// - Returns: 完整的聊天完成结果
    /// - Throws: ``OpenAIError`` 如果请求失败或响应无效
    ///
    /// ## Example
    ///
    /// ```swift
    /// let query = ChatQuery(messages: [.user("你好")], model: "gpt-4")
    /// let result = try await openAI.chats(query: query)
    /// print(result.choices.first?.message.content ?? "")
    /// ```
    public func chats(query: ChatQuery) async throws -> ChatCompletionResult {
        try await chatCompletionEnvelope(query: query).result
    }

    func chatCompletionEnvelope(query: ChatQuery) async throws -> ChatCompletionEnvelope {
        try await createChatCompletionEnvelope(query: query, configuration: configuration)
    }

    func chatsStreamEnvelope(query: ChatQuery) -> AsyncThrowingStream<ChatStreamEnvelope, Error> {
        createChatStreamEnvelopeStream(query: query, configuration: configuration)
    }
}

nonisolated func createChatRequest(query: ChatQuery, configuration: OpenAIConfiguration) async throws -> PreparedChatRequest {
    try ProviderRequestEncoder.makeRequest(query: query, configuration: configuration)
}

#if !os(Windows)
private let openAIRequestTimeout: TimeAmount = .seconds(300)
private let openAIResponseBodyLimit = 64 * 1024 * 1024

nonisolated private func executePreparedRequest(_ preparedRequest: PreparedChatRequest) async throws -> HTTPClientResponse {
    let request = try makeHTTPClientRequest(from: preparedRequest.urlRequest)
    return try await HTTPClient.shared.execute(request, timeout: openAIRequestTimeout)
}

nonisolated private func makeHTTPClientRequest(from urlRequest: URLRequest) throws -> HTTPClientRequest {
    guard let url = urlRequest.url else {
        throw OpenAIError.invalidURL
    }

    var request = HTTPClientRequest(url: url.absoluteString)
    request.method = httpMethod(from: urlRequest.httpMethod)

    if let headers = urlRequest.allHTTPHeaderFields {
        for (name, value) in headers {
            request.headers.add(name: name, value: value)
        }
    }

    if let body = urlRequest.httpBody {
        request.body = .bytes(body)
    }

    return request
}

nonisolated private func httpMethod(from method: String?) -> HTTPMethod {
    switch method?.uppercased() {
    case "DELETE":
        return .DELETE
    case "GET":
        return .GET
    case "HEAD":
        return .HEAD
    case "PATCH":
        return .PATCH
    case "POST":
        return .POST
    case "PUT":
        return .PUT
    default:
        return .GET
    }
}

nonisolated private func collectBodyData(from body: HTTPClientResponse.Body?) async throws -> Data {
    guard let body else { return Data() }
    let buffer = try await body.collect(upTo: openAIResponseBodyLimit)
    guard let bytes = buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes) else {
        return Data()
    }
    return Data(bytes)
}

nonisolated private func responseBodyString(from body: HTTPClientResponse.Body?) async throws -> String {
    let data = try await collectBodyData(from: body)
    return String(data: data, encoding: .utf8) ?? "无法解析响应内容（非UTF-8）"
}

nonisolated func createChatCompletionEnvelope(
    query: ChatQuery,
    configuration: OpenAIConfiguration
) async throws -> ChatCompletionEnvelope {
    let preparedRequest = try await createChatRequest(query: query, configuration: configuration)
    let response = try await executePreparedRequest(preparedRequest)

    guard (200...299).contains(Int(response.status.code)) else {
        let responseBody = try await responseBodyString(from: response.body)
        let statusCode = Int(response.status.code)
        throw OpenAIError.invalidResponse(responseBody, code: statusCode)
    }

    do {
        let data = try await collectBodyData(from: response.body)
        let result = try JSONDecoder().decode(ChatCompletionResult.self, from: data)
        let metadata = preparedRequest.metadata.withRequestID(
            ProviderResponseNormalizer.requestID(from: response.headers)
        )
        return ChatCompletionEnvelope(result: result, metadata: metadata)
    } catch {
        throw OpenAIError.decodingError(error)
    }
}

nonisolated func createChatStreamEnvelopeStream(
    query: ChatQuery,
    configuration: OpenAIConfiguration
) -> AsyncThrowingStream<ChatStreamEnvelope, Error> {
    AsyncThrowingStream { continuation in
        let task = Task { [configuration] in
            do {
                let preparedRequest = try await createChatRequest(query: query, configuration: configuration)
                var streamState = ProviderStreamNormalizationState()
                let response = try await executePreparedRequest(preparedRequest)

                guard (200...299).contains(Int(response.status.code)) else {
                    let responseBody = try await responseBodyString(from: response.body)
                    let statusCode = Int(response.status.code)
                    throw OpenAIError.invalidResponse(responseBody, code: statusCode)
                }

                let metadata = preparedRequest.metadata.withRequestID(
                    ProviderResponseNormalizer.requestID(from: response.headers)
                )
                let statusCode = Int(response.status.code)

                var pendingText = ""
                for try await part in response.body {
                    try Task.checkCancellation()
                    let text = String(buffer: part)
                    if try processSSEText(
                        text,
                        pendingText: &pendingText,
                        statusCode: statusCode,
                        metadata: metadata,
                        family: preparedRequest.family,
                        state: &streamState,
                        continuation: continuation
                    ) {
                        return
                    }
                }

                if try processSSEText(
                    "",
                    pendingText: &pendingText,
                    statusCode: statusCode,
                    metadata: metadata,
                    family: preparedRequest.family,
                    state: &streamState,
                    continuation: continuation,
                    finalize: true
                ) {
                    return
                }

                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { _ in
            task.cancel()
        }
    }
}
#else /* Windows */

final class ChatStreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    typealias Continuation = AsyncThrowingStream<ChatStreamEnvelope, Error>.Continuation
    
    let continuation: Continuation
    var pendingText: String = ""
    var statusCode: Int = 0
    var metadata: ChatResponseMetadata
    var family: ProviderFamily
    var streamState = ProviderStreamNormalizationState()
    var receivedResponse = false
    
    init(continuation: Continuation, metadata: ChatResponseMetadata, family: ProviderFamily) {
        self.continuation = continuation
        self.metadata = metadata
        self.family = family
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let httpResponse = response as? HTTPURLResponse {
            receivedResponse = true
            statusCode = httpResponse.statusCode
            metadata = metadata.withRequestID(ProviderResponseNormalizer.requestID(from: httpResponse))
        }
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard receivedResponse else { return }
        let text = String(data: data, encoding: .utf8) ?? ""
        if !(200...299).contains(statusCode) {
            pendingText += text
            return
        }
        
        do {
            let finished = try processSSEText(
                text,
                pendingText: &pendingText,
                statusCode: statusCode,
                metadata: metadata,
                family: family,
                state: &streamState,
                continuation: continuation
            )
            if finished {
                dataTask.cancel()
            }
        } catch {
            dataTask.cancel()
            session.invalidateAndCancel()
            continuation.finish(throwing: error)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            continuation.finish(throwing: error)
            return
        }
        
        if !(200...299).contains(statusCode) {
            continuation.finish(throwing: OpenAIError.invalidResponse(pendingText, code: statusCode))
            return
        }
        
        do {
            let _ = try processSSEText(
                "",
                pendingText: &pendingText,
                statusCode: statusCode,
                metadata: metadata,
                family: family,
                state: &streamState,
                continuation: continuation,
                finalize: true
            )
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }
}

nonisolated func createChatCompletionEnvelope(
    query: ChatQuery,
    configuration: OpenAIConfiguration
) async throws -> ChatCompletionEnvelope {
    let preparedRequest = try await createChatRequest(query: query, configuration: configuration)
    
    return try await withCheckedThrowingContinuation { continuation in
        let task = URLSession.shared.dataTask(with: preparedRequest.urlRequest) { data, response, error in
            if let error = error {
                continuation.resume(throwing: error)
                return
            }
            guard let data = data, let httpResponse = response as? HTTPURLResponse else {
                continuation.resume(throwing: OpenAIError.invalidResponse("Invalid URLResponse type", code: 0))
                return
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                let responseBody = String(data: data, encoding: .utf8) ?? "Cannot parse response"
                continuation.resume(throwing: OpenAIError.invalidResponse(responseBody, code: httpResponse.statusCode))
                return
            }

            do {
                let result = try JSONDecoder().decode(ChatCompletionResult.self, from: data)
                let metadata = preparedRequest.metadata.withRequestID(
                    ProviderResponseNormalizer.requestID(from: httpResponse)
                )
                continuation.resume(returning: ChatCompletionEnvelope(result: result, metadata: metadata))
            } catch {
                continuation.resume(throwing: OpenAIError.decodingError(error))
            }
        }
        task.resume()
    }
}

nonisolated func createChatStreamEnvelopeStream(
    query: ChatQuery,
    configuration: OpenAIConfiguration
) -> AsyncThrowingStream<ChatStreamEnvelope, Error> {
    AsyncThrowingStream { continuation in
        let localTask = Task {
            do {
                let preparedRequest = try await createChatRequest(query: query, configuration: configuration)
                
                let delegate = ChatStreamDelegate(
                    continuation: continuation,
                    metadata: preparedRequest.metadata,
                    family: preparedRequest.family
                )
                let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
                let dataTask = session.dataTask(with: preparedRequest.urlRequest)
                dataTask.resume()
                
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in
            localTask.cancel()
        }
    }
}

#endif

@discardableResult
nonisolated private func processSSEText(
    _ text: String,
    pendingText: inout String,
    statusCode: Int,
    metadata: ChatResponseMetadata,
    family: ProviderFamily,
    state: inout ProviderStreamNormalizationState,
    continuation: AsyncThrowingStream<ChatStreamEnvelope, Error>.Continuation,
    finalize: Bool = false
) throws -> Bool {
    pendingText += text

    while let newlineIndex = pendingText.firstIndex(of: "\n") {
        var line = String(pendingText[..<newlineIndex])
        pendingText.removeSubrange(...newlineIndex)
        if line.hasSuffix("\r") {
            line.removeLast()
        }
        if try processSSELine(
            line,
            statusCode: statusCode,
            metadata: metadata,
            family: family,
            state: &state,
            continuation: continuation
        ) {
            return true
        }
    }

    if finalize, !pendingText.isEmpty {
        let line = pendingText
        pendingText.removeAll(keepingCapacity: false)
        if try processSSELine(
            line,
            statusCode: statusCode,
            metadata: metadata,
            family: family,
            state: &state,
            continuation: continuation
        ) {
            return true
        }
    }

    return false
}

@discardableResult
nonisolated private func processSSELine(
    _ line: String,
    statusCode: Int,
    metadata: ChatResponseMetadata,
    family: ProviderFamily,
    state: inout ProviderStreamNormalizationState,
    continuation: AsyncThrowingStream<ChatStreamEnvelope, Error>.Continuation
) throws -> Bool {
    guard !line.isEmpty, !line.hasPrefix(":") else { return false }

    var dataString = line
    if dataString.hasPrefix("data:") {
        dataString.removeFirst(5)
    }
    dataString = dataString.trimmingCharacters(in: .whitespaces)

    if dataString == "[DONE]" {
        continuation.finish()
        return true
    }

    let chunkData = Data(dataString.utf8)
    do {
        let decodedChunk = try JSONDecoder().decode(ChatStreamResult.self, from: chunkData)
        let normalizedChunk = ProviderResponseNormalizer.normalize(
            streamChunk: decodedChunk,
            family: family,
            state: &state
        )
        continuation.yield(ChatStreamEnvelope(result: normalizedChunk, metadata: metadata))
        return false
    } catch {
        throw OpenAIError.invalidResponse(dataString, code: statusCode)
    }
}

// MARK: - Configuration

/// OpenAI API 配置
///
/// 用于配置 OpenAI 客户端的连接参数和认证信息。
///
/// ## Topics
///
/// ### 创建配置
/// - ``init(token:host:port:scheme:basePath:organizationID:extraBody:extraHeaders:)``
///
/// ### 默认配置
/// - ``default``
///
/// ### 配置属性
/// - ``token``
/// - ``host``
/// - ``port``
/// - ``scheme``
/// - ``basePath``
/// - ``organizationID``
/// - ``extraBody``
/// - ``extraHeaders``
/// - ``baseURL``
///
public struct OpenAIConfiguration : Sendable {
    /// API 访问令牌
    public let token: String
    
    /// API 主机地址
    public let host: String
    
    /// API 端口号
    public let port: Int?
    
    /// URL 协议方案
    public let scheme: String
    
    /// API 基础路径
    public let basePath: String?
    
    /// 组织 ID（可选）
    public let organizationID: String?
    
    /// 额外的请求体参数
    public let extraBody: [String: AnyCodableValue]?
    
    /// 额外的 HTTP 请求头
    public let extraHeaders: [String: String]?
    
    /// 初始化 OpenAI 配置
    ///
    /// - Parameters:
    ///   - token: API 访问令牌
    ///   - host: API 主机地址，默认为 "api.openai.com"
    ///   - port: API 端口号，默认为 nil
    ///   - scheme: URL 协议方案，默认为 "https"
    ///   - basePath: API 基础路径，默认为 nil（使用 "/v1"）
    ///   - organizationID: 组织 ID，默认为 nil
    ///   - extraBody: 额外的请求体参数，默认为 nil
    ///   - extraHeaders: 额外的 HTTP 请求头，默认为 nil
    public init(
        token: String,
        host: String = "api.openai.com",
        port: Int? = nil,
        scheme: String = "https",
        basePath: String? = nil,
        organizationID: String? = nil,
        extraBody: [String: AnyCodableValue]? = nil,
        extraHeaders: [String: String]? = nil
    ) {
        self.token = token
        self.host = host
        self.port = port
        self.scheme = scheme
        self.basePath = basePath
        self.organizationID = organizationID
        self.extraBody = extraBody
        self.extraHeaders = extraHeaders
    }
    
    /// 完整的 API 基础 URL
    public var baseURL: URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        
        let pathPrefix = basePath ?? "/v1"
        components.path = pathPrefix
        
        return components.url
    }
    
    /// 默认配置（从环境变量 OPENAI_API_KEY 读取令牌）
    public static let `default` = OpenAIConfiguration(
        token: ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    )

    /// 默认的 User-Agent 请求头值
    public static var defaultUserAgent: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        if let version, !version.isEmpty {
            return "ShengYanCode/\(version)"
        }
        return "ShengYanCode"
    }

    /// 默认的 X-Title 请求头值
    public static let defaultXTitle = "ShengYanCode"
}

// MARK: - Response Models

/// 聊天完成结果（非流式）
///
/// 表示完整的聊天完成响应，包含所有选择、使用情况统计等信息。
public struct ChatCompletionResult: Codable, Sendable {
    /// 响应的唯一标识符
    public let id: String
    
    /// 对象类型
    public let object: String
    
    /// 创建时间戳
    public let created: Int
    
    /// 使用的模型名称
    public let model: String
    
    /// 响应选择列表
    public let choices: [Choice]
    
    /// Token 使用情况统计
    public let usage: Usage?
    
    /// 系统指纹
    public let systemFingerprint: String?
    
    /// 聊天完成的单个选择
    public struct Choice: Codable, Sendable {
        /// 选择索引
        public let index: Int
        
        /// 助手回复的消息
        public let message: Message
        
        /// 对数概率（可选）
        public let logprobs: String?
        
        /// 完成原因
        public let finishReason: String?
        
        private enum CodingKeys: String, CodingKey {
            case index, message, logprobs
            case finishReason = "finish_reason"
        }
        
        /// 助手消息内容
        public struct Message: Codable, Sendable {
            /// 消息角色
            public let role: String
            
            /// 消息文本内容
            public let content: String?
            
            /// 推理过程（用于支持推理模型）
            public let reasoning: String?
            
            /// 工具调用列表
            public let toolCalls: [ToolCall]?
            
            private enum CodingKeys: String, CodingKey {
                case role, content, reasoning
                case reasoningContent = "reasoning_content"
                case reasoningDetails = "reasoning_details"
                case toolCalls = "tool_calls"
            }
            
            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.role = try container.decode(String.self, forKey: .role)
                self.content = try container.decodeIfPresent(String.self, forKey: .content)
                self.toolCalls = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
                
                if let reasoning = try container.decodeIfPresent(String.self, forKey: .reasoning) {
                    self.reasoning = reasoning
                } else if let reasoningContent = try container.decodeIfPresent(String.self, forKey: .reasoningContent) {
                    self.reasoning = reasoningContent
                } else if let reasoningDetails = try container.decodeIfPresent([ReasoningDetailPayload].self, forKey: .reasoningDetails) {
                    self.reasoning = ProviderResponseNormalizer.extractReasoningText(from: reasoningDetails)
                } else {
                    self.reasoning = nil
                }
            }
            
            public func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(role, forKey: .role)
                try container.encodeIfPresent(content, forKey: .content)
                try container.encodeIfPresent(reasoning, forKey: .reasoning)
                try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
            }
            
            /// 工具调用信息
            public struct ToolCall: Codable, Sendable {
                /// 工具调用 ID
                public let id: String
                
                /// 调用类型
                public let type: String
                
                /// 函数调用详情
                public let function: Function
                
                /// 函数调用详情
                public struct Function: Codable, Sendable {
                    /// 函数名称
                    public let name: String
                    
                    /// 函数参数（JSON 字符串）
                    public let arguments: String
                }
            }
        }
    }
    
    /// Token 使用统计
    public struct Usage: Codable, Sendable {
        /// 提示词使用的 Token 数
        public let promptTokens: Int
        
        /// 完成内容使用的 Token 数
        public let completionTokens: Int
        
        /// 总 Token 数
        public let totalTokens: Int

        /// 缓存的 Token 数
        public let cachedTokens: Int?

        /// 推理过程中使用的 Token 数
        public let reasoningTokens: Int?
        
        private enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
            case cachedTokens = "cached_tokens"
            case reasoningTokens = "reasoning_tokens"
            case promptTokensDetails = "prompt_tokens_details"
            case completionTokensDetails = "completion_tokens_details"
        }

        private struct PromptTokensDetails: Codable {
            let cachedTokens: Int?

            private enum CodingKeys: String, CodingKey {
                case cachedTokens = "cached_tokens"
            }
        }

        private struct CompletionTokensDetails: Codable {
            let reasoningTokens: Int?

            private enum CodingKeys: String, CodingKey {
                case reasoningTokens = "reasoning_tokens"
            }
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            promptTokens = try container.decodeIfPresent(Int.self, forKey: .promptTokens) ?? 0
            completionTokens = try container.decodeIfPresent(Int.self, forKey: .completionTokens) ?? 0
            totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0

            if let cachedTokens = try container.decodeIfPresent(Int.self, forKey: .cachedTokens) {
                self.cachedTokens = cachedTokens
            } else {
                let promptDetails = try container.decodeIfPresent(PromptTokensDetails.self, forKey: .promptTokensDetails)
                self.cachedTokens = promptDetails?.cachedTokens
            }

            if let reasoningTokens = try container.decodeIfPresent(Int.self, forKey: .reasoningTokens) {
                self.reasoningTokens = reasoningTokens
            } else {
                let completionDetails = try container.decodeIfPresent(CompletionTokensDetails.self, forKey: .completionTokensDetails)
                self.reasoningTokens = completionDetails?.reasoningTokens
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(promptTokens, forKey: .promptTokens)
            try container.encode(completionTokens, forKey: .completionTokens)
            try container.encode(totalTokens, forKey: .totalTokens)
            try container.encodeIfPresent(cachedTokens, forKey: .cachedTokens)
            try container.encodeIfPresent(reasoningTokens, forKey: .reasoningTokens)
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, object, created, model, choices, usage
        case systemFingerprint = "system_fingerprint"
    }
}
