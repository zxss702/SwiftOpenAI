import Foundation

struct ResponsesStreamState {
    var sseBuffer = SSEByteBuffer()
    var usage: ChatStreamResult.Choice.UsageInfo?
    var responseID: String?
    var resolvedModel: String?
    var toolCallIndexByCallID: [String: Int] = [:]
    var toolCallIndexByItemID: [String: Int] = [:]
    var nextToolCallIndex: Int = 0
    var prefersReasoningText = false
}

typealias CodexResponsesStreamState = ResponsesStreamState

nonisolated func processResponsesSSEBytes(
    _ bytes: Data,
    actorHelper: OpenAISendMessageValueHelper,
    state: inout ResponsesStreamState,
    metadata: inout ChatResponseMetadata,
    finalize: Bool = false
) async throws {
    state.sseBuffer.append(bytes)

    for line in state.sseBuffer.drainLines(finalize: finalize) {
        try await processResponsesSSELine(
            line,
            actorHelper: actorHelper,
            state: &state,
            metadata: &metadata
        )
    }
}

/// Codex-compatible alias used by existing tests.
nonisolated func processCodexResponsesSSEBytes(
    _ bytes: Data,
    actorHelper: OpenAISendMessageValueHelper,
    state: inout ResponsesStreamState,
    metadata: inout ChatResponseMetadata,
    finalize: Bool = false
) async throws {
    try await processResponsesSSEBytes(
        bytes,
        actorHelper: actorHelper,
        state: &state,
        metadata: &metadata,
        finalize: finalize
    )
}

private nonisolated func processResponsesSSELine(
    _ line: String,
    actorHelper: OpenAISendMessageValueHelper,
    state: inout ResponsesStreamState,
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
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let type = json["type"] as? String else {
        return
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
        try await applyResponsesOutputItem(
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

private nonisolated func applyResponsesOutputItem(
    _ item: [String: Any],
    actorHelper: OpenAISendMessageValueHelper,
    state: inout ResponsesStreamState
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
    let promptCacheHitTokens = usage["prompt_cache_hit_tokens"] as? Int
    let promptCacheMissTokens = usage["prompt_cache_miss_tokens"] as? Int
    return ChatStreamResult.Choice.UsageInfo(
        promptTokens: usage["input_tokens"] as? Int,
        completionTokens: usage["output_tokens"] as? Int,
        totalTokens: usage["total_tokens"] as? Int,
        cachedTokens: (usage["cached_tokens"] as? Int) ?? (promptDetails?["cached_tokens"] as? Int) ?? promptCacheHitTokens,
        promptCacheHitTokens: promptCacheHitTokens,
        promptCacheMissTokens: promptCacheMissTokens,
        reasoningTokens: (usage["reasoning_tokens"] as? Int) ?? (completionDetails?["reasoning_tokens"] as? Int)
    )
}
