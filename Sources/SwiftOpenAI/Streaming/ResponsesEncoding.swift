import Foundation

struct ResponsesRequestConfig: Sendable {
    let modelID: String
    let baseURL: URL
    let resolvedBasePath: String
    let providerName: String
    let defaultHeaders: [String: String]
}

struct PreparedResponsesRequest: Sendable {
    let urlRequest: URLRequest
    let metadata: ChatResponseMetadata
    let fileBindings: [String: FileBinding]
}

nonisolated func validateResponsesParameters(
    prediction: ChatQuery.PredictedOutputConfig?,
    n: Int?,
    user: String?,
    pathLabel: String
) throws {
    if prediction != nil {
        throw OpenAIError.providerUnsupported("\(pathLabel) 路径暂不支持 prediction 参数")
    }
    if let n, n != 1 {
        throw OpenAIError.providerUnsupported("\(pathLabel) 路径暂不支持 n != 1")
    }
    if user != nil {
        throw OpenAIError.providerUnsupported("\(pathLabel) 路径暂不支持 user 参数")
    }
}

nonisolated func makeResponsesURLRequest(
    config: ResponsesRequestConfig,
    messages: [ChatQuery.ChatCompletionMessageParam],
    frequencyPenalty: Double?,
    maxCompletionTokens: Int?,
    parallelToolCalls: Bool?,
    presencePenalty: Double?,
    responseFormat: ChatQuery.ResponseFormat?,
    stop: ChatQuery.Stop?,
    temperature: Double?,
    toolChoice: ChatQuery.ChatCompletionFunctionCallOptionParam?,
    tools: [ChatQuery.ChatCompletionToolParam]?,
    topP: Double?,
    thinkLevel: ThinkLevel?,
    extraBody: [String: AnyCodableValue]?,
    extraHeaders: [String: String]?,
    fileBindings: [String: FileBinding] = [:]
) throws -> PreparedResponsesRequest {
    let url = appendResponsesPath(to: config.baseURL)
    let body = try makeResponsesRequestBody(
        modelID: config.modelID,
        messages: messages,
        frequencyPenalty: frequencyPenalty,
        maxCompletionTokens: maxCompletionTokens,
        parallelToolCalls: parallelToolCalls,
        presencePenalty: presencePenalty,
        responseFormat: responseFormat,
        stop: stop,
        temperature: temperature,
        toolChoice: toolChoice,
        tools: tools,
        topP: topP,
        thinkLevel: thinkLevel,
        extraBody: extraBody,
        baseURL: config.baseURL.absoluteString,
        wireAPI: config.providerName == "openai-codex" ? .codexResponses : .responses
    )

    var request = URLRequest(url: url)
    request.timeoutInterval = 300
    request.httpMethod = "POST"
    let httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    try assertRequestBodyWithinDeepSeekLimitIfNeeded(
        body: httpBody,
        baseURL: config.baseURL.absoluteString
    )
    request.httpBody = httpBody
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    request.setValue(OpenAIConfiguration.defaultUserAgent, forHTTPHeaderField: "User-Agent")
    request.setValue(OpenAIConfiguration.defaultXTitle, forHTTPHeaderField: "X-Title")

    for (key, value) in extraHeaders ?? [:] {
        request.setValue(value, forHTTPHeaderField: key)
    }
    for (key, value) in config.defaultHeaders {
        request.setValue(value, forHTTPHeaderField: key)
    }

    return PreparedResponsesRequest(
        urlRequest: request,
        metadata: ChatResponseMetadata(
            providerName: config.providerName,
            requestID: nil,
            resolvedModel: config.modelID,
            resolvedBasePath: config.resolvedBasePath
        ),
        fileBindings: fileBindings
    )
}

