import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if !os(Windows)
import AsyncHTTPClient
import NIOCore
import NIOHTTP1
#endif

#if !os(Windows)

private let codexResponsesRequestTimeout: TimeAmount = .seconds(300)
private let codexResponsesBodyLimit = 64 * 1024 * 1024
private let defaultCodexResponsesInstructions = "You are a helpful assistant."

struct CodexResponsesStreamState {
    var pendingText: String = ""
    var usage: ChatStreamResult.Choice.UsageInfo?
    var responseID: String?
    var resolvedModel: String?
    var toolCallIndexByCallID: [String: Int] = [:]
    var toolCallIndexByItemID: [String: Int] = [:]
    var nextToolCallIndex: Int = 0
    var prefersReasoningText = false
}

nonisolated func sendCodexResponsesMessage(
    modelInfo: AIModelInfoValue.CodexInfo,
    messages: [ChatQuery.ChatCompletionMessageParam],
    frequencyPenalty: Double? = nil,
    maxCompletionTokens: Int? = nil,
    n: Int? = nil,
    parallelToolCalls: Bool? = nil,
    prediction: ChatQuery.PredictedOutputConfig? = nil,
    presencePenalty: Double? = nil,
    responseFormat: ChatQuery.ResponseFormat? = nil,
    stop: ChatQuery.Stop? = nil,
    temperature: Double? = nil,
    toolChoice: ChatQuery.ChatCompletionFunctionCallOptionParam? = nil,
    tools: [ChatQuery.ChatCompletionToolParam]? = nil,
    topP: Double? = nil,
    user: String? = nil,
    think: Bool? = nil,
    reasoningEffort: OpenAIReasoningEffort? = nil,
    extraBody: [String: AnyCodableValue]? = nil,
    extraHeaders: [String: String]? = nil,
    action: @escaping @Sendable (OpenAIChatStreamResult) async throws -> Void
) async throws -> OpenAIChatResult {
    if prediction != nil {
        throw OpenAIError.providerUnsupported("Codex responses 路径暂不支持 prediction 参数")
    }
    if let n, n != 1 {
        throw OpenAIError.providerUnsupported("Codex responses 路径暂不支持 n != 1")
    }
    if user != nil {
        throw OpenAIError.providerUnsupported("Codex responses 路径暂不支持 user 参数")
    }

    let request = try makeCodexResponsesRequest(
        modelInfo: modelInfo,
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
        think: think,
        reasoningEffort: reasoningEffort,
        extraBody: extraBody,
        extraHeaders: extraHeaders
    )

    let actorHelper = OpenAISendMessageValueHelper()
    let response = try await executeCodexResponsesRequest(request)

    guard (200...299).contains(Int(response.status.code)) else {
        let responseBody = try await codexResponseBodyString(from: response.body)
        throw OpenAIError.invalidResponse(responseBody, code: Int(response.status.code))
    }

    var lastSendTime = Date().timeIntervalSince1970
    var state = CodexResponsesStreamState()
    var metadata = ChatResponseMetadata(
        providerName: "openai-codex",
        requestID: response.headers["x-request-id"].first,
        resolvedModel: modelInfo.modelID,
        resolvedBasePath: modelInfo.basePath
    )

    for try await part in response.body {
        try Task.checkCancellation()
        let text = String(buffer: part)
        try await processCodexResponsesSSEText(
            text,
            actorHelper: actorHelper,
            state: &state,
            metadata: &metadata
        )

        let currentTime = Date().timeIntervalSince1970
        if currentTime - lastSendTime >= 0.5, await actorHelper.hasPendingDelta() {
            let currentResult = await actorHelper.getResult()
            try await action(currentResult)
            lastSendTime = currentTime
        }
    }

    try await processCodexResponsesSSEText(
        "",
        actorHelper: actorHelper,
        state: &state,
        metadata: &metadata,
        finalize: true
    )

    if await actorHelper.hasPendingDelta() {
        let finalStreamResult = await actorHelper.getResult()
        try await action(finalStreamResult)
    }

    return await OpenAIChatResult(
        fullThinkingText: actorHelper.fullThinkingText,
        fullText: actorHelper.fullText,
        allToolCalls: actorHelper.allToolCalls,
        usage: state.usage,
        providerName: metadata.providerName,
        requestID: metadata.requestID,
        resolvedModel: metadata.resolvedModel,
        resolvedBasePath: metadata.resolvedBasePath
    )
}

