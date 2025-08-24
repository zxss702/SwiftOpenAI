import Foundation

public struct ChatStreamResult: Codable {
    public let id: String
    public let object: String
    public let created: Int
    public let model: String
    public let systemFingerprint: String?
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
    
    public struct Choice: Codable {
        public let index: Int
        public let delta: ChoiceDelta
        public let logprobs: String?
        public let finishReason: String?
        
        public init(index: Int, delta: ChoiceDelta, logprobs: String? = nil, finishReason: String? = nil) {
            self.index = index
            self.delta = delta
            self.logprobs = logprobs
            self.finishReason = finishReason
        }
        
        private enum CodingKeys: String, CodingKey {
            case index, delta, logprobs
            case finishReason = "finish_reason"
        }
        
        public struct ChoiceDelta: Codable {
            public let role: String?
            public let content: String?
            public let reasoning: String?
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
                try container.encodeIfPresent(role, forKey: .role)
                try container.encodeIfPresent(content, forKey: .content)
                try container.encodeIfPresent(reasoning, forKey: .reasoning)
                try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
            }
            
            public struct ChoiceDeltaToolCall: Codable {
                public let index: Int
                public let id: String?
                public let type: String?
                public let function: ChoiceDeltaToolCallFunction?
                
                public init(index: Int, id: String? = nil, type: String? = nil, function: ChoiceDeltaToolCallFunction? = nil) {
                    self.index = index
                    self.id = id
                    self.type = type
                    self.function = function
                }
                
                public struct ChoiceDeltaToolCallFunction: Codable {
                    public let name: String?
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
