import Foundation

struct PreparedAnthropicRequest: Sendable {
    let urlRequest: URLRequest
    let metadata: ChatResponseMetadata
    let fileBindings: [String: FileBinding]
}

nonisolated func validateAnthropicParameters(
    prediction: ChatQuery.PredictedOutputConfig?,
    n: Int?,
    frequencyPenalty: Double?,
    presencePenalty: Double?,
    user: String?,
    responseFormat: ChatQuery.ResponseFormat?
) throws {
    if prediction != nil {
        throw OpenAIError.providerUnsupported("Anthropic 路径暂不支持 prediction 参数")
    }
    if let n, n != 1 {
        throw OpenAIError.providerUnsupported("Anthropic 路径暂不支持 n != 1")
    }
    if frequencyPenalty != nil {
        throw OpenAIError.providerUnsupported("Anthropic 路径暂不支持 frequencyPenalty 参数")
    }
    if presencePenalty != nil {
        throw OpenAIError.providerUnsupported("Anthropic 路径暂不支持 presencePenalty 参数")
    }
    if user != nil {
        throw OpenAIError.providerUnsupported("Anthropic 路径暂不支持 user 参数")
    }
    if responseFormat != nil {
        throw OpenAIError.providerUnsupported("Anthropic 路径暂不支持 responseFormat 参数，请使用 extraBody")
    }
}

nonisolated func makeAnthropicURLRequest(
    modelInfo: AIModelInfoValue.AnthropicInfo,
    messages: [ChatQuery.ChatCompletionMessageParam],
    maxCompletionTokens: Int?,
    parallelToolCalls: Bool?,
    stop: ChatQuery.Stop?,
    temperature: Double?,
    toolChoice: ChatQuery.ChatCompletionFunctionCallOptionParam?,
    tools: [ChatQuery.ChatCompletionToolParam]?,
    topP: Double?,
    thinkLevel: ThinkLevel?,
    extraBody: [String: AnyCodableValue]?,
    extraHeaders: [String: String]?,
    fileBindings: [String: FileBinding] = [:]
) throws -> PreparedAnthropicRequest {
    let url = try APIBaseURL.appendMessages(to: modelInfo.baseURL)
    let body = try makeAnthropicRequestBody(
        modelID: modelInfo.modelID,
        messages: messages,
        maxCompletionTokens: maxCompletionTokens,
        parallelToolCalls: parallelToolCalls,
        stop: stop,
        temperature: temperature,
        toolChoice: toolChoice,
        tools: tools,
        topP: topP,
        thinkLevel: thinkLevel,
        extraBody: extraBody
    )

    var request = URLRequest(url: url)
    request.timeoutInterval = 300
    request.httpMethod = "POST"
    let httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    try assertRequestBodyWithinDeepSeekLimitIfNeeded(
        body: httpBody,
        baseURL: modelInfo.baseURL
    )
    request.httpBody = httpBody
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    request.setValue(OpenAIConfiguration.defaultUserAgent, forHTTPHeaderField: "User-Agent")
    request.setValue(OpenAIConfiguration.defaultXTitle, forHTTPHeaderField: "X-Title")

    for (key, value) in extraHeaders ?? [:] {
        request.setValue(value, forHTTPHeaderField: key)
    }
    for (key, value) in modelInfo.defaultHeaders {
        request.setValue(value, forHTTPHeaderField: key)
    }

    return PreparedAnthropicRequest(
        urlRequest: request,
        metadata: ChatResponseMetadata(
            providerName: "anthropic",
            requestID: nil,
            resolvedModel: modelInfo.modelID,
            resolvedBasePath: APIBaseURL.configuredPath(of: modelInfo.baseURL)
        ),
        fileBindings: fileBindings
    )
}

nonisolated func makeAnthropicRequestBody(
    modelID: String,
    messages: [ChatQuery.ChatCompletionMessageParam],
    maxCompletionTokens: Int?,
    parallelToolCalls: Bool?,
    stop: ChatQuery.Stop?,
    temperature: Double?,
    toolChoice: ChatQuery.ChatCompletionFunctionCallOptionParam?,
    tools: [ChatQuery.ChatCompletionToolParam]?,
    topP: Double?,
    thinkLevel: ThinkLevel?,
    extraBody: [String: AnyCodableValue]?
) throws -> [String: Any] {
    let prepared = try prepareAnthropicPrompt(messages)
    let thinkingEnabled = thinkLevel != nil && thinkLevel != ThinkLevel.none
    let (maxTokens, thinkingConfig) = resolvedAnthropicMaxTokensAndThinking(
        maxCompletionTokens: maxCompletionTokens,
        thinkLevel: thinkLevel
    )

    var body: [String: Any] = [
        "model": modelID,
        "messages": prepared.messages,
        "max_tokens": maxTokens,
        "stream": true
    ]

    if let system = prepared.system {
        body["system"] = system
    }
    if let temperature {
        body["temperature"] = temperature
    }
    if let topP {
        body["top_p"] = topP
    }
    if let stop {
        body["stop_sequences"] = encodeAnthropicStop(stop)
    }

    let effectiveToolChoice = resolveAnthropicToolChoice(
        toolChoice,
        thinkingEnabled: thinkingEnabled
    )
    if let tools, !tools.isEmpty {
        body["tools"] = tools.map(encodeAnthropicTool)
        body["tool_choice"] = encodeAnthropicToolChoice(
            effectiveToolChoice ?? .auto,
            disableParallelToolUse: parallelToolCalls == false
        )
    } else if let effectiveToolChoice {
        body["tool_choice"] = encodeAnthropicToolChoice(
            effectiveToolChoice,
            disableParallelToolUse: parallelToolCalls == false
        )
    }
    if let thinkingConfig {
        body["thinking"] = thinkingConfig
    }

    for (key, value) in extraBody ?? [:] {
        body[key] = value.anyValue
    }
    return body
}

