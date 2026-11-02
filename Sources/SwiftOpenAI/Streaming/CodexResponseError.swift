import Foundation

public struct CodexResponseError: Error, LocalizedError, Sendable {
    public let statusCode: Int
    public let code: String?
    public let param: String?
    public let message: String
    public let requestID: String?

    public var errorDescription: String? {
        ["Codex HTTP \(statusCode)", code, param, message, requestID].compactMap { $0 }.joined(separator: ": ")
    }
}

nonisolated func codexHTTPError(body: String, status: Int, requestID: String?) -> CodexResponseError {
    let object = body.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    let error = object?["error"] as? [String: Any]
    return CodexResponseError(statusCode: status, code: error?["code"] as? String,
        param: error?["param"] as? String,
        message: error?["message"] as? String ?? object?["detail"] as? String ?? body, requestID: requestID)
}
