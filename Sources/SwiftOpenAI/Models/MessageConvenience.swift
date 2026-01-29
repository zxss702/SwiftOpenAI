import Foundation

// MARK: - Type Aliases

/// OpenAI 消息类型别名
public typealias OpenAIMessage = ChatQuery.ChatCompletionMessageParam

/// OpenAI 工具类型别名
public typealias OpenAITool = ChatQuery.ChatCompletionToolParam

/// OpenAI 函数定义类型别名
public typealias OpenAIFunctionDefinition = ChatQuery.ChatCompletionToolParam.Function

// MARK: - Message Parameter Types

// MARK: - User Message

/// 用户消息参数
///
/// 表示来自用户的输入消息，支持文本和图片内容。
public struct UserMessageParam: Codable {
    public let content: Content
    public let name: String?
    
    public init(content: Content, name: String? = nil) {
        self.content = content
        self.name = name
    }
    
    /// 消息内容
    public enum Content: Codable {
        case string(String)
        case contentParts([ContentPart])
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self = .string(string)
            } else {
                self = .contentParts(try container.decode([ContentPart].self))
            }
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let string):
                try container.encode(string)
            case .contentParts(let parts):
                try container.encode(parts)
            }
        }
        
        /// 内容部分
        ///
        /// 可以是文本或图片。
        public enum ContentPart: Codable {
            case text(TextContent)
            case image(ImageContent)
            
            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                let type = try container.decode(String.self, forKey: .type)
                
                switch type {
                case "text":
                    self = .text(try TextContent(from: decoder))
                case "image_url":
                    self = .image(try ImageContent(from: decoder))
                default:
                    throw DecodingError.dataCorrupted(DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "未知的content部分类型: \(type)"
                    ))
                }
            }
            
            public func encode(to encoder: Encoder) throws {
                switch self {
                case .text(let textContent):
                    try textContent.encode(to: encoder)
                case .image(let imageContent):
                    try imageContent.encode(to: encoder)
                }
            }
            
            private enum CodingKeys: String, CodingKey {
                case type
            }
            
            /// 文本内容
            public struct TextContent: Codable {
                public var type: String = "text"
                public let text: String
                
                public init(text: String) {
                    self.text = text
                }
            }
            
            /// 图片内容
            public struct ImageContent: Codable {
                public let type: String = "image_url"
                public let imageUrl: ImageURL
                
                public init(imageUrl: ImageURL) {
                    self.imageUrl = imageUrl
                }
                
                private enum CodingKeys: String, CodingKey {
                    case type
                    case imageUrl = "image_url"
                }
                
                /// 图片 URL 或 Base64 数据
                public struct ImageURL: Codable {
                    public let url: String
                    public let detail: Detail
                    
                    public init(url: String, detail: Detail = .auto) {
                        self.url = url
                        self.detail = detail
                    }
                    
                    public init(imageData: Data, detail: Detail = .auto) {
                        let base64String = imageData.base64EncodedString()
                        let mimeType = Self.detectMimeType(from: imageData)
                        self.url = "data:\(mimeType);base64,\(base64String)"
                        self.detail = detail
                    }
                    
                    /// 检测图片 MIME 类型
                    private static func detectMimeType(from data: Data) -> String {
                        guard data.count >= 4 else { return "image/jpeg" }
                        
                        let bytes = data.prefix(4)
                        let header = bytes.map { $0 }
                        
                        if header.starts(with: [0xFF, 0xD8, 0xFF]) {
                            return "image/jpeg"
                        } else if header.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
                            return "image/png"
                        } else if header.starts(with: [0x47, 0x49, 0x46]) {
                            return "image/gif"
                        } else if header.starts(with: [0x52, 0x49, 0x46, 0x46]) {
                            return "image/webp"
                        } else {
                            return "image/jpeg" // 默认
                        }
                    }
                    
                    /// 图片细节级别
                    public enum Detail: String, Codable, CaseIterable {
                        case low
                        case high 
                        case auto
                    }
                }
            }
        }
    }
}

