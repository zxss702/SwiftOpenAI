import Foundation

struct AnthropicStreamState {
    var sseBuffer = SSEByteBuffer()
    var usage: ChatStreamResult.Choice.UsageInfo?
    var toolCallIndexByContentIndex: [Int: Int] = [:]
    var nextToolCallIndex: Int = 0
}

nonisolated func processAnthropicSSEBytes(
    _ bytes: Data,
    actorHelper: OpenAISendMessageValueHelper,
    state: inout AnthropicStreamState,
    metadata: inout ChatResponseMetadata,
    finalize: Bool = false
) async throws {
    state.sseBuffer.append(bytes)

    for line in state.sseBuffer.drainLines(finalize: finalize) {
        try await processAnthropicSSELine(
            line,
            actorHelper: actorHelper,
            state: &state,
            metadata: &metadata
        )
    }
}

private nonisolated func processAnthropicSSELine(
    _ line: String,
    actorHelper: OpenAISendMessageValueHelper,
    state: inout AnthropicStreamState,
    metadata: inout ChatResponseMetadata
) async throws {
    guard !line.isEmpty, !line.hasPrefix(":") else { return }
    // Anthropic may emit `event:` lines; we only consume `data:` payloads.
    guard line.hasPrefix("data:") else { return }

    let dataString = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
    guard !dataString.isEmpty, dataString != "[DONE]" else { return }

    guard let data = dataString.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let type = json["type"] as? String else {
        return
    }

    switch type {
    case "message_start":
        if let message = json["message"] as? [String: Any] {
            if let model = message["model"] as? String, !model.isEmpty {
                metadata = ChatResponseMetadata(
                    providerName: metadata.providerName,
                    requestID: metadata.requestID,
                    resolvedModel: model,
                    resolvedBasePath: metadata.resolvedBasePath
                )
            }
            if let usage = message["usage"] as? [String: Any] {
                state.usage = makeAnthropicUsageInfo(from: usage, previous: state.usage)
                await actorHelper.setUsage(state.usage)
            }
        }

    case "content_block_start":
        guard let index = json["index"] as? Int,
              let block = json["content_block"] as? [String: Any],
              let blockType = block["type"] as? String else {
            return
        }
        if blockType == "tool_use" {
            let callID = (block["id"] as? String) ?? UUID().uuidString
            let name = (block["name"] as? String) ?? ""
            let toolIndex = state.nextToolCallIndex
            state.nextToolCallIndex += 1
            state.toolCallIndexByContentIndex[index] = toolIndex
            await actorHelper.appendAllToolCalls(
                .init(
                    index: toolIndex,
                    id: callID,
                    type: "function",
                    function: .init(name: name, arguments: "")
                )
            )
        }

    case "content_block_delta":
        guard let index = json["index"] as? Int,
              let delta = json["delta"] as? [String: Any],
              let deltaType = delta["type"] as? String else {
            return
        }
        switch deltaType {
        case "text_delta":
            let text = (delta["text"] as? String) ?? ""
            await actorHelper.setText(thinkingText: "", text: text)
        case "thinking_delta":
            let thinking = (delta["thinking"] as? String) ?? ""
            await actorHelper.setText(thinkingText: thinking, text: "")
        case "input_json_delta":
            guard let toolIndex = state.toolCallIndexByContentIndex[index] else { return }
            let partial = (delta["partial_json"] as? String) ?? ""
            let existingCalls = await actorHelper.allToolCalls
            guard toolIndex < existingCalls.count else { return }
            let existing = existingCalls[toolIndex]
            let updated = ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall(
                index: toolIndex,
                id: existing.id,
                type: existing.type,
                function: .init(
                    name: existing.function?.name ?? "",
                    arguments: (existing.function?.arguments ?? "") + partial
                )
            )
            await actorHelper.setAllToolCalls(index: toolIndex, call: updated)
        default:
            return
        }

    case "message_delta":
        if let usage = json["usage"] as? [String: Any] {
            state.usage = makeAnthropicUsageInfo(from: usage, previous: state.usage)
            await actorHelper.setUsage(state.usage)
        }

    case "error":
        let errorObject = json["error"] as? [String: Any]
        let message = (errorObject?["message"] as? String) ?? dataString
        throw OpenAIError.invalidResponse(message, code: 200)

    case "ping", "content_block_stop", "message_stop":
        return

    default:
        return
    }
}

nonisolated func makeAnthropicUsageInfo(
    from usage: [String: Any],
    previous: ChatStreamResult.Choice.UsageInfo?
) -> ChatStreamResult.Choice.UsageInfo {
    let input = usage["input_tokens"] as? Int ?? previous?.promptTokens
    let output = usage["output_tokens"] as? Int ?? previous?.completionTokens
    let cacheRead = usage["cache_read_input_tokens"] as? Int
        ?? usage["cache_creation_input_tokens"] as? Int
        ?? previous?.cachedTokens
    let total: Int?
    if let input, let output {
        total = input + output
    } else {
        total = previous?.totalTokens
    }
    return ChatStreamResult.Choice.UsageInfo(
        promptTokens: input,
        completionTokens: output,
        totalTokens: total,
        cachedTokens: cacheRead,
        promptCacheHitTokens: usage["cache_read_input_tokens"] as? Int ?? previous?.promptCacheHitTokens,
        promptCacheMissTokens: previous?.promptCacheMissTokens,
        reasoningTokens: previous?.reasoningTokens
    )
}