nonisolated func appendMessagesPath(to baseURL: URL) -> URL {
    (try? APIBaseURL.appendMessages(to: baseURL.absoluteString)) ?? baseURL
}

private nonisolated func prepareAnthropicPrompt(
    _ messages: [ChatQuery.ChatCompletionMessageParam]
) throws -> (system: String?, messages: [[String: Any]]) {
    var systemParts: [String] = []
    var encodedMessages: [[String: Any]] = []
    var pendingToolResults: [[String: Any]] = []

    func flushToolResults() {
        guard !pendingToolResults.isEmpty else { return }
        encodedMessages.append([
            "role": "user",
            "content": pendingToolResults
        ])
        pendingToolResults.removeAll(keepingCapacity: true)
    }

    for message in messages {
        switch message {
        case .system(let systemMessage):
            flushToolResults()
            guard case .textContent(let text) = systemMessage.content else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                systemParts.append(trimmed)
            }
        case .reminder(let reminderMessage):
            flushToolResults()
            guard case .textContent(let text) = reminderMessage.content else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                systemParts.append(trimmed)
            }
        case .user(let userMessage):
            flushToolResults()
            encodedMessages.append([
                "role": "user",
                "content": try encodeAnthropicUserContent(userMessage.content)
            ])
        case .assistant(let assistantMessage):
            flushToolResults()
            let content = try encodeAnthropicAssistantContent(assistantMessage)
            if !content.isEmpty {
                encodedMessages.append([
                    "role": "assistant",
                    "content": content
                ])
            }
        case .tool(let toolMessage):
            pendingToolResults.append([
                "type": "tool_result",
                "tool_use_id": toolMessage.toolCallId,
                "content": try encodeAnthropicToolResultContent(toolMessage.content)
            ])
        }
    }
    flushToolResults()

    let system = systemParts.isEmpty ? nil : systemParts.joined(separator: "\n\n")
    return (system, encodedMessages)
}

private nonisolated func encodeAnthropicUserContent(
    _ content: UserMessageParam.Content
) throws -> Any {
    switch content {
    case .string(let text):
        return text
    case .contentParts(let parts):
        var encoded: [[String: Any]] = []
        for part in parts {
            switch part {
            case .text(let text):
                encoded.append(["type": "text", "text": text.text])
            case .image(let image):
                encoded.append(try encodeAnthropicImage(url: image.imageUrl.url))
            case .file(let file):
                encoded.append([
                    "type": "image",
                    "source": [
                        "type": "file",
                        "file_id": file.fileId
                    ] as [String: Any]
                ])
            case .video:
                encoded.append(["type": "text", "text": "video 不支持"])
            }
        }
        return encoded
    }
}

private nonisolated func encodeAnthropicAssistantContent(
    _ assistant: AssistantMessageParam
) throws -> [[String: Any]] {
    // Align with anthropic-sdk-python cookbook: echo preserved blocks verbatim.
    if let blocks = assistant.contentBlocks?.anthropic, !blocks.isEmpty {
        let echoed: [[String: Any]] = blocks.compactMap { block in
            let dict = block.toAnyDictionary()
            guard let type = dict["type"] as? String else { return nil }
            switch type {
            case "thinking", "redacted_thinking", "tool_use", "text":
                return dict
            default:
                return dict
            }
        }
        if !echoed.isEmpty {
            return echoed
        }
    }

    var content: [[String: Any]] = []
    if let text = assistant.content, !text.isEmpty {
        content.append(["type": "text", "text": text])
    }
    for toolCall in assistant.toolCalls ?? [] {
        content.append([
            "type": "tool_use",
            "id": toolCall.id,
            "name": toolCall.function.name,
            "input": parseJSONObject(from: toolCall.function.arguments)
        ])
    }
    return content
}

