import Foundation

// MARK: - AI Model Info

public enum AIModelWireAPI: String, Codable, Sendable, Hashable {
    case completions
    case codexResponses
}

public enum OpenAIReasoningEffort: String, Codable, Sendable, Hashable, CaseIterable {
    case none
    case minimal
    case low
    case medium
    case high
    case xhigh

    public var enablesReasoning: Bool {
        self != .none
    }
}

/// AI 模型配置信息
///
/// 对外统一暴露为一个值类型，但内部区分 `chat/completions`
/// 与 Codex `responses` 两条传输线路。
public enum AIModelInfoValue: Sendable, Codable, Hashable {
    case completions(CompletionsInfo)
    case codex(CodexInfo)

    /// 兼容旧的 completions 初始化方式。
    public init(
        token: String,
        host: String = "api.openai.com",
        port: Int? = nil,
        scheme: String = "https",
        basePath: String? = nil,
        modelID: String = "gpt-4"
    ) {
        self = .completions(
            CompletionsInfo(
                token: token,
                host: host,
                port: port,
                scheme: scheme,
                basePath: basePath,
                modelID: modelID
            )
        )
    }

    public var wireAPI: AIModelWireAPI {
        switch self {
        case .completions:
            return .completions
        case .codex:
            return .codexResponses
        }
    }

    public var modelID: String {
        switch self {
        case .completions(let info):
            return info.modelID
        case .codex(let info):
            return info.modelID
        }
    }

    public var host: String {
        switch self {
        case .completions(let info):
            return info.host
        case .codex(let info):
            return info.host
        }
    }

    public var port: Int? {
        switch self {
        case .completions(let info):
            return info.port
        case .codex(let info):
            return info.port
        }
    }

    public var scheme: String {
        switch self {
        case .completions(let info):
            return info.scheme
        case .codex(let info):
            return info.scheme
        }
    }

    public var basePath: String? {
        switch self {
        case .completions(let info):
            return info.basePath
        case .codex(let info):
            return info.basePath
        }
    }

    /// completions 路径返回 API key，codex 路径返回 access token。
    public var token: String {
        switch self {
        case .completions(let info):
            return info.token
        case .codex(let info):
            return info.accessToken
        }
    }

    public var resolvedBasePath: String {
        switch self {
        case .completions(let info):
            return info.basePath ?? "/v1"
        case .codex(let info):
            return info.basePath
        }
    }

    public var baseURL: URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        components.path = resolvedBasePath
        return components.url
    }

    public var completionsInfo: CompletionsInfo? {
        guard case .completions(let info) = self else { return nil }
        return info
    }

    public var codexInfo: CodexInfo? {
        guard case .codex(let info) = self else { return nil }
        return info
    }

    public var isCodex: Bool {
        if case .codex = self {
            return true
        }
        return false
    }

    public struct CompletionsInfo: Sendable, Codable, Hashable {
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
            components.path = basePath ?? "/v1"
            return components.url
        }
    }

    public struct CodexInfo: Sendable, Codable, Hashable {
        public let accessToken: String
        public let accountID: String
        public let modelID: String
        public let host: String
        public let port: Int?
        public let scheme: String
        public let basePath: String
        public let isFedRAMPAccount: Bool

        public init(
            accessToken: String,
            accountID: String,
            modelID: String = "gpt-5.4",
            host: String = "chatgpt.com",
            port: Int? = nil,
            scheme: String = "https",
            basePath: String = "/backend-api/codex",
            isFedRAMPAccount: Bool = false
        ) {
            self.accessToken = accessToken
            self.accountID = accountID
            self.modelID = modelID
            self.host = host
            self.port = port
            self.scheme = scheme
            self.basePath = basePath
            self.isFedRAMPAccount = isFedRAMPAccount
        }

        public var baseURL: URL? {
            var components = URLComponents()
            components.scheme = scheme
            components.host = host
            components.port = port
            components.path = basePath
            return components.url
        }

        public var defaultHeaders: [String: String] {
            var headers: [String: String] = [
                "Authorization": "Bearer \(accessToken)",
                "ChatGPT-Account-ID": accountID
            ]
            if isFedRAMPAccount {
                headers["X-OpenAI-Fedramp"] = "true"
            }
            return headers
        }
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
    case invalidResponse(String, code: Int)

    /// 当前厂商不支持此能力
    case providerUnsupported(String)

    /// 参数组合不受支持
    case unsupportedParameterCombination(String)

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
        case .invalidResponse(let message, _):
            return "无效的响应: \(message)"
        case .providerUnsupported(let message):
            return "厂商能力不支持: \(message)"
        case .unsupportedParameterCombination(let message):
            return "参数组合不支持: \(message)"
        }
    }
}
