import Foundation

// MARK: - AI Model Info

public enum AIModelWireAPI: String, Codable, Sendable, Hashable {
    case completions
    case responses
    case codexResponses
    case anthropic
}

/// 统一的思考强度等级（completions / responses / Codex / Anthropic 共用）
///
/// - `none`：关闭思考
/// - 其余等级：开启思考，并由 Provider 映射到对应线格式
///
/// 注意：参数类型为 `ThinkLevel?` 时，请写 `ThinkLevel.none`，不要写 `.none`
///（后者会被解析为 `Optional.none`，等同于不传）。
public enum ThinkLevel: String, Codable, Sendable, Hashable, CaseIterable {
    case none
    case minimal
    case low
    case medium
    case high
    case xhigh
    case max

    public var enablesReasoning: Bool {
        self != .none
    }
}

/// AI 模型配置信息
///
/// 对外统一暴露为一个值类型，内部区分四条传输线路：
/// - `chat/completions`
/// - 通用 `/responses`
/// - Codex（ChatGPT backend，复用 Responses 协议）
/// - Anthropic Messages API（`/v1/messages`）
///
/// 端点统一用完整 `baseURL` 配置（如 `https://api.deepseek.com`、`http://localhost:8080`），
/// 库再按线路追加资源路径。
public enum AIModelInfoValue: Sendable, Codable, Hashable {
    case completions(CompletionsInfo)
    case responses(ResponsesInfo)
    case codex(CodexInfo)
    case anthropic(AnthropicInfo)

    /// Completions 便捷初始化。
    public init(
        token: String,
        baseURL: String = "https://api.openai.com/v1",
        modelID: String = "gpt-4"
    ) {
        self = .completions(
            CompletionsInfo(
                token: token,
                baseURL: baseURL,
                modelID: modelID
            )
        )
    }

    public var wireAPI: AIModelWireAPI {
        switch self {
        case .completions:
            return .completions
        case .responses:
            return .responses
        case .codex:
            return .codexResponses
        case .anthropic:
            return .anthropic
        }
    }

    public var modelID: String {
        switch self {
        case .completions(let info):
            return info.modelID
        case .responses(let info):
            return info.modelID
        case .codex(let info):
            return info.modelID
        case .anthropic(let info):
            return info.modelID
        }
    }

    /// completions / responses / anthropic 返回 API key，codex 返回 access token。
    public var token: String {
        switch self {
        case .completions(let info):
            return info.token
        case .responses(let info):
            return info.token
        case .codex(let info):
            return info.accessToken
        case .anthropic(let info):
            return info.token
        }
    }

    /// 配置的 API 根 URL 字符串。
    public var baseURL: String {
        switch self {
        case .completions(let info):
            return info.baseURL
        case .responses(let info):
            return info.baseURL
        case .codex(let info):
            return info.baseURL
        case .anthropic(let info):
            return info.baseURL
        }
    }

    /// 解析后的配置根 URL；无效时为 `nil`。
    public var resolvedURL: URL? {
        try? APIBaseURL.parse(baseURL)
    }

    /// 配置 URL 的 path（无 path 时为空字符串）。
    public var configuredPath: String {
        APIBaseURL.configuredPath(of: baseURL)
    }

    public var completionsInfo: CompletionsInfo? {
        guard case .completions(let info) = self else { return nil }
        return info
    }

    public var responsesInfo: ResponsesInfo? {
        guard case .responses(let info) = self else { return nil }
        return info
    }

    public var codexInfo: CodexInfo? {
        guard case .codex(let info) = self else { return nil }
        return info
    }

    public var anthropicInfo: AnthropicInfo? {
        guard case .anthropic(let info) = self else { return nil }
        return info
    }

    public var isResponses: Bool {
        if case .responses = self {
            return true
        }
        return false
    }

    public var isCodex: Bool {
        if case .codex = self {
            return true
        }
        return false
    }

    public var isAnthropic: Bool {
        if case .anthropic = self {
            return true
        }
        return false
    }

    public struct CompletionsInfo: Sendable, Codable, Hashable {
        /// API 访问令牌
        public let token: String

        /// API 根 URL（默认 `https://api.openai.com/v1`，请求时追加 `/chat/completions`）
        public let baseURL: String

        /// 模型标识符
        public let modelID: String

        public init(
            token: String,
            baseURL: String = "https://api.openai.com/v1",
            modelID: String = "gpt-4"
        ) {
            self.token = token
            self.baseURL = APIBaseURL.normalize(baseURL)
            self.modelID = modelID
        }

        public var resolvedURL: URL? {
            try? APIBaseURL.parse(baseURL)
        }
    }

    /// 通用 OpenAI Responses API（`/responses`）配置
    public struct ResponsesInfo: Sendable, Codable, Hashable {
        /// API 访问令牌
        public let token: String

        /// API 根 URL（默认 `https://api.openai.com/v1`，请求时追加 `/responses`）
        public let baseURL: String

        /// 模型标识符
        public let modelID: String

        public init(
            token: String,
            baseURL: String = "https://api.openai.com/v1",
            modelID: String = "gpt-4"
        ) {
            self.token = token
            self.baseURL = APIBaseURL.normalize(baseURL)
            self.modelID = modelID
        }

        public var resolvedURL: URL? {
            try? APIBaseURL.parse(baseURL)
        }

        public var defaultHeaders: [String: String] {
            [
                "Authorization": "Bearer \(token)"
            ]
        }
    }

    public struct CodexInfo: Sendable, Codable, Hashable {
        public let accessToken: String
        public let accountID: String
        public let modelID: String
        /// API 根 URL（默认 `https://chatgpt.com/backend-api/codex`，请求时追加 `/responses`）
        public let baseURL: String
        public let isFedRAMPAccount: Bool

        public init(
            accessToken: String,
            accountID: String,
            modelID: String = "gpt-5.4",
            baseURL: String = "https://chatgpt.com/backend-api/codex",
            isFedRAMPAccount: Bool = false
        ) {
            self.accessToken = accessToken
            self.accountID = accountID
            self.modelID = modelID
            self.baseURL = APIBaseURL.normalize(baseURL)
            self.isFedRAMPAccount = isFedRAMPAccount
        }

        public var resolvedURL: URL? {
            try? APIBaseURL.parse(baseURL)
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

    /// Anthropic Messages API（`/messages`）配置
    public struct AnthropicInfo: Sendable, Codable, Hashable {
        /// API 访问令牌（`x-api-key`）
        public let token: String

        /// API 根 URL（默认 `https://api.anthropic.com`，请求时追加 `/v1/messages`）
        public let baseURL: String

        /// 模型标识符
        public let modelID: String

        /// Anthropic API 版本头
        public let apiVersion: String

        public init(
            token: String,
            baseURL: String = "https://api.anthropic.com",
            modelID: String = "claude-sonnet-4-5",
            apiVersion: String = "2023-06-01"
        ) {
            self.token = token
            self.baseURL = APIBaseURL.normalize(baseURL)
            self.modelID = modelID
            self.apiVersion = apiVersion
        }

        public var resolvedURL: URL? {
            try? APIBaseURL.parse(baseURL)
        }

        public var defaultHeaders: [String: String] {
            [
                "x-api-key": token,
                "anthropic-version": apiVersion
            ]
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

    /// 请求体超过厂商字节上限（如 DeepSeek 48 MiB）
    case requestBodyTooLarge(String)

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
        case .requestBodyTooLarge(let message):
            return "请求体过大: \(message)"
        }
    }
}
