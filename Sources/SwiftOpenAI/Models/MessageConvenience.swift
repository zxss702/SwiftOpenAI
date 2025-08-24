import Foundation

// MARK: - Type Aliases
public typealias OpenAIMessage = ChatQuery.ChatCompletionMessageParam
public typealias OpenAITool = ChatQuery.ChatCompletionToolParam
public typealias OpenAIFunctionDefinition = ChatQuery.ChatCompletionToolParam.Function

// MARK: - Message Parameter Types

// MARK: - User Message
public struct UserMessageParam: Codable {
    public let content: Content
    public let name: String?
    
    public init(content: Content, name: String? = nil) {
        self.content = content
        self.name = name
    }
    
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

// MARK: - System Message
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
public struct AssistantMessageParam: Codable {
    public let content: String?
    public let name: String?
    public let toolCalls: [ToolCallParam]?
    
    public init(content: String? = nil, name: String? = nil, toolCalls: [ToolCallParam]? = nil) {
        self.content = content
        self.name = name
        self.toolCalls = toolCalls
    }
    
    private enum CodingKeys: String, CodingKey {
        case content, name
        case toolCalls = "tool_calls"
    }
    
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
public struct ToolMessageParam: Codable {
    public let content: TextContent
    public let toolCallId: String
    
    public init(content: TextContent, toolCallId: String) {
        self.content = content
        self.toolCallId = toolCallId
    }
    
    private enum CodingKeys: String, CodingKey {
        case content
        case toolCallId = "tool_call_id"
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

// MARK: - ContentPartImageParam
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
