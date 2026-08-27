import Foundation

struct DeepSeekVisionOffloadResult: Sendable {
    var messages: [ChatQuery.ChatCompletionMessageParam]
    var fileBindings: [String: FileBinding]
}

/// Upload inline `data:` images to DeepSeek Files API and rewrite parts to `file_id`.
nonisolated func offloadDeepSeekVisionImagesIfNeeded(
    messages: [ChatQuery.ChatCompletionMessageParam],
    baseURL: String,
    modelID: String,
    bearerToken: String,
    priorBindings: [String: FileBinding] = [:],
    extraHeaders: [String: String]? = nil
) async throws -> DeepSeekVisionOffloadResult {
    guard shouldOffloadImagesToFilesAPI(baseURL: baseURL, modelID: modelID) else {
        return DeepSeekVisionOffloadResult(messages: messages, fileBindings: priorBindings)
    }

    var bindings = priorBindings
    var rewritten: [ChatQuery.ChatCompletionMessageParam] = []
    rewritten.reserveCapacity(messages.count)

    for message in messages {
        switch message {
        case .user(let user):
            let content = try await rewriteUserContent(
                user.content,
                bindings: &bindings,
                baseURL: baseURL,
                bearerToken: bearerToken,
                extraHeaders: extraHeaders
            )
            rewritten.append(.user(UserMessageParam(content: content, name: user.name)))
        case .tool(let tool):
            let content = try await rewriteToolContent(
                tool.content,
                bindings: &bindings,
                baseURL: baseURL,
                bearerToken: bearerToken,
                extraHeaders: extraHeaders
            )
            rewritten.append(.tool(ToolMessageParam(content: content, toolCallId: tool.toolCallId)))
        default:
            rewritten.append(message)
        }
    }

    return DeepSeekVisionOffloadResult(messages: rewritten, fileBindings: bindings)
}

private nonisolated func rewriteUserContent(
    _ content: UserMessageParam.Content,
    bindings: inout [String: FileBinding],
    baseURL: String,
    bearerToken: String,
    extraHeaders: [String: String]?
) async throws -> UserMessageParam.Content {
    switch content {
    case .string:
        return content
    case .contentParts(let parts):
        var out: [UserMessageParam.Content.ContentPart] = []
        out.reserveCapacity(parts.count)
        for part in parts {
            switch part {
            case .image(let image):
                if let fileId = try await resolveFileId(
                    forDataURL: image.imageUrl.url,
                    bindings: &bindings,
                    baseURL: baseURL,
                    bearerToken: bearerToken,
                    extraHeaders: extraHeaders
                ) {
                    out.append(.file(.init(fileId: fileId)))
                } else {
                    out.append(part)
                }
            default:
                out.append(part)
            }
        }
        return .contentParts(out)
    }
}

private nonisolated func rewriteToolContent(
    _ content: ToolMessageParam.Content,
    bindings: inout [String: FileBinding],
    baseURL: String,
    bearerToken: String,
    extraHeaders: [String: String]?
) async throws -> ToolMessageParam.Content {
    switch content {
    case .textContent:
        return content
    case .contentParts(let parts):
        var out: [ToolMessageParam.Content.ContentPart] = []
        out.reserveCapacity(parts.count)
        for part in parts {
            switch part {
            case .image(let image):
                if let fileId = try await resolveFileId(
                    forDataURL: image.imageUrl.url,
                    bindings: &bindings,
                    baseURL: baseURL,
                    bearerToken: bearerToken,
                    extraHeaders: extraHeaders
                ) {
                    out.append(.file(.init(fileId: fileId)))
                } else {
                    out.append(part)
                }
            default:
                out.append(part)
            }
        }
        return .contentParts(out)
    }
}

private nonisolated func resolveFileId(
    forDataURL url: String,
    bindings: inout [String: FileBinding],
    baseURL: String,
    bearerToken: String,
    extraHeaders: [String: String]?
) async throws -> String? {
    guard let payload = decodeDataURLImage(url) else {
        return nil
    }
    let sha = ContentBlocksCrypto.sha256Hex(of: payload.data)
    let key = MessageContentBlocks.fileBindingKey(sha256Hex: sha, baseURL: baseURL)
    if let existing = bindings[key], existing.isUsable() {
        return existing.fileId
    }
    let filename = "upload.\(extensionForMimeType(payload.mimeType))"
    // 不传 expires_after：DeepSeek 侧永久有效（传 seconds 才会过期）。
    let uploaded = try await uploadOpenAIFile(
        baseURL: baseURL,
        bearerToken: bearerToken,
        fileData: payload.data,
        filename: filename,
        purpose: "user_data",
        expiresAfterSeconds: nil,
        extraHeaders: extraHeaders
    )
    let binding = FileBinding(
        fileId: uploaded.id,
        expiresAt: uploaded.expiresDate,
        filename: uploaded.filename ?? filename,
        byteCount: uploaded.bytes ?? payload.data.count
    )
    bindings[key] = binding
    return uploaded.id
}

private struct DecodedDataURLImage: Sendable {
    var data: Data
    var mimeType: String
}

private nonisolated func decodeDataURLImage(_ url: String) -> DecodedDataURLImage? {
    // data:image/png;base64,....
    guard url.hasPrefix("data:"),
          let comma = url.firstIndex(of: ",") else { return nil }
    let meta = String(url[url.index(url.startIndex, offsetBy: 5)..<comma])
    guard meta.contains(";base64") || meta.hasSuffix("base64") else { return nil }
    let mime = meta.split(separator: ";").first.map(String.init) ?? "image/jpeg"
    let b64 = String(url[url.index(after: comma)...])
    guard let data = Data(base64Encoded: b64, options: [.ignoreUnknownCharacters]) else {
        return nil
    }
    return DecodedDataURLImage(data: data, mimeType: mime)
}

nonisolated func mergeContentBlocksForResult(
    anthropic: [[String: AnyCodableValue]]?,
    fileBindings: [String: FileBinding]
) -> MessageContentBlocks? {
    if (anthropic == nil || anthropic?.isEmpty == true) && fileBindings.isEmpty {
        return nil
    }
    return MessageContentBlocks(
        anthropic: (anthropic?.isEmpty == false) ? anthropic : nil,
        fileBindings: fileBindings.isEmpty ? nil : fileBindings
    )
}