// MARK: - System Message

/// 系统消息参数
///
/// 表示系统级指令消息。
public struct SystemMessageParam: Codable {
    public let content: TextContent
    public let name: String?
    
    public init(content: TextContent, name: String? = nil) {
        self.content = content
        self.name = name
    }
    
    public enum TextContent: Codable {
        case textContent(String)
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            self = .textContent(try container.decode(String.self))
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .textContent(let text):
                try container.encode(text)
            }
        }
    }
}

// MARK: - Assistant Message

/// 助手消息参数
///
/// 表示来自 AI 助手的回复消息，支持文本内容、工具调用和推理内容。
///
/// 当使用 OpenAI 推理模型（如 o1、o3 系列）时，助手消息可能包含推理过程。
/// 如果启用了 thinking 功能且消息包含工具调用，则必须提供 `reasoningContent`。
///
/// ## Topics
///
/// ### 属性
/// - ``content``
/// - ``name``
/// - ``toolCalls``
/// - ``reasoningContent``
///
/// ### 工具调用
/// - ``ToolCallParam``
public struct AssistantMessageParam: Codable {
    
    /// 消息的文本内容
    public let content: String?
    
    /// 消息的可选名称标识符
    public let name: String?
    
    /// 助手请求的工具调用列表
    public let toolCalls: [ToolCallParam]?
    
    /// 推理模型的思考过程内容
    ///
    /// 当使用 o1、o3 等推理模型并启用 thinking 功能时，
    /// 此字段包含模型的内部推理过程。在多轮对话中，
    /// 如果 assistant 消息包含工具调用，则此字段为必填。
    public let reasoningContent: String?
    
    /// 创建助手消息参数
    /// - Parameters:
    ///   - content: 消息的文本内容
    ///   - name: 消息的可选名称标识符
    ///   - toolCalls: 助手请求的工具调用列表
    ///   - reasoningContent: 推理模型的思考过程内容
    public init(
        content: String? = nil,
        name: String? = nil,
        toolCalls: [ToolCallParam]? = nil,
        reasoningContent: String? = nil
    ) {
        self.content = content
        self.name = name
        self.toolCalls = toolCalls
        self.reasoningContent = reasoningContent
    }
    
    private enum CodingKeys: String, CodingKey {
        case content, name
        case toolCalls = "tool_calls"
        case reasoningContent = "reasoning_content"
    }
    
    /// 工具调用参数
    public struct ToolCallParam: Codable {
        public let id: String
        public let type: String
        public let function: FunctionCall
        
        public init(id: String, type: String = "function", function: FunctionCall) {
            self.id = id
            self.type = type
            self.function = function
        }
        
        public struct FunctionCall: Codable {
            public let name: String
            public let arguments: String
            
            public init(name: String, arguments: String) {
                self.name = name
                self.arguments = arguments
            }
        }
    }
}

// MARK: - Tool Message

/// 工具消息参数
///
/// 表示工具执行结果的消息。
public struct ToolMessageParam: Codable {
    public let content: Content
    public let toolCallId: String
    
    public init(content: Content, toolCallId: String) {
        self.content = content
        self.toolCallId = toolCallId
    }
    
    private enum CodingKeys: String, CodingKey {
        case content
        case toolCallId = "tool_call_id"
    }
    