nonisolated func makeResponsesRequestBody(
    modelID: String,
    messages: [ChatQuery.ChatCompletionMessageParam],
    frequencyPenalty: Double?,
    maxCompletionTokens: Int?,
    parallelToolCalls: Bool?,
    presencePenalty: Double?,
    responseFormat: ChatQuery.ResponseFormat?,
    stop: ChatQuery.Stop?,
    temperature: Double?,
    toolChoice: ChatQuery.ChatCompletionFunctionCallOptionParam?,
    tools: [ChatQuery.ChatCompletionToolParam]?,
    topP: Double?,
    thinkLevel: ThinkLevel?,
    extraBody: [String: AnyCodableValue]?,
    baseURL: String? = nil,
    wireAPI: AIModelWireAPI = .responses
) throws -> [String: Any] {
    let host = baseURL.flatMap { APIBaseURL.host(of: $0) } ?? ""
    let family = ProviderFamilyResolver.resolve(host: host)
    let capability = MultimediaCapabilityResolver.resolve(
        family: family,
        wireAPI: wireAPI,
        model: modelID
    )

    var body: [String: Any] = [
        "model": modelID,
        "input": try encodeResponsesInputItems(messages, capability: capability),
        "stream": true,
        // Align with openai/codex ResponsesApiRequest: always store=false.
        "store": false,
        "parallel_tool_calls": parallelToolCalls ?? !(tools?.isEmpty ?? true)
    ]

    if let frequencyPenalty {
        body["frequency_penalty"] = frequencyPenalty
    }
    if let maxCompletionTokens {
        body["max_output_tokens"] = maxCompletionTokens
    }
    if let presencePenalty {
        body["presence_penalty"] = presencePenalty
    }
    if let stop {
        body["stop"] = try encodeResponsesStop(stop)
    }
    if let temperature {
        body["temperature"] = temperature
    }
    if let topP {
        body["top_p"] = topP
    }
    if let tools, !tools.isEmpty {
        body["tools"] = tools.map(encodeResponsesTool)
        body["tool_choice"] = encodeResponsesToolChoice(toolChoice ?? .auto)
    } else {
        body["tool_choice"] = encodeResponsesToolChoice(toolChoice ?? .none)
    }
    if let textControls = try encodeResponsesTextControls(responseFormat) {
        body["text"] = textControls
    }
    if let reasoning = encodeResponsesReasoning(thinkLevel: thinkLevel) {
        body["reasoning"] = reasoning
    }

    for (key, value) in extraBody ?? [:] {
        body[key] = value.anyValue
    }
    return body
}

/// Codex-compatible wrapper used by existing tests.
nonisolated func makeCodexResponsesRequestBody(
    modelInfo: AIModelInfoValue.CodexInfo,
    messages: [ChatQuery.ChatCompletionMessageParam],
    frequencyPenalty: Double?,
    maxCompletionTokens: Int?,
    parallelToolCalls: Bool?,
    presencePenalty: Double?,
    responseFormat: ChatQuery.ResponseFormat?,
    stop: ChatQuery.Stop?,
    temperature: Double?,
    toolChoice: ChatQuery.ChatCompletionFunctionCallOptionParam?,
    tools: [ChatQuery.ChatCompletionToolParam]?,
    topP: Double?,
    thinkLevel: ThinkLevel?,
    extraBody: [String: AnyCodableValue]?
) throws -> [String: Any] {
    try makeResponsesRequestBody(
        modelID: modelInfo.modelID,
        messages: messages,
        frequencyPenalty: frequencyPenalty,
        maxCompletionTokens: maxCompletionTokens,
        parallelToolCalls: parallelToolCalls,
        presencePenalty: presencePenalty,
        responseFormat: responseFormat,
        stop: stop,
        temperature: temperature,
        toolChoice: toolChoice,
        tools: tools,
        topP: topP,
        thinkLevel: thinkLevel,
        extraBody: extraBody,
        baseURL: modelInfo.baseURL,
        wireAPI: .codexResponses
    )
}

nonisolated func appendResponsesPath(to baseURL: URL) -> URL {
    (try? APIBaseURL.appendResponses(to: baseURL.absoluteString)) ?? baseURL
}

