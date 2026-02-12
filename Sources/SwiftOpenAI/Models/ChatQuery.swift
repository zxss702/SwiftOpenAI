import Foundation

/// 聊天查询参数
///
/// 封装发送给 OpenAI Chat Completions API 的所有参数。
///
/// ## Topics
///
/// ### 初始化
/// - ``init(messages:model:frequencyPenalty:maxCompletionTokens:n:parallelToolCalls:prediction:presencePenalty:responseFormat:stop:temperature:toolChoice:tools:topP:user:stream:extraBody:)``
///
/// ### 消息相关
/// - ``messages``
/// - ``ChatCompletionMessageParam``
///
/// ### 模型配置
/// - ``model``
/// - ``temperature``
/// - ``topP``
///
/// ### Token 限制
/// - ``maxCompletionTokens``
/// - ``n``
///
/// ### 工具调用
/// - ``tools``
/// - ``toolChoice``
/// - ``ChatCompletionToolParam``
///
public struct ChatQuery: Codable {
    public let messages: [ChatCompletionMessageParam]
    public let model: String
    public let frequencyPenalty: Double?
    public let maxCompletionTokens: Int?
    public let n: Int?
    public let parallelToolCalls: Bool?
    public let prediction: PredictedOutputConfig?
    public let presencePenalty: Double?
    public let responseFormat: ResponseFormat?
    public let stop: Stop?
    public let temperature: Double?
    public let toolChoice: ChatCompletionFunctionCallOptionParam?
    public let tools: [ChatCompletionToolParam]?
    public let topP: Double?
    public let user: String?
    public let stream: Bool?
    public let extraBody: [String: AnyCodableValue]?
    
    public init(
        messages: [ChatCompletionMessageParam],
        model: String,
        frequencyPenalty: Double? = nil,
        maxCompletionTokens: Int? = nil,
        n: Int? = nil,
        parallelToolCalls: Bool? = nil,
        prediction: PredictedOutputConfig? = nil,
        presencePenalty: Double? = nil,
        responseFormat: ResponseFormat? = nil,
        stop: Stop? = nil,
        temperature: Double? = nil,
        toolChoice: ChatCompletionFunctionCallOptionParam? = nil,
        tools: [ChatCompletionToolParam]? = nil,
        topP: Double? = nil,
        user: String? = nil,
        stream: Bool? = nil,
        extraBody: [String: AnyCodableValue]? = nil
    ) {
        self.messages = messages
        self.model = model
        self.frequencyPenalty = frequencyPenalty
        self.maxCompletionTokens = maxCompletionTokens
        self.n = n
        self.parallelToolCalls = parallelToolCalls
        self.prediction = prediction
        self.presencePenalty = presencePenalty
        self.responseFormat = responseFormat
        self.stop = stop
        self.temperature = temperature
        self.toolChoice = toolChoice
        self.tools = tools
        self.topP = topP
        self.user = user
        self.stream = stream
        self.extraBody = extraBody
    }
    
    // MARK: - Nested Types
    