    public enum Content: Codable {
        case textContent(String)
        case contentParts([ContentPart])
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self = .textContent(string)
            } else {
                self = .contentParts(try container.decode([ContentPart].self))
            }
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .textContent(let text):
                try container.encode(text)
            case .contentParts(let parts):
                try container.encode(parts)
            }
        }
        
        public enum ContentPart: Codable {
            case text(TextContent)
            case image(ImageContent)
            
            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                let type = try container.decode(String.self, forKey: .type)
                
                switch type {
                case "text":
                    self = .text(try TextContent(from: decoder))
                case "image_url":
                    self = .image(try ImageContent(from: decoder))
                default:
                    throw DecodingError.dataCorrupted(DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "未知的content部分类型: \(type)"
                    ))
                }
            }
            
            public func encode(to encoder: Encoder) throws {
                switch self {
                case .text(let textContent):
                    try textContent.encode(to: encoder)
                case .image(let imageContent):
                    try imageContent.encode(to: encoder)
                }
            }
            
            private enum CodingKeys: String, CodingKey {
                case type
            }
            
            public struct TextContent: Codable {
                public var type: String = "text"
                public let text: String
                
                public init(text: String) {
                    self.text = text
                }
            }
            
            public struct ImageContent: Codable {
                public let type: String = "image_url"
                public let imageUrl: ImageURL
                
                public init(imageUrl: ImageURL) {
                    self.imageUrl = imageUrl
                }
                
                private enum CodingKeys: String, CodingKey {
                    case type
                    case imageUrl = "image_url"
                }
                
                public struct ImageURL: Codable {
                    public let url: String
                    public let detail: Detail
                    
                    public init(url: String, detail: Detail = .auto) {
                        self.url = url
                        self.detail = detail
                    }
                    
                    public init(imageData: Data, detail: Detail = .auto) {
                        let base64String = imageData.base64EncodedString()
                        let mimeType = Self.detectMimeType(from: imageData)
                        self.url = "data:\(mimeType);base64,\(base64String)"
                        self.detail = detail
                    }
                    
                    private static func detectMimeType(from data: Data) -> String {
                        guard data.count >= 4 else { return "image/jpeg" }
                        
                        let bytes = data.prefix(4)
                        let header = bytes.map { $0 }
                        
                        if header.starts(with: [0xFF, 0xD8, 0xFF]) {
                            return "image/jpeg"
                        } else if header.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
                            return "image/png"
                        } else if header.starts(with: [0x47, 0x49, 0x46]) {
                            return "image/gif"
                        } else if header.starts(with: [0x52, 0x49, 0x46, 0x46]) {
                            return "image/webp"
                        } else {
                            return "image/jpeg" // 默认
                        }
                    }
                    
                    public enum Detail: String, Codable, CaseIterable {
                        case low
                        case high 
                        case auto
                    }
                }
            }
        }
    }
}

// MARK: - Content Part Image Param

/// 图片内容部分参数
public struct ContentPartImageParam: Codable {
    public let imageUrl: ImageURL
    
    public init(imageUrl: ImageURL) {
        self.imageUrl = imageUrl
    }
    
    private enum CodingKeys: String, CodingKey {
        case imageUrl = "image_url"
    }
    
    public struct ImageURL: Codable {
        public let url: String
        public let detail: Detail
        
        public init(url: String, detail: Detail = .auto) {
            self.url = url
            self.detail = detail
        }
        
        public init(imageData: Data, detail: Detail = .auto) {
            let base64String = imageData.base64EncodedString()
            let mimeType = Self.detectMimeType(from: imageData)
            self.url = "data:\(mimeType);base64,\(base64String)"
            self.detail = detail
        }
        
        private static func detectMimeType(from data: Data) -> String {
            guard data.count >= 4 else { return "image/jpeg" }
            
            let bytes = data.prefix(4)
            let header = bytes.map { $0 }
            
            if header.starts(with: [0xFF, 0xD8, 0xFF]) {
                return "image/jpeg"
            } else if header.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
                return "image/png"
            } else if header.starts(with: [0x47, 0x49, 0x46]) {
                return "image/gif"
            } else if header.starts(with: [0x52, 0x49, 0x46, 0x46]) {
                return "image/webp"
            } else {
                return "image/jpeg" // 默认
            }
        }
        
        public enum Detail: String, Codable, CaseIterable {
            case low
            case high
            case auto
        }
    }
}