nonisolated func encodeResponsesInputItems(
    _ messages: [ChatQuery.ChatCompletionMessageParam],
    capability: MultimediaCapability = .none
) throws -> [[String: Any]] {
    try messages.flatMap { message -> [[String: Any]] in
        switch message {
        case .system(let systemMessage):
            guard case .textContent(let text) = systemMessage.content, !text.isEmpty else {
                return []
            }
            return [[
                "type": "message",
                "role": "system",
                "content": [["type": "input_text", "text": text]]
            ]]

        case .reminder(let reminderMessage):
            guard case .textContent(let text) = reminderMessage.content, !text.isEmpty else {
                return []
            }
            return [[
                "type": "message",
                "role": "system",
                "content": [["type": "input_text", "text": text]]
            ]]

        case .user(let userMessage):
            return [[
                "type": "message",
                "role": "user",
                "content": try encodeResponsesUserContent(userMessage.content, capability: capability)
            ]]

        case .assistant(let assistantMessage):
            var items: [[String: Any]] = []
            if let content = assistantMessage.content, !content.isEmpty {
                items.append([
                    "type": "message",
                    "role": "assistant",
                    "content": [["type": "output_text", "text": content]]
                ])
            }
            // Previous assistant reasoning is not valid as a message input item for
            // Responses. We only replay visible assistant output plus tool calls.
            for toolCall in assistantMessage.toolCalls ?? [] {
                items.append([
                    "type": "function_call",
                    "call_id": toolCall.id,
                    "name": toolCall.function.name,
                    "arguments": toolCall.function.arguments
                ])
            }
            return items

        case .tool(let toolMessage):
            return [[
                "type": "function_call_output",
                "call_id": toolMessage.toolCallId,
                "output": try encodeResponsesToolOutput(toolMessage.content, capability: capability)
            ]]
        }
    }
}

private nonisolated func encodeResponsesUserContent(
    _ content: UserMessageParam.Content,
    capability: MultimediaCapability
) throws -> [[String: Any]] {
    switch content {
    case .string(let text):
        return [["type": "input_text", "text": text]]
    case .contentParts(let parts):
        var texts: [String] = []
        var encodedParts: [[String: Any]] = []
        var hasUnsupportedImage = false
        var hasUnsupportedVideo = false
        var keptSupportedMedia = false

        for part in parts {
            switch part {
            case .text(let text):
                texts.append(text.text)
                encodedParts.append(["type": "input_text", "text": text.text])
            case .image(let image):
                if capability.supportsImage {
                    keptSupportedMedia = true
                    encodedParts.append([
                        "type": "input_image",
                        "image_url": image.imageUrl.url,
                        "detail": image.imageUrl.detail.rawValue
                    ])
                } else {
                    hasUnsupportedImage = true
                }
            case .file(let file):
                if capability.supportsImage {
                    keptSupportedMedia = true
                    encodedParts.append([
                        "type": "input_image",
                        "file_id": file.fileId
                    ])
                } else {
                    hasUnsupportedImage = true
                }
            case .video(let video):
                if capability.supportsVideo {
                    keptSupportedMedia = true
                    encodedParts.append([
                        "type": "input_video",
                        "video_url": video.videoUrl.url
                    ])
                } else {
                    hasUnsupportedVideo = true
                }
            }
        }

        let finalized = finalizeMultimediaContentParts(
            encodedParts: encodedParts,
            texts: texts,
            hasUnsupportedImage: hasUnsupportedImage,
            hasUnsupportedVideo: hasUnsupportedVideo,
            keptSupportedMedia: keptSupportedMedia
        )
        if let parts = finalized as? [[String: Any]] {
            return parts.map { part in
                if part["type"] as? String == "text", let text = part["text"] {
                    return ["type": "input_text", "text": text]
                }
                return part
            }
        }
        if let plain = finalized as? String {
            return [["type": "input_text", "text": plain]]
        }
        return encodedParts
    }
}

