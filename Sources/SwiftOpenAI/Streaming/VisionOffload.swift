import Foundation

struct VisionOffloadResult: Sendable {
    var messages: [ChatQuery.ChatCompletionMessageParam]
    var fileBindings: [String: FileBinding]
}

/// 文件旁路目标厂家。
private enum OffloadTarget {
    /// DeepSeek Files API：`data:` 图像上传后改写为 `file_id` part。
    case deepSeekFiles
    /// 阿里百炼临时存储：`data:` 图像/视频上传后改写为携 `oss://` URL 的同类型 part（48h，文件绑定模型）。
    case dashScopeOSS
    /// Kimi Files API：`data:` 视频上传后改写为 `ms://` URL；图像保留 base64（Kimi 原生支持）。
    case moonshotFiles
}

/// 按厂家将消息中的内联 `data:` 图像/视频旁路为文件引用，并维护 ``FileBinding`` 缓存。
nonisolated func offloadVisionMediaIfNeeded(
    messages: [ChatQuery.ChatCompletionMessageParam],
    baseURL: String,
    modelID: String,
    bearerToken: String,
    priorBindings: [String: FileBinding] = [:],
    extraHeaders: [String: String]? = nil
) async throws -> VisionOffloadResult {
    let target: OffloadTarget?
    if shouldOffloadImagesToFilesAPI(baseURL: baseURL, modelID: modelID) {
        target = .deepSeekFiles
    } else {
        switch ProviderFamilyResolver.resolve(host: APIBaseURL.host(of: baseURL) ?? "") {
        case .dashscope:
            target = .dashScopeOSS
        case .moonshot:
            target = .moonshotFiles
        default:
            target = nil
        }
    }
    guard let target else {
        return VisionOffloadResult(messages: messages, fileBindings: priorBindings)
    }

    var bindings = priorBindings
    var rewritten: [ChatQuery.ChatCompletionMessageParam] = []
    rewritten.reserveCapacity(messages.count)

    for message in messages {
        switch message {
        case .user(let user):
            let content = try await rewriteUserContent(
                user.content,
                target: target,
                bindings: &bindings,
                baseURL: baseURL,
                modelID: modelID,
                bearerToken: bearerToken,
                extraHeaders: extraHeaders
            )
            rewritten.append(.user(UserMessageParam(content: content, name: user.name)))
        case .tool(let tool):
            let content = try await rewriteToolContent(
                tool.content,
                target: target,
                bindings: &bindings,
                baseURL: baseURL,
                modelID: modelID,
                bearerToken: bearerToken,
                extraHeaders: extraHeaders
            )
            rewritten.append(.tool(ToolMessageParam(content: content, toolCallId: tool.toolCallId)))
        default:
            rewritten.append(message)
        }
    }

    return VisionOffloadResult(messages: rewritten, fileBindings: bindings)
}

