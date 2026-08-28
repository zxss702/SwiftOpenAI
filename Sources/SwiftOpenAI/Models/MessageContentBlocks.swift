import Foundation
import Crypto

/// 随消息/结果携带的扩展内容块（Anthropic 原样 blocks、Files API 绑定等）。
public struct MessageContentBlocks: Codable, Sendable, Hashable {
    /// Anthropic 原样 content blocks（thinking/signature/tool_use…）
    public var anthropic: [[String: AnyCodableValue]]?
    /// 已上传文件绑定：key = `sha256Hex + basePath`（厂商根，如 `api.deepseek.com/v1`），不存原始 Data
    public var fileBindings: [String: FileBinding]?

    public init(
        anthropic: [[String: AnyCodableValue]]? = nil,
        fileBindings: [String: FileBinding]? = nil
    ) {
        self.anthropic = anthropic
        self.fileBindings = fileBindings
    }

    private enum CodingKeys: String, CodingKey {
        case anthropic
        case fileBindings = "file_bindings"
    }

    public static func anthropicOnly(_ blocks: [[String: AnyCodableValue]]) -> MessageContentBlocks {
        MessageContentBlocks(anthropic: blocks)
    }

    /// 厂商隔离用的 basePath：`host` + `configuredPath`（例：`api.deepseek.com`、`api.deepseek.com/v1`）。
    public static func fileBindingBasePath(from baseURL: String) -> String {
        let host = APIBaseURL.host(of: baseURL) ?? ""
        let path = APIBaseURL.configuredPath(of: baseURL)
        return host + path
    }

    /// `fileBindings` 字典 key：`<SHA256 hex><basePath>`。
    public static func fileBindingKey(sha256Hex: String, baseURL: String) -> String {
        sha256Hex + fileBindingBasePath(from: baseURL)
    }

    /// 对图像 Data 直接生成绑定 key。
    public static func fileBindingKey(imageData: Data, baseURL: String) -> String {
        fileBindingKey(sha256Hex: ContentBlocksCrypto.sha256Hex(of: imageData), baseURL: baseURL)
    }

    /// 合并 fileBindings（后者覆盖同 key）。
    public mutating func mergeFileBindings(_ other: [String: FileBinding]?) {
        guard let other, !other.isEmpty else { return }
        var merged = fileBindings ?? [:]
        for (key, value) in other {
            merged[key] = value
        }
        fileBindings = merged
    }

    public func merging(_ other: MessageContentBlocks?) -> MessageContentBlocks {
        guard let other else { return self }
        var copy = self
        if let anthropic = other.anthropic {
            copy.anthropic = anthropic
        }
        copy.mergeFileBindings(other.fileBindings)
        return copy
    }

    /// 从对话历史里的 assistant.contentBlocks 汇总 fileBindings。
    public static func aggregatedFileBindings(
        from messages: [ChatQuery.ChatCompletionMessageParam]
    ) -> [String: FileBinding] {
        var merged: [String: FileBinding] = [:]
        for message in messages {
            guard case .assistant(let assistant) = message,
                  let bindings = assistant.contentBlocks?.fileBindings else { continue }
            for (key, value) in bindings {
                merged[key] = value
            }
        }
        return merged
    }
}

/// Files API 上传结果的轻量绑定（不含图像字节）。
public struct FileBinding: Codable, Sendable, Hashable {
    public var fileId: String
    public var expiresAt: Date?
    public var filename: String?
    public var byteCount: Int?

    public init(
        fileId: String,
        expiresAt: Date? = nil,
        filename: String? = nil,
        byteCount: Int? = nil
    ) {
        self.fileId = fileId
        self.expiresAt = expiresAt
        self.filename = filename
        self.byteCount = byteCount
    }

    private enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case expiresAt = "expires_at"
        case filename
        case byteCount = "byte_count"
    }

    /// 是否仍视为有效（留 60s skew）。
    public func isUsable(now: Date = .now, skew: TimeInterval = 60) -> Bool {
        guard let expiresAt else { return true }
        return expiresAt.timeIntervalSince(now) > skew
    }
}

enum ContentBlocksCrypto {
    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