private nonisolated func encodeAnthropicToolResultContent(
    _ content: ToolMessageParam.Content
) throws -> Any {
    switch content {
    case .textContent(let text):
        return text
    case .contentParts(let parts):
        var encoded: [[String: Any]] = []
        for part in parts {
            switch part {
            case .text(let text):
                encoded.append(["type": "text", "text": text.text])
            case .image(let image):
                encoded.append(try encodeAnthropicImage(url: image.imageUrl.url))
            case .file(let file):
                encoded.append([
                    "type": "image",
                    "source": [
                        "type": "file",
                        "file_id": file.fileId
                    ] as [String: Any]
                ])
            case .video:
                encoded.append(["type": "text", "text": "video 不支持"])
            }
        }
        return encoded
    }
}

private nonisolated func encodeAnthropicImage(url: String) throws -> [String: Any] {
    if url.hasPrefix("data:"),
       let comma = url.firstIndex(of: ","),
       let mediaStart = url.firstIndex(of: ":") {
        let header = String(url[url.index(after: mediaStart)..<comma])
        let mediaType = header.split(separator: ";").first.map(String.init) ?? "image/png"
        let data = String(url[url.index(after: comma)...])
        return [
            "type": "image",
            "source": [
                "type": "base64",
                "media_type": mediaType,
                "data": data
            ] as [String: Any]
        ]
    }
    return [
        "type": "image",
        "source": [
            "type": "url",
            "url": url
        ] as [String: Any]
    ]
}

private nonisolated func encodeAnthropicTool(
    _ tool: ChatQuery.ChatCompletionToolParam
) -> [String: Any] {
    var encoded: [String: Any] = [
        "name": tool.function.name,
        "input_schema": tool.function.parameters?.toDictionary() ?? [
            "type": "object",
            "properties": [:] as [String: Any]
        ]
    ]
    if let description = tool.function.description {
        encoded["description"] = description
    }
    return encoded
}

private nonisolated func encodeAnthropicToolChoice(
    _ toolChoice: ChatQuery.ChatCompletionFunctionCallOptionParam,
    disableParallelToolUse: Bool
) -> Any {
    var encoded: [String: Any]
    switch toolChoice {
    case .none:
        encoded = ["type": "none"]
    case .auto:
        encoded = ["type": "auto"]
    case .required:
        encoded = ["type": "any"]
    case .function(let name):
        encoded = [
            "type": "tool",
            "name": name
        ]
    }
    if disableParallelToolUse, encoded["type"] as? String != "none" {
        encoded["disable_parallel_tool_use"] = true
    }
    return encoded
}

private nonisolated func resolveAnthropicToolChoice(
    _ toolChoice: ChatQuery.ChatCompletionFunctionCallOptionParam?,
    thinkingEnabled: Bool
) -> ChatQuery.ChatCompletionFunctionCallOptionParam? {
    guard let toolChoice else { return nil }
    guard thinkingEnabled else { return toolChoice }
    // Manual extended thinking only supports tool_choice auto/none.
    switch toolChoice {
    case .required, .function:
        return .auto
    case .none, .auto:
        return toolChoice
    }
}

private nonisolated func resolvedAnthropicMaxTokensAndThinking(
    maxCompletionTokens: Int?,
    thinkLevel: ThinkLevel?
) -> (maxTokens: Int, thinking: [String: Any]?) {
    let requested = maxCompletionTokens ?? 4096
    guard let thinkLevel else {
        return (requested, nil)
    }
    if thinkLevel == .none {
        return (requested, ["type": "disabled"])
    }
    // Official: budget_tokens ≥ 1024 and strictly less than max_tokens.
    let budget = max(1024, anthropicBudgetTokens(for: thinkLevel))
    let maxTokens = max(requested, budget + 4096)
    return (
        maxTokens,
        [
            "type": "enabled",
            "budget_tokens": budget
        ]
    )
}

private nonisolated func encodeAnthropicThinking(
    thinkLevel: ThinkLevel?
) -> [String: Any]? {
    resolvedAnthropicMaxTokensAndThinking(maxCompletionTokens: nil, thinkLevel: thinkLevel).thinking
}

private nonisolated func anthropicBudgetTokens(for thinkLevel: ThinkLevel) -> Int {
    switch thinkLevel {
    case .none:
        return 0
    case .minimal:
        return 1024
    case .low:
        return 2048
    case .medium:
        return 8192
    case .high:
        return 16384
    case .xhigh:
        return 24576
    case .max:
        return 32000
    }
}

private nonisolated func encodeAnthropicStop(_ stop: ChatQuery.Stop) -> [String] {
    switch stop {
    case .string(let string):
        return [string]
    case .array(let array):
        return array
    }
}

private nonisolated func parseJSONObject(from arguments: String) -> [String: Any] {
    let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let data = trimmed.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return [:]
    }
    return object
}