    /// 停止序列
    ///
    /// 可以是单个字符串或字符串数组。
    public enum Stop: Codable {
        case string(String)
        case array([String])
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self = .string(string)
            } else {
                self = .array(try container.decode([String].self))
            }
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let string):
                try container.encode(string)
            case .array(let array):
                try container.encode(array)
            }
        }
    }
    
    /// 预测输出配置
    public struct PredictedOutputConfig: Codable {
        public let type: String
        public let content: String?
        
        public init(type: String, content: String? = nil) {
            self.type = type
            self.content = content
        }
    }
    
    /// 响应格式配置
    ///
    /// 用于指定 JSON Schema 等结构化输出格式。
    public struct ResponseFormat: Codable {
        public let type: String
        public let jsonSchema: JSONSchema?
        
        public init(type: String, jsonSchema: JSONSchema? = nil) {
            self.type = type
            self.jsonSchema = jsonSchema
        }
        
        /// JSON Schema 定义
        public struct JSONSchema: Codable {
            public let name: String
            public let description: String?
            public let schema: String  // 简化为字符串，避免复杂的[String: Any]编码
            
            public init(name: String, description: String? = nil, schema: String) {
                self.name = name
                self.description = description
                self.schema = schema
            }
        }
    }
    
    /// 聊天消息参数
    ///
    /// 支持系统、用户、助手和工具四种消息类型。
    public enum ChatCompletionMessageParam: Codable, Sendable {
        case system(SystemMessageParam)
        case user(UserMessageParam)
        case assistant(AssistantMessageParam)
        case tool(ToolMessageParam)
        
        public init?(role: Role, content: String?, name: String? = nil, toolCalls: [AssistantMessageParam.ToolCallParam]? = nil, toolCallId: String? = nil, reasoningContent: String? = nil) {
            switch role {
            case .system:
                guard let content = content else { return nil }
                self = .system(SystemMessageParam(content: .textContent(content), name: name))
            case .user:
                guard let content = content else { return nil }
                self = .user(UserMessageParam(content: .string(content), name: name))
            case .assistant:
                self = .assistant(AssistantMessageParam(content: content, name: name, toolCalls: toolCalls, reasoningContent: reasoningContent))
            case .tool:
                guard let content = content, let toolCallId = toolCallId else { return nil }
                self = .tool(ToolMessageParam(content: .textContent(content), toolCallId: toolCallId))
            }
        }
        
        public var role: Role {
            switch self {
            case .system: return .system
            case .user: return .user
            case .assistant: return .assistant
            case .tool: return .tool
            }
        }
        
        public enum Role: String, Codable {
            case system, user, assistant, tool
        }
        
        // MARK: - Codable Implementation
        private enum CodingKeys: String, CodingKey {
            case role, content, name, toolCalls = "tool_calls", toolCallId = "tool_call_id", reasoningContent = "reasoning_content"
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let role = try container.decode(Role.self, forKey: .role)
            
            switch role {
            case .system:
                let content = try container.decodeIfPresent(String.self, forKey: .content)
                let name = try container.decodeIfPresent(String.self, forKey: .name)
                self = .system(SystemMessageParam(
                    content: .textContent(content ?? ""),
                    name: name
                ))
                
            case .user:
                let name = try container.decodeIfPresent(String.self, forKey: .name)
                
                // 尝试解码为字符串或数组
                if let stringContent = try? container.decode(String.self, forKey: .content) {
                    self = .user(UserMessageParam(content: .string(stringContent), name: name))
                } else if let arrayContent = try? container.decode([UserMessageParam.Content.ContentPart].self, forKey: .content) {
                    self = .user(UserMessageParam(content: .contentParts(arrayContent), name: name))
                } else {
                    self = .user(UserMessageParam(content: .string(""), name: name))
                }
                
            case .assistant:
                let content = try container.decodeIfPresent(String.self, forKey: .content)
                let name = try container.decodeIfPresent(String.self, forKey: .name)
                let toolCalls = try container.decodeIfPresent([AssistantMessageParam.ToolCallParam].self, forKey: .toolCalls)
                let reasoningContent = try container.decodeIfPresent(String.self, forKey: .reasoningContent)
                self = .assistant(AssistantMessageParam(content: content, name: name, toolCalls: toolCalls, reasoningContent: reasoningContent))
                
            case .tool:
                let toolCallId = try container.decode(String.self, forKey: .toolCallId)
                
                // 尝试解码为字符串或数组
                if let stringContent = try? container.decode(String.self, forKey: .content) {
                    self = .tool(ToolMessageParam(content: .textContent(stringContent), toolCallId: toolCallId))
                } else if let arrayContent = try? container.decode([ToolMessageParam.Content.ContentPart].self, forKey: .content) {
                    self = .tool(ToolMessageParam(content: .contentParts(arrayContent), toolCallId: toolCallId))
                } else {
                    self = .tool(ToolMessageParam(content: .textContent(""), toolCallId: toolCallId))
                }
            }
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            
            switch self {
            case .system(let systemParam):
                try container.encode(Role.system, forKey: .role)
                if case .textContent(let text) = systemParam.content {
                    try container.encode(text, forKey: .content)
                }
                try container.encodeIfPresent(systemParam.name, forKey: .name)
                
            case .user(let userParam):
                try container.encode(Role.user, forKey: .role)
                try container.encode(userParam.content, forKey: .content)
                try container.encodeIfPresent(userParam.name, forKey: .name)
                
            case .assistant(let assistantParam):
                try container.encode(Role.assistant, forKey: .role)
                try container.encodeIfPresent(assistantParam.content, forKey: .content)
                try container.encodeIfPresent(assistantParam.name, forKey: .name)
                try container.encodeIfPresent(assistantParam.toolCalls, forKey: .toolCalls)
                try container.encodeIfPresent(assistantParam.reasoningContent, forKey: .reasoningContent)
                
            case .tool(let toolParam):
                try container.encode(Role.tool, forKey: .role)
                try container.encode(toolParam.content, forKey: .content)
                try container.encode(toolParam.toolCallId, forKey: .toolCallId)
            }
        }
    }
    
    /// 聊天工具参数
    ///
    /// 定义可供模型调用的函数工具。
    public struct ChatCompletionToolParam: Codable {
        public let type: String
        public let function: Function
        
        public init(type: String, function: Function) {
            self.type = type
            self.function = function
        }
        
        /// 函数定义
        public struct Function: Codable {
            public let name: String
            public let description: String?
            public let parameters: ParametersContainer?  // 使用包装器类型
            
            public init(name: String, description: String? = nil, parameters: [String: Any]? = nil) {
                self.name = name
                self.description = description
                self.parameters = parameters.map { ParametersContainer($0) }
            }
            
            /// 参数容器
            ///
            /// 用于处理 `[String: Any]` 类型的参数字典。
            public struct ParametersContainer: Codable, CustomStringConvertible {
                private let data: [String: AnyCodableValue]
                
                public init(_ dict: [String: Any]) {
                    self.data = dict.mapValues { AnyCodableValue.from($0) }
                }
                
                public func encode(to encoder: Encoder) throws {
                    try data.encode(to: encoder)
                }
                
                public init(from decoder: Decoder) throws {
                    data = try [String: AnyCodableValue](from: decoder)
                }
                
                /// 转换为字典
                public func toDictionary() -> [String: Any] {
                    return data.mapValues { $0.anyValue }
                }
                
                /// 转换为 JSON 字符串
                public func toJSONString() -> String? {
                    do {
                        let dict = toDictionary()
                        let jsonData = try JSONSerialization.data(withJSONObject: dict, options: [])
                        return String(data: jsonData, encoding: .utf8)
                    } catch {
                        return nil
                    }
                }
                
                // CustomStringConvertible 实现
                public var description: String {
                    return toJSONString() ?? "{}"
                }
            }
        }
    }
    
    /// 函数调用选项参数
    ///
    /// 控制模型如何选择要调用的函数。
    public enum ChatCompletionFunctionCallOptionParam: Codable {
        case none
        case auto
        case required
        case function(String)
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                switch string {
                case "none":
                    self = .none
                case "auto":
                    self = .auto
                case "required":
                    self = .required
                default:
                    self = .function(string)
                }
            } else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "无法解码ChatCompletionFunctionCallOptionParam"))
            }
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .none:
                try container.encode("none")
            case .auto:
                try container.encode("auto")
            case .required:
                try container.encode("required")
            case .function(let name):
                try container.encode(name)
            }
        }
    }
}