private nonisolated func rewriteUserContent(
    _ content: UserMessageParam.Content,
    target: OffloadTarget,
    bindings: inout [String: FileBinding],
    baseURL: String,
    modelID: String,
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
                switch target {
                case .deepSeekFiles:
                    if let fileId = try await resolveDeepSeekFileId(
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
                case .dashScopeOSS:
                    if let ossURL = try await resolveDashScopeFileURL(
                        forDataURL: image.imageUrl.url,
                        bindings: &bindings,
                        baseURL: baseURL,
                        modelID: modelID,
                        bearerToken: bearerToken,
                        extraHeaders: extraHeaders
                    ) {
                        out.append(.image(.init(imageUrl: .init(url: ossURL, detail: image.imageUrl.detail))))
                    } else {
                        out.append(part)
                    }
                case .moonshotFiles:
                    out.append(part)
                }
            case .video(let video):
                if let url = try await resolveVideoFileURL(
                    video.videoUrl.url,
                    target: target,
                    bindings: &bindings,
                    baseURL: baseURL,
                    modelID: modelID,
                    bearerToken: bearerToken,
                    extraHeaders: extraHeaders
                ) {
                    out.append(.video(.init(videoUrl: .init(url: url, fps: video.videoUrl.fps))))
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
    target: OffloadTarget,
    bindings: inout [String: FileBinding],
    baseURL: String,
    modelID: String,
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
                switch target {
                case .deepSeekFiles:
                    if let fileId = try await resolveDeepSeekFileId(
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
                case .dashScopeOSS:
                    if let ossURL = try await resolveDashScopeFileURL(
                        forDataURL: image.imageUrl.url,
                        bindings: &bindings,
                        baseURL: baseURL,
                        modelID: modelID,
                        bearerToken: bearerToken,
                        extraHeaders: extraHeaders
                    ) {
                        out.append(.image(.init(imageUrl: .init(url: ossURL, detail: image.imageUrl.detail))))
                    } else {
                        out.append(part)
                    }
                case .moonshotFiles:
                    out.append(part)
                }
            case .video(let video):
                if let url = try await resolveVideoFileURL(
                    video.videoUrl.url,
                    target: target,
                    bindings: &bindings,
                    baseURL: baseURL,
                    modelID: modelID,
                    bearerToken: bearerToken,
                    extraHeaders: extraHeaders
                ) {
                    out.append(.video(.init(videoUrl: .init(url: url, fps: video.videoUrl.fps))))
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

/// 视频旁路：dashscope 上传得 `oss://` URL，moonshot 上传得 `ms://` URL；其余厂家或不可解析时返回 nil（保持原 part）。
private nonisolated func resolveVideoFileURL(
    _ url: String,
    target: OffloadTarget,
    bindings: inout [String: FileBinding],
    baseURL: String,
    modelID: String,
    bearerToken: String,
    extraHeaders: [String: String]?
) async throws -> String? {
    switch target {
    case .deepSeekFiles:
        return nil
    case .dashScopeOSS:
        return try await resolveDashScopeFileURL(
            forDataURL: url,
            bindings: &bindings,
            baseURL: baseURL,
            modelID: modelID,
            bearerToken: bearerToken,
            extraHeaders: extraHeaders
        )
    case .moonshotFiles:
        guard let payload = decodeDataURL(url) else { return nil }
        let sha = ContentBlocksCrypto.sha256Hex(of: payload.data)
        let key = MessageContentBlocks.fileBindingKey(sha256Hex: sha, baseURL: baseURL)
        if let existing = bindings[key], existing.isUsable() {
            return "ms://\(existing.fileId)"
        }
        let filename = "upload.\(extensionForMimeType(payload.mimeType))"
        let uploaded = try await uploadOpenAIFile(
            baseURL: baseURL,
            bearerToken: bearerToken,
            fileData: payload.data,
            filename: filename,
            purpose: "video",
            mimeType: payload.mimeType,
            extraHeaders: extraHeaders
        )
        // Kimi 文件不过期，expiresAt 留空。
        bindings[key] = FileBinding(
            fileId: uploaded.id,
            filename: uploaded.filename ?? filename,
            byteCount: uploaded.bytes ?? payload.data.count
        )
        return "ms://\(uploaded.id)"
    }
}

private nonisolated func resolveDeepSeekFileId(
    forDataURL url: String,
    bindings: inout [String: FileBinding],
    baseURL: String,
    bearerToken: String,
    extraHeaders: [String: String]?
) async throws -> String? {
    guard let payload = decodeDataURL(url) else {
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

private nonisolated func resolveDashScopeFileURL(
    forDataURL url: String,
    bindings: inout [String: FileBinding],
    baseURL: String,
    modelID: String,
    bearerToken: String,
    extraHeaders: [String: String]?
) async throws -> String? {
    guard let payload = decodeDataURL(url) else {
        return nil
    }
    let sha = ContentBlocksCrypto.sha256Hex(of: payload.data)
    // 百炼文件与模型绑定，key 须纳入 modelID；FileBinding.fileId 存 `oss://` URL。
    let key = MessageContentBlocks.fileBindingKey(sha256Hex: sha, baseURL: baseURL, modelID: modelID)
    if let existing = bindings[key], existing.isUsable() {
        return existing.fileId
    }
    let filename = "upload.\(extensionForMimeType(payload.mimeType))"
    let uploaded = try await uploadDashScopeTemporaryFile(
        baseURL: baseURL,
        bearerToken: bearerToken,
        modelID: modelID,
        fileData: payload.data,
        filename: filename,
        extraHeaders: extraHeaders
    )
    bindings[key] = FileBinding(
        fileId: uploaded.ossURL,
        expiresAt: uploaded.expiresAt,
        filename: filename,
        byteCount: payload.data.count
    )
    return uploaded.ossURL
}

private struct DecodedDataURLPayload: Sendable {
    var data: Data
    var mimeType: String
}

private nonisolated func decodeDataURL(_ url: String) -> DecodedDataURLPayload? {
    // data:image/png;base64,.... / data:video/mp4;base64,....
    guard url.hasPrefix("data:"),
          let comma = url.firstIndex(of: ",") else { return nil }
    let meta = String(url[url.index(url.startIndex, offsetBy: 5)..<comma])
    guard meta.contains(";base64") || meta.hasSuffix("base64") else { return nil }
    let mime = meta.split(separator: ";").first.map(String.init) ?? "application/octet-stream"
    let b64 = String(url[url.index(after: comma)...])
    guard let data = Data(base64Encoded: b64, options: [.ignoreUnknownCharacters]) else {
        return nil
    }
    return DecodedDataURLPayload(data: data, mimeType: mime)
}

nonisolated func mergeContentBlocksForResult(
    anthropic: [[String: AnyCodableValue]]?,
    fileBindings: [String: FileBinding],
    responses: ResponsesMessageContext? = nil
) -> MessageContentBlocks? {
    if (anthropic == nil || anthropic?.isEmpty == true)
        && fileBindings.isEmpty
        && responses == nil {
        return nil
    }
    return MessageContentBlocks(
        anthropic: (anthropic?.isEmpty == false) ? anthropic : nil,
        fileBindings: fileBindings.isEmpty ? nil : fileBindings,
        responses: responses
    )
}