private nonisolated func encodeResponsesToolOutput(
    _ content: ToolMessageParam.Content,
    capability: MultimediaCapability
) throws -> Any {
    switch content {
    case .textContent(let text):
        return text
    case .contentParts(let parts):
        var texts: [String] = []
        var encodedParts: [[String: Any]] = []
        var hasUnsupportedImage = false
        var hasUnsupportedVideo = false
        var keptSupportedMedia = false

        for part in parts {
            switch part {
            case .text(let text):
                texts.append(text.text)
                encodedParts.append([
                    "type": "input_text",
                    "text": text.text
                ])
            case .image(let image):
                if capability.supportsImage {
                    keptSupportedMedia = true
                    encodedParts.append([
                        "type": "input_image",
                        "image_url": image.imageUrl.url,
                        "detail": image.imageUrl.detail.rawValue
                    ])
                } else {
                    hasUnsupportedImage = true
                }
            case .file(let file):
                if capability.supportsImage {
                    keptSupportedMedia = true
                    encodedParts.append([
                        "type": "input_image",
                        "file_id": file.fileId
                    ])
                } else {
                    hasUnsupportedImage = true
                }
            case .video(let video):
                if capability.supportsVideo {
                    keptSupportedMedia = true
                    encodedParts.append([
                        "type": "input_video",
                        "video_url": video.videoUrl.url
                    ])
                } else {
                    hasUnsupportedVideo = true
                }
            }
        }

        return finalizeMultimediaContentParts(
            encodedParts: encodedParts,
            texts: texts,
            hasUnsupportedImage: hasUnsupportedImage,
            hasUnsupportedVideo: hasUnsupportedVideo,
            keptSupportedMedia: keptSupportedMedia
        )
    }
}

private nonisolated func encodeResponsesTool(
    _ tool: ChatQuery.ChatCompletionToolParam
) -> [String: Any] {
    var encoded: [String: Any] = [
        "type": tool.type,
        "name": tool.function.name
    ]
    if let description = tool.function.description {
        encoded["description"] = description
    }
    if let parameters = tool.function.parameters {
        encoded["parameters"] = parameters.toDictionary()
    }
    return encoded
}

private nonisolated func encodeResponsesToolChoice(
    _ toolChoice: ChatQuery.ChatCompletionFunctionCallOptionParam
) -> Any {
    switch toolChoice {
    case .none:
        return "none"
    case .auto:
        return "auto"
    case .required:
        return "required"
    case .function(let name):
        return [
            "type": "function",
            "name": name
        ]
    }
}

private nonisolated func encodeResponsesReasoning(
    thinkLevel: ThinkLevel?
) -> [String: Any]? {
    guard let thinkLevel else {
        return nil
    }
    return [
        "effort": thinkLevel.rawValue,
        "summary": "auto"
    ]
}

private nonisolated func encodeResponsesTextControls(
    _ responseFormat: ChatQuery.ResponseFormat?
) throws -> [String: Any]? {
    guard let responseFormat else { return nil }

    switch responseFormat.type {
    case "json_schema":
        guard let schema = responseFormat.jsonSchema else { return nil }
        var formatDict: [String: Any] = [
            "type": "json_schema",
            "name": schema.name,
            "strict": schema.strict ?? true
        ]
        if let schemaDict = schema.schema {
            formatDict["schema"] = schemaDict.toAnyDictionary()
        }
        return [
            "format": formatDict
        ]
    case "json_object":
        return [
            "format": [
                "type": "json_schema",
                "name": "json_object",
                "strict": false,
                "schema": [
                    "type": "object"
                ]
            ]
        ]
    default:
        return nil
    }
}

private nonisolated func encodeResponsesStop(_ stop: ChatQuery.Stop) throws -> Any {
    switch stop {
    case .string(let string):
        return string
    case .array(let array):
        return array
    }
}