nonisolated func makeCodexResponsesRequest(
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
    think: Bool?,
    reasoningEffort: OpenAIReasoningEffort?,
    extraBody: [String: AnyCodableValue]?,
    extraHeaders: [String: String]?
) throws -> HTTPClientRequest {
    guard let baseURL = modelInfo.baseURL else {
        throw OpenAIError.invalidURL
    }

    let url = appendResponsesPath(to: baseURL)
    let body = try makeCodexResponsesRequestBody(
        modelInfo: modelInfo,
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
        think: think,
        reasoningEffort: reasoningEffort,
        extraBody: extraBody
    )

    var request = HTTPClientRequest(url: url.absoluteString)
    request.method = .POST
    request.headers.add(name: "Content-Type", value: "application/json")
    request.headers.add(name: "Accept", value: "text/event-stream")
    request.headers.add(name: "User-Agent", value: OpenAIConfiguration.defaultUserAgent)
    request.headers.add(name: "X-Title", value: OpenAIConfiguration.defaultXTitle)

    for (key, value) in extraHeaders ?? [:] {
        request.headers.replaceOrAdd(name: key, value: value)
    }
    for (key, value) in modelInfo.defaultHeaders {
        request.headers.replaceOrAdd(name: key, value: value)
    }

    request.body = .bytes(try JSONSerialization.data(withJSONObject: body, options: []))
    return request
}

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
    think: Bool?,
    reasoningEffort: OpenAIReasoningEffort?,
    extraBody: [String: AnyCodableValue]?
) throws -> [String: Any] {
    let preparedPrompt = try prepareCodexResponsesPrompt(messages)
    var body: [String: Any] = [
        "model": modelInfo.modelID,
        "instructions": preparedPrompt.instructions,
        "input": preparedPrompt.input,
        "stream": true,
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
        body["stop"] = try encodeStop(stop)
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
    if let reasoning = encodeResponsesReasoning(
        think: think,
        reasoningEffort: reasoningEffort
    ) {
        body["reasoning"] = reasoning
    }

    for (key, value) in extraBody ?? [:] {
        body[key] = value.anyValue
    }
    return body
}

private nonisolated func prepareCodexResponsesPrompt(
    _ messages: [ChatQuery.ChatCompletionMessageParam]
) throws -> (instructions: String, input: [[String: Any]]) {
    var instructionsParts: [String] = []
    var inputMessages: [ChatQuery.ChatCompletionMessageParam] = []

    for message in messages {
        switch message {
        case .system(let systemMessage):
            guard case .textContent(let text) = systemMessage.content else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                instructionsParts.append(trimmed)
            }
        default:
            inputMessages.append(message)
        }
    }

    let instructions = instructionsParts.isEmpty
        ? defaultCodexResponsesInstructions
        : instructionsParts.joined(separator: "\n\n")

    return (instructions, try encodeResponsesInputItems(inputMessages))
}

nonisolated func appendResponsesPath(to baseURL: URL) -> URL {
    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
    var path = components.path
    if path.hasSuffix("/") {
        path.removeLast()
    }
    if path.hasSuffix("/responses") {
        components.path = path
    } else {
        components.path = path + "/responses"
    }
    return components.url ?? baseURL
}

nonisolated func encodeResponsesInputItems(
    _ messages: [ChatQuery.ChatCompletionMessageParam]
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

        case .user(let userMessage):
            return [[
                "type": "message",
                "role": "user",
                "content": try encodeResponsesUserContent(userMessage.content)
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
            // Codex responses. We only replay visible assistant output plus tool calls.
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
                "output": try encodeResponsesToolOutput(toolMessage.content)
            ]]
        }
    }
}

private nonisolated func encodeResponsesUserContent(
    _ content: UserMessageParam.Content
) throws -> [[String: Any]] {
    switch content {
    case .string(let text):
        return [["type": "input_text", "text": text]]
    case .contentParts(let parts):
        return parts.map { part in
            switch part {
            case .text(let text):
                return ["type": "input_text", "text": text.text]
            case .image(let image):
                return [
                    "type": "input_image",
                    "image_url": image.imageUrl.url,
                    "detail": image.imageUrl.detail.rawValue
                ]
            }
        }
    }
}

