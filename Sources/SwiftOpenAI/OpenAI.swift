import Foundation

public class OpenAI {
    private let configuration: OpenAIConfiguration
    private let urlSession: URLSession
    
    public init(configuration: OpenAIConfiguration? = nil) {
        self.configuration = configuration ?? OpenAIConfiguration.default
        self.urlSession = URLSession(configuration: .default)
    }
    
    /// 发送聊天消息，支持流式传输
    public func chatsStream(query: ChatQuery) -> AsyncThrowingStream<ChatStreamResult, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try createChatRequest(query: query)
                    
                    let (bytes, response) = try await urlSession.bytes(for: request)
                    
                    let httpResponse = response as? HTTPURLResponse
                    guard let httpResponse = httpResponse,
                          200...299 ~= httpResponse.statusCode else {
                        // 读取响应内容用于调试
                        var responseBody = ""
                        do {
                            for try await line in bytes.lines {
                                responseBody += line + "\n"
                            }
                        } catch {
                            responseBody = "无法读取响应内容: \(error)"
                        }
                        
                        let statusCode = httpResponse?.statusCode ?? -1
                        throw OpenAIError.invalidResponse("HTTP状态码: \(statusCode), 响应内容: \(responseBody)")
                    }
                    
                    for try await line in bytes.lines {
                        guard !line.isEmpty, line.hasPrefix("data: ") else { continue }
                        
                        let dataString = String(line.dropFirst(6))
                        
                        // 检查是否为结束标记
                        if dataString == "[DONE]" {
                            continuation.finish()
                            return
                        }
                        
                        do {
                            let data = Data(dataString.utf8)
                            let streamResult = try JSONDecoder().decode(ChatStreamResult.self, from: data)
                            continuation.yield(streamResult)
                        } catch {
                            // 忽略解析失败的行，继续处理下一行
                            continue
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// 发送聊天消息，非流式传输
    public func chats(query: ChatQuery) async throws -> ChatCompletionResult {
        let modifiedQuery = query
        let request = try createChatRequest(query: modifiedQuery)
        
        let (data, response) = try await urlSession.data(for: request)
        
        let httpResponse = response as? HTTPURLResponse
        guard let httpResponse = httpResponse,
              200...299 ~= httpResponse.statusCode else {
            // 包含响应内容用于调试
            let responseBody = String(data: data, encoding: .utf8) ?? "无法解析响应内容（非UTF-8）"
            let statusCode = httpResponse?.statusCode ?? -1
            throw OpenAIError.invalidResponse("HTTP状态码: \(statusCode), 响应内容: \(responseBody)")
        }
        
        do {
            let result = try JSONDecoder().decode(ChatCompletionResult.self, from: data)
            return result
        } catch {
            throw OpenAIError.decodingError(error)
        }
    }
    
    private func createChatRequest(query: ChatQuery) throws -> URLRequest {
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

        // Add default/custom headers (custom can override defaults)
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
        
        // 添加自定义extra_body支持
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
        
        // 合并extra_body - 首先添加配置级别的
        if let extraBody = configuration.extraBody {
            for (key, value) in extraBody {
                requestBody[key] = value
            }
        }
        
        // 然后添加请求级别的 extra_body，它会覆盖配置级别的同名字段
        if let queryExtraBody = query.extraBody {
            for (key, value) in queryExtraBody {
                requestBody[key] = value.anyValue
            }
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
        
        return request
    }
}

// MARK: - 配置
public struct OpenAIConfiguration {
    public let token: String
    public let host: String
    public let port: Int?
    public let scheme: String
    public let basePath: String?
    public let organizationID: String?
    public let extraBody: [String: Any]?
    public let extraHeaders: [String: String]?
    
    public init(
        token: String,
        host: String = "api.openai.com",
        port: Int? = nil,
        scheme: String = "https",
        basePath: String? = nil,
        organizationID: String? = nil,
        extraBody: [String: Any]? = nil,
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
    
    public var baseURL: URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        
        let pathPrefix = basePath ?? "/v1"
        components.path = pathPrefix
        
        return components.url
    }
    
    public static let `default` = OpenAIConfiguration(
        token: ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    )

    public static var defaultUserAgent: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        if let version, !version.isEmpty {
            return "ShengYanCode/\(version)"
        }
        return "ShengYanCode"
    }

    public static let defaultXTitle = "ShengYanCode"
}

// MARK: - 聊天完成结果（非流式）
public struct ChatCompletionResult: Codable {
    public let id: String
    public let object: String
    public let created: Int
    public let model: String
    public let choices: [Choice]
    public let usage: Usage?
    public let systemFingerprint: String?
    
    public struct Choice: Codable {
        public let index: Int
        public let message: Message
        public let logprobs: String?
        public let finishReason: String?
        
        private enum CodingKeys: String, CodingKey {
            case index, message, logprobs
            case finishReason = "finish_reason"
        }
        
        public struct Message: Codable {
            public let role: String
            public let content: String?
            public let reasoning: String?
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
                
                // 尝试两种可能的 reasoning 字段名
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
            
            public struct ToolCall: Codable {
                public let id: String
                public let type: String
                public let function: Function
                
                public struct Function: Codable {
                    public let name: String
                    public let arguments: String
                }
            }
        }
    }
    
    public struct Usage: Codable {
        public let promptTokens: Int
        public let completionTokens: Int
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
