import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// DeepSeek / OpenAI-compatible Files API upload result.
public struct OpenAIUploadedFile: Codable, Sendable, Hashable {
    public let id: String
    public let bytes: Int?
    public let filename: String?
    public let purpose: String?
    public let expiresAt: Int?

    enum CodingKeys: String, CodingKey {
        case id, bytes, filename, purpose
        case expiresAt = "expires_at"
    }

    public var expiresDate: Date? {
        guard let expiresAt else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(expiresAt))
    }
}

/// Upload an image for later `file_id` reference (DeepSeek Files API shape).
///
/// - Parameter expiresAfterSeconds: 可选过期秒数。`nil`（默认）不传 `expires_after`，文件永久有效。
nonisolated public func uploadOpenAIFile(
    baseURL: String,
    bearerToken: String,
    fileData: Data,
    filename: String,
    purpose: String = "user_data",
    expiresAfterSeconds: Int? = nil,
    extraHeaders: [String: String]? = nil
) async throws -> OpenAIUploadedFile {
    let url = try APIBaseURL.appendFiles(to: baseURL)
    let boundary = "Boundary-\(UUID().uuidString)"
    var body = Data()

    func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            body.append(data)
        }
    }

    append("--\(boundary)\r\n")
    append("Content-Disposition: form-data; name=\"purpose\"\r\n\r\n")
    append("\(purpose)\r\n")

    if let expiresAfterSeconds {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"expires_after[anchor]\"\r\n\r\n")
        append("created_at\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"expires_after[seconds]\"\r\n\r\n")
        append("\(expiresAfterSeconds)\r\n")
    }

    let mime = mimeType(forImageData: fileData)
    append("--\(boundary)\r\n")
    append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
    append("Content-Type: \(mime)\r\n\r\n")
    body.append(fileData)
    append("\r\n")
    append("--\(boundary)--\r\n")

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 600
    request.httpBody = body
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
    request.setValue(OpenAIConfiguration.defaultUserAgent, forHTTPHeaderField: "User-Agent")
    for (key, value) in extraHeaders ?? [:] {
        request.setValue(value, forHTTPHeaderField: key)
    }

    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200...299).contains(status) else {
        let text = String(data: data, encoding: .utf8) ?? ""
        throw mapDeepSeekBodyLimitError(message: text, code: status)
    }
    do {
        return try JSONDecoder().decode(OpenAIUploadedFile.self, from: data)
    } catch {
        throw OpenAIError.decodingError(error)
    }
}

/// Delete an uploaded file (optional cleanup).
nonisolated public func deleteOpenAIFile(
    baseURL: String,
    bearerToken: String,
    fileId: String,
    extraHeaders: [String: String]? = nil
) async throws {
    let base = try APIBaseURL.appendFiles(to: baseURL)
    guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
        throw OpenAIError.invalidURL
    }
    let path = components.path.hasSuffix("/") ? components.path + fileId : components.path + "/" + fileId
    components.path = path
    guard let url = components.url else {
        throw OpenAIError.invalidURL
    }

    var request = URLRequest(url: url)
    request.httpMethod = "DELETE"
    request.timeoutInterval = 60
    request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
    request.setValue(OpenAIConfiguration.defaultUserAgent, forHTTPHeaderField: "User-Agent")
    for (key, value) in extraHeaders ?? [:] {
        request.setValue(value, forHTTPHeaderField: key)
    }

    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200...299).contains(status) else {
        let text = String(data: data, encoding: .utf8) ?? ""
        throw mapDeepSeekBodyLimitError(message: text, code: status)
    }
}

nonisolated func mimeType(forImageData data: Data) -> String {
    guard data.count >= 4 else { return "image/jpeg" }
    let header = Array(data.prefix(4))
    if header.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
    if header.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
    if header.starts(with: [0x47, 0x49, 0x46]) { return "image/gif" }
    if header.starts(with: [0x52, 0x49, 0x46, 0x46]) { return "image/webp" }
    return "image/jpeg"
}

nonisolated func extensionForMimeType(_ mime: String) -> String {
    switch mime {
    case "image/png": return "png"
    case "image/gif": return "gif"
    case "image/webp": return "webp"
    default: return "jpg"
    }
}

/// DeepSeek chat/completions & responses documented inline body ceiling.
let deepSeekRequestBodyLimitBytes = 48 * 1024 * 1024

nonisolated func isDeepSeekHost(_ baseURL: String) -> Bool {
    (APIBaseURL.host(of: baseURL) ?? "").lowercased().contains("deepseek")
}

nonisolated func isDeepSeekVisionExpModel(_ modelID: String) -> Bool {
    let id = modelID.lowercased()
    return id.contains("vision-exp") || id.contains("vision_exp") || id == "deepseek-v4-flash-vision-exp"
}

nonisolated func shouldOffloadImagesToFilesAPI(baseURL: String, modelID: String) -> Bool {
    isDeepSeekHost(baseURL) && isDeepSeekVisionExpModel(modelID)
}

nonisolated func mapDeepSeekBodyLimitError(message: String, code: Int) -> OpenAIError {
    let lower = message.lowercased()
    if code == 413
        || lower.contains("length limit exceeded")
        || lower.contains("failed to buffer the request body")
        || lower.contains("request entity too large")
        || lower.contains("payload too large")
    {
        return .requestBodyTooLarge(
            "DeepSeek request body exceeded the ~48 MiB limit (HTTP \(code)): \(message)"
        )
    }
    return .invalidResponse(message, code: code)
}

nonisolated func assertRequestBodyWithinDeepSeekLimitIfNeeded(
    body: Data,
    baseURL: String
) throws {
    guard isDeepSeekHost(baseURL) else { return }
    if body.count >= deepSeekRequestBodyLimitBytes {
        throw OpenAIError.requestBodyTooLarge(
            "Serialized request is \(body.count) bytes; DeepSeek limit is \(deepSeekRequestBodyLimitBytes) bytes. Use Files API file_id for images or shrink context."
        )
    }
}