// MARK: - Coding Helpers

/// 通用编码键
struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    
    init?(stringValue: String) {
        self.stringValue = stringValue
    }
    
    init?(intValue: Int) {
        self.intValue = intValue
        self.stringValue = "\(intValue)"
    }
}

// MARK: - Any Codable Value

/// 可编码的任意值
///
/// 支持动态类型的 JSON 编解码。
public enum AnyCodableValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case object([String: AnyCodableValue])
    case null
    
    /// 从 Any 类型创建
    ///
    /// - Parameter value: 任意 Swift 值
    /// - Returns: 对应的 AnyCodableValue
    public static func from(_ value: Any) -> AnyCodableValue {
        if let string = value as? String {
            return .string(string)
        } else if let int = value as? Int {
            return .int(int)
        } else if let double = value as? Double {
            return .double(double)
        } else if let bool = value as? Bool {
            return .bool(bool)
        } else if let array = value as? [Any] {
            return .array(array.map { AnyCodableValue.from($0) })
        } else if let dict = value as? [String: Any] {
            return .object(dict.mapValues { AnyCodableValue.from($0) })
        } else {
            return .null
        }
    }
    
    /// 转换为 Any 类型
    public var anyValue: Any {
        switch self {
        case .string(let string):
            return string
        case .int(let int):
            return int
        case .double(let double):
            return double
        case .bool(let bool):
            return bool
        case .array(let array):
            return array.map { $0.anyValue }
        case .object(let dict):
            return dict.mapValues { $0.anyValue }
        case .null:
            return NSNull()
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([AnyCodableValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: AnyCodableValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "无法解码AnyCodableValue"))
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch self {
        case .string(let string):
            try container.encode(string)
        case .int(let int):
            try container.encode(int)
        case .double(let double):
            try container.encode(double)
        case .bool(let bool):
            try container.encode(bool)
        case .array(let array):
            try container.encode(array)
        case .object(let object):
            try container.encode(object)
        case .null:
            try container.encodeNil()
        }
    }
    
}
