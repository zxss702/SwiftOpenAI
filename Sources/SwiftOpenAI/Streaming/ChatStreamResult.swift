import Foundation

/// 聊天流式响应结果
///
/// 表示流式聊天完成的单个响应片段，
/// 包含增量更新的消息内容和元数据。
///
/// ## Topics
///
/// ### 响应属性
/// - ``id``
/// - ``object``
/// - ``created``
/// - ``model``
/// - ``systemFingerprint``
/// - ``choices``
///
/// ### 初始化
/// - ``init(id:object:created:model:systemFingerprint:choices:)``
///
public struct ChatStreamResult: Codable {
    /// 响应的唯一标识符
    public let id: String
    
    /// 对象类型
    public let object: String
    
    /// 创建时间戳
    public let created: Int
    
    /// 使用的模型名称
    public let model: String
    
    /// 系统指纹
    public let systemFingerprint: String?
    
    /// 响应选择列表
    public let choices: [Choice]
    
    public init(id: String, object: String, created: Int, model: String, systemFingerprint: String? = nil, choices: [Choice]) {
        self.id = id
        self.object = object
        self.created = created
        self.model = model
        self.systemFingerprint = systemFingerprint
        self.choices = choices
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, object, created, model
        case systemFingerprint = "system_fingerprint"
        case choices
    }
    
    /// 流式响应的单个选择
    public struct Choice: Codable {
        /// 选择索引
        public let index: Int
        
        /// 增量更新的消息内容
        public let delta: ChoiceDelta
        
        /// 对数概率（可选）
        public let logprobs: String?
        
        /// 完成原因
        public let finishReason: String?
        
        /// Token 使用统计信息
        public let usage: UsageInfo?
        
        public init(index: Int, delta: ChoiceDelta, logprobs: String? = nil, finishReason: String? = nil, usage: UsageInfo? = nil) {
            self.index = index
            self.delta = delta
            self.logprobs = logprobs
            self.finishReason = finishReason
            self.usage = usage
        }
        
        private enum CodingKeys: String, CodingKey {
            case index, delta, logprobs, usage
            case finishReason = "finish_reason"
        }
        
        /// Token 使用统计信息
        public struct UsageInfo: Codable {
            /// 提示词使用的 Token 数
            public let promptTokens: Int?
            
            /// 完成内容使用的 Token 数
            public let completionTokens: Int?
            
            /// 总 Token 数
            public let totalTokens: Int?
            
            /// 缓存的 Token 数
            public let cachedTokens: Int?
            
            public init(promptTokens: Int? = nil, completionTokens: Int? = nil, totalTokens: Int? = nil, cachedTokens: Int? = nil) {
                self.promptTokens = promptTokens
                self.completionTokens = completionTokens
                self.totalTokens = totalTokens
                self.cachedTokens = cachedTokens
            }
            
            private enum CodingKeys: String, CodingKey {
                case promptTokens = "prompt_tokens"
                case completionTokens = "completion_tokens"
                case totalTokens = "total_tokens"
                case cachedTokens = "cached_tokens"
            }
        }
        
        /// 增量消息内容
        ///
        /// 表示流式响应中的增量更新部分。
        public struct ChoiceDelta: Codable {
            /// 消息角色（仅在第一个片段中出现）
            public let role: String?
            
            /// 增量文本内容
            public let content: String?
            
            /// 推理过程（用于支持推理模型）
            public let reasoning: String?
            
            /// 工具调用增量列表
            public let toolCalls: [ChoiceDeltaToolCall]?
            
            public init(role: String? = nil, content: String? = nil, reasoning: String? = nil, toolCalls: [ChoiceDeltaToolCall]? = nil) {
                self.role = role
                self.content = content
                self.reasoning = reasoning
                self.toolCalls = toolCalls
            }
            
            private enum CodingKeys: String, CodingKey {
                case role, content, reasoning
                case reasoningContent = "reasoning_content"
                case toolCalls = "tool_calls"
            }
            
            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.role = try container.decodeIfPresent(String.self, forKey: .role)
                self.content = try container.decodeIfPresent(String.self, forKey: .content)
                self.toolCalls = try container.decodeIfPresent([ChoiceDeltaToolCall].self, forKey: .toolCalls)
                
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
                try container.encodeIfPresent(role, forKey: .role)
                try container.encodeIfPresent(content, forKey: .content)
                try container.encodeIfPresent(reasoning, forKey: .reasoning)
                try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
            }
            
            /// 增量工具调用
            public struct ChoiceDeltaToolCall: Codable {
                /// 工具调用在列表中的索引
                public let index: Int
                
                /// 工具调用 ID
                public let id: String?
                
                /// 调用类型
                public let type: String?
                
                /// 函数调用增量
                public let function: ChoiceDeltaToolCallFunction?
                
                public init(index: Int, id: String? = nil, type: String? = nil, function: ChoiceDeltaToolCallFunction? = nil) {
                    self.index = index
                    self.id = id
                    self.type = type
                    self.function = function
                }
                
                /// 函数调用增量
                public struct ChoiceDeltaToolCallFunction: Codable {
                    /// 函数名称（增量）
                    public let name: String?
                    
                    /// 函数参数（增量，JSON 字符串片段）
                    public let arguments: String?
                    
                    public init(name: String? = nil, arguments: String? = nil) {
                        self.name = name
                        self.arguments = arguments
                    }
                }
            }
        }
    }
}
