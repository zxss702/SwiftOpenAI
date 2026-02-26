import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
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
        
        return AsyncThrowingStream { continuation in
            let task = Task { [configuration] in
                do {
                    let request = try await createChatRequest(query: query, configuration: configuration)
#if canImport(FoundationNetworking)
                    let (data, response) = try await URLSession(configuration: .default).data(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          200...299 ~= httpResponse.statusCode else {
                        let responseBody = String(data: data, encoding: .utf8) ?? "无法解析响应内容（非UTF-8）"
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                        throw OpenAIError.invalidResponse("HTTP状态码: \(statusCode), 响应内容: \(responseBody)")
                    }

                    let responseText = String(data: data, encoding: .utf8) ?? ""
                    for rawLine in responseText.split(whereSeparator: \.isNewline) {
                        try Task.checkCancellation()
                        let line = String(rawLine)
                        guard !line.isEmpty, !line.hasPrefix(":") else { continue }

                        let dataString = line.replacingOccurrences(of: "data:", with: "").trimmingCharacters(in: .whitespaces)
                        if dataString == "[DONE]" {
                            continuation.finish()
                            return
                        }

                        let chunk = Data(dataString.utf8)
                        let streamResult = try JSONDecoder().decode(ChatStreamResult.self, from: chunk)
                        continuation.yield(streamResult)
                    }
#else
                    let (bytes, response) = try await URLSession(configuration: .default).bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse,
                          200...299 ~= httpResponse.statusCode else {
                        var responseBody = ""
                        do {
                            for try await line in bytes.lines {
                                responseBody += line + "\n"
                            }
                        } catch {
                            responseBody = "无法读取响应内容: \(error)"
                        }
                        
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                        throw OpenAIError.invalidResponse("HTTP状态码: \(statusCode), 响应内容: \(responseBody)")
                    }
                    
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard !line.isEmpty, !line.hasPrefix(":") else { continue }
                        
                        let dataString = line.replacingOccurrences(of: "data:", with: "").trimmingCharacters(in: .whitespaces)
                        
                        if dataString == "[DONE]" {
                            continuation.finish()
                            return
                        }
                        
                        let data = Data(dataString.utf8)
                        let streamResult = try JSONDecoder().decode(ChatStreamResult.self, from: data)
                        continuation.yield(streamResult)
                    }
#endif
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
        let request = try await createChatRequest(query: query, configuration: configuration)
        let (data, response) = try await URLSession(configuration: .default).data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            let responseBody = String(data: data, encoding: .utf8) ?? "无法解析响应内容（非UTF-8）"
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw OpenAIError.invalidResponse("HTTP状态码: \(statusCode), 响应内容: \(responseBody)")
        }
        
        do {
            let result = try JSONDecoder().decode(ChatCompletionResult.self, from: data)
            return result
        } catch {
            throw OpenAIError.decodingError(error)
        }
    }
    
}

nonisolated func createChatRequest(query: ChatQuery, configuration: OpenAIConfiguration) async throws -> URLRequest {
    guard let baseURL = configuration.baseURL else {
        throw OpenAIError.invalidURL
    }
    
    let url = baseURL.appendingPathComponent("chat/completions")
    var request = URLRequest(url: url)
    
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
    
    if let organizationID = configuration.organizationID {
        request.setValue(organizationID, forHTTPHeaderField: "OpenAI-Organization")
    }

    var headers = configuration.extraHeaders ?? [:]
    if headers["User-Agent"] == nil {
        headers["User-Agent"] = OpenAIConfiguration.defaultUserAgent
    }
    if headers["X-Title"] == nil {
        headers["X-Title"] = OpenAIConfiguration.defaultXTitle
    }
    
    for (key, value) in headers {
        request.setValue(value, forHTTPHeaderField: key)
    }
    
    var requestBody: [String: Any] = [:]
    
    do {
        let encoder = JSONEncoder()
        let data = try encoder.encode(query)
        if let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
            requestBody = jsonObject
        }
    } catch {
        throw OpenAIError.decodingError(error)
    }
    
    if let extraBody = configuration.extraBody {
        for (key, value) in extraBody {
            requestBody[key] = value
        }
    }
    
    if let queryExtraBody = query.extraBody {
        for (key, value) in queryExtraBody {
            requestBody[key] = value.anyValue
        }
    }
    
    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
    
    return request
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
public struct ChatCompletionResult: Codable {
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
    public struct Choice: Codable {
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
        public struct Message: Codable {
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
            public struct ToolCall: Codable {
                /// 工具调用 ID
                public let id: String
                
                /// 调用类型
                public let type: String
                
                /// 函数调用详情
                public let function: Function
                
                /// 函数调用详情
                public struct Function: Codable {
                    /// 函数名称
                    public let name: String
                    
                    /// 函数参数（JSON 字符串）
                    public let arguments: String
                }
            }
        }
    }
    
    /// Token 使用统计
    public struct Usage: Codable {
        /// 提示词使用的 Token 数
        public let promptTokens: Int
        
        /// 完成内容使用的 Token 数
        public let completionTokens: Int
        
        /// 总 Token 数
        public let totalTokens: Int
        
        private enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, object, created, model, choices, usage
        case systemFingerprint = "system_fingerprint"
    }
}