private nonisolated func encodeResponsesToolOutput(
    _ content: ToolMessageParam.Content
) throws -> Any {
    switch content {
    case .textContent(let text):
        return text
    case .contentParts(let parts):
        return parts.map { part in
            switch part {
            case .text(let text):
                return [
                    "type": "input_text",
                    "text": text.text
                ]
            case .image(let image):
                return [
                    "type": "input_image",
                    "image_url": image.imageUrl.url,
                    "detail": image.imageUrl.detail.rawValue
                ]
            }
        }
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
    think: Bool?,
    reasoningEffort: OpenAIReasoningEffort?
) -> [String: Any]? {
    guard let reasoningEffort else {
        return nil
    }
    return [
        "effort": reasoningEffort.rawValue,
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
        let schemaObject = try parseJSONObjectString(schema.schema)
        return [
            "format": [
                "type": "json_schema",
                "name": schema.name,
                "strict": true,
                "schema": schemaObject
            ]
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

private nonisolated func parseJSONObjectString(_ schema: String) throws -> Any {
    guard let data = schema.data(using: .utf8) else {
        throw OpenAIError.invalidResponse("JSON Schema 不是有效的 UTF-8 字符串", code: 0)
    }
    return try JSONSerialization.jsonObject(with: data)
}

private nonisolated func encodeStop(_ stop: ChatQuery.Stop) throws -> Any {
    switch stop {
    case .string(let string):
        return string
    case .array(let array):
        return array
    }
}

private nonisolated func executeCodexResponsesRequest(
    _ request: HTTPClientRequest
) async throws -> HTTPClientResponse {
    try await HTTPClient.shared.execute(request, timeout: codexResponsesRequestTimeout)
}

private nonisolated func codexCollectBodyData(
    from body: HTTPClientResponse.Body?
) async throws -> Data {
    guard let body else { return Data() }
    let buffer = try await body.collect(upTo: codexResponsesBodyLimit)
    guard let bytes = buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes) else {
        return Data()
    }
    return Data(bytes)
}

private nonisolated func codexResponseBodyString(
    from body: HTTPClientResponse.Body?
) async throws -> String {
    let data = try await codexCollectBodyData(from: body)
    return String(data: data, encoding: .utf8) ?? "无法解析响应内容（非UTF-8）"
}

nonisolated func processCodexResponsesSSEText(
    _ text: String,
    actorHelper: OpenAISendMessageValueHelper,
    state: inout CodexResponsesStreamState,
    metadata: inout ChatResponseMetadata,
    finalize: Bool = false
) async throws {
    state.pendingText += text

    while let newlineIndex = state.pendingText.firstIndex(of: "\n") {
        var line = String(state.pendingText[..<newlineIndex])
        state.pendingText.removeSubrange(...newlineIndex)
        if line.hasSuffix("\r") {
            line.removeLast()
        }
        try await processCodexResponsesSSELine(
            line,
            actorHelper: actorHelper,
            state: &state,
            metadata: &metadata
        )
    }

    if finalize, !state.pendingText.isEmpty {
        let line = state.pendingText
        state.pendingText.removeAll(keepingCapacity: false)
        try await processCodexResponsesSSELine(
            line,
            actorHelper: actorHelper,
            state: &state,
            metadata: &metadata
        )
    }
}

private nonisolated func processCodexResponsesSSELine(
    _ line: String,
    actorHelper: OpenAISendMessageValueHelper,
    state: inout CodexResponsesStreamState,
    metadata: inout ChatResponseMetadata
) async throws {
    guard !line.isEmpty, !line.hasPrefix(":") else { return }
    guard line.hasPrefix("data:") else { return }

    let dataString = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
    guard !dataString.isEmpty else { return }
    if dataString == "[DONE]" {
        return
    }

    guard let data = dataString.data(using: .utf8),
          let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let type = json["type"] as? String else {
        throw OpenAIError.invalidResponse(dataString, code: 200)
    }

    switch type {
    case "response.created":
        if let response = json["response"] as? [String: Any] {
            state.responseID = response["id"] as? String ?? state.responseID
            if let model = response["model"] as? String, !model.isEmpty {
                state.resolvedModel = model
                metadata = ChatResponseMetadata(
                    providerName: metadata.providerName,
                    requestID: metadata.requestID,
                    resolvedModel: model,
                    resolvedBasePath: metadata.resolvedBasePath
                )
            }
        }

    case "response.output_text.delta":
        let delta = (json["delta"] as? String) ?? ""
        await actorHelper.setText(thinkingText: "", text: delta)

    case "response.reasoning_text.delta":
        state.prefersReasoningText = true
        let delta = (json["delta"] as? String) ?? ""
        await actorHelper.setText(thinkingText: delta, text: "")

    case "response.reasoning_summary_text.delta":
        if state.prefersReasoningText {
            return
        }
        let delta = (json["delta"] as? String) ?? ""
        await actorHelper.setText(thinkingText: delta, text: "")

    case "response.function_call_arguments.delta":
        guard
            let itemID = json["item_id"] as? String,
            let delta = json["delta"] as? String,
            let index = state.toolCallIndexByItemID[itemID]
        else {
            return
        }
        let existingCalls = await actorHelper.allToolCalls
        guard index < existingCalls.count else { return }
        let existingCall = existingCalls[index]
        let updatedCall = ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall(
            index: index,
            id: existingCall.id,
            type: existingCall.type,
            function: .init(
                name: existingCall.function?.name ?? "",
                arguments: (existingCall.function?.arguments ?? "") + delta
            )
        )
        await actorHelper.setAllToolCalls(index: index, call: updatedCall)

    case "response.output_item.added", "response.output_item.done":
        guard let item = json["item"] as? [String: Any] else { return }
        try await applyCodexOutputItem(
            item,
            actorHelper: actorHelper,
            state: &state
        )

    case "response.completed":
        if let response = json["response"] as? [String: Any] {
            state.responseID = response["id"] as? String ?? state.responseID
            if let usage = response["usage"] as? [String: Any] {
                state.usage = makeUsageInfo(from: usage)
                await actorHelper.setUsage(state.usage)
            }
            if let model = response["model"] as? String, !model.isEmpty {
                state.resolvedModel = model
                metadata = ChatResponseMetadata(
                    providerName: metadata.providerName,
                    requestID: metadata.requestID,
                    resolvedModel: model,
                    resolvedBasePath: metadata.resolvedBasePath
                )
            }
        }

    case "response.failed":
        if let response = json["response"] as? [String: Any],
           let error = response["error"] as? [String: Any] {
            let message = (error["message"] as? String) ?? dataString
            throw OpenAIError.invalidResponse(message, code: 200)
        }
        throw OpenAIError.invalidResponse(dataString, code: 200)

    case "response.incomplete":
        let reason = ((json["response"] as? [String: Any])?["incomplete_details"] as? [String: Any])?["reason"] as? String
        throw OpenAIError.invalidResponse("Incomplete response returned, reason: \(reason ?? "unknown")", code: 200)

    default:
        return
    }
}

private nonisolated func applyCodexOutputItem(
    _ item: [String: Any],
    actorHelper: OpenAISendMessageValueHelper,
    state: inout CodexResponsesStreamState
) async throws {
    guard let itemType = item["type"] as? String else { return }

    switch itemType {
    case "function_call":
        let callID = (item["call_id"] as? String) ?? (item["id"] as? String) ?? UUID().uuidString
        let itemID = item["id"] as? String
        let name = item["name"] as? String
        let arguments = item["arguments"] as? String ?? ""

        let index: Int
        if let existingIndex = state.toolCallIndexByCallID[callID] ?? itemID.flatMap({ state.toolCallIndexByItemID[$0] }) {
            index = existingIndex
        } else {
            index = state.nextToolCallIndex
            state.nextToolCallIndex += 1
        }

        state.toolCallIndexByCallID[callID] = index
        if let itemID {
            state.toolCallIndexByItemID[itemID] = index
        }

        let existingCalls = await actorHelper.allToolCalls
        let existingCall = index < existingCalls.count ? existingCalls[index] : nil
        let updatedCall = ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall(
            index: index,
            id: callID,
            type: existingCall?.type ?? "function",
            function: .init(
                name: name ?? existingCall?.function?.name ?? "",
                arguments: arguments.isEmpty ? (existingCall?.function?.arguments ?? "") : arguments
            )
        )

        if existingCall == nil {
            await actorHelper.appendAllToolCalls(updatedCall)
        } else {
            await actorHelper.setAllToolCalls(index: index, call: updatedCall)
        }

    default:
        return
    }
}

nonisolated func makeUsageInfo(
    from usage: [String: Any]
) -> ChatStreamResult.Choice.UsageInfo {
    let promptDetails = usage["input_tokens_details"] as? [String: Any]
    let completionDetails = usage["output_tokens_details"] as? [String: Any]
    return ChatStreamResult.Choice.UsageInfo(
        promptTokens: usage["input_tokens"] as? Int,
        completionTokens: usage["output_tokens"] as? Int,
        totalTokens: usage["total_tokens"] as? Int,
        cachedTokens: (usage["cached_tokens"] as? Int) ?? (promptDetails?["cached_tokens"] as? Int),
        reasoningTokens: (usage["reasoning_tokens"] as? Int) ?? (completionDetails?["reasoning_tokens"] as? Int)
    )
}

#endif
