import Foundation

// MARK: - AI Model Info

/// AI 模型配置信息
///
/// 封装 AI 模型的连接参数和标识信息。
public struct AIModelInfoValue: Sendable {
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
    
    /// 模型标识符
    public let modelID: String
    
    /// 初始化 AI 模型配置
    ///
    /// - Parameters:
    ///   - token: API 访问令牌
    ///   - host: API 主机地址，默认为 "api.openai.com"
    ///   - port: API 端口号，默认为 nil
    ///   - scheme: URL 协议方案，默认为 "https"
    ///   - basePath: API 基础路径，默认为 nil
    ///   - modelID: 模型标识符，默认为 "gpt-4"
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
}

// MARK: - Errors

/// OpenAI 错误类型
///
/// 定义 OpenAI API 操作中可能发生的各种错误。
public nonisolated enum OpenAIError: Error, LocalizedError {
    /// 缺少模型 ID
    case missingModelID
    
    /// 无效的 URL
    case invalidURL
    
    /// 缺少 API 令牌
    case missingToken
    
    /// 网络错误
    case networkError(Error)
    
    /// 解码错误
    case decodingError(Error)
    
    /// 流式传输错误
    case streamingError(String)
    
    /// 无效的响应
    case invalidResponse(String)
    
    /// 错误的本地化描述
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
        case .invalidResponse(let message):
            return "无效的响应: \(message)"
        }
    }
}
