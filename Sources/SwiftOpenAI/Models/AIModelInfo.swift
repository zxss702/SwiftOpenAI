import Foundation

public struct AIModelInfoValue {
    public let token: String
    public let host: String
    public let port: Int?
    public let scheme: String
    public let basePath: String?
    public let modelID: String
    
    public init(
        token: String,
        host: String = "api.openai.com",
        port: Int? = nil,
        scheme: String = "https",
        basePath: String? = nil,
        modelID: String = "gpt-4"
    ) {
        self.token = token
        self.host = host
        self.port = port
        self.scheme = scheme
        self.basePath = basePath
        self.modelID = modelID
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
}

public enum OpenAIError: Error, LocalizedError {
    case missingModelID
    case invalidURL
    case missingToken
    case networkError(Error)
    case decodingError(Error)
    case streamingError(String)
    case invalidResponse
    
    public var errorDescription: String? {
        switch self {
        case .missingModelID:
            return "缺少模型ID"
        case .invalidURL:
            return "无效的URL"
        case .missingToken:
            return "缺少API密钥"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .decodingError(let error):
            return "解码错误: \(error.localizedDescription)"
        case .streamingError(let message):
            return "流式传输错误: \(message)"
        case .invalidResponse:
            return "无效的响应"
        }
    }
}
