import Foundation

nonisolated func sendCompletionsMessage(
    modelInfo: AIModelInfoValue.CompletionsInfo,
    messages: [ChatQuery.ChatCompletionMessageParam],
    frequencyPenalty: Double?,
    maxCompletionTokens: Int?,
    n: Int?,
    parallelToolCalls: Bool?,
    prediction: ChatQuery.PredictedOutputConfig?,
    presencePenalty: Double?,
    responseFormat: ChatQuery.ResponseFormat?,
    stop: ChatQuery.Stop?,
    temperature: Double?,
    toolChoice: ChatQuery.ChatCompletionFunctionCallOptionParam?,
    tools: [any OpenAIToolConvertible]?,
    topP: Double?,
    user: String?,
    stream: Bool,
    thinkLevel: ThinkLevel?,
    extraBody: [String: AnyCodableValue]?,
    extraHeaders: [String: String]?,
    action: @escaping @Sendable (OpenAIChatStreamResult) async throws -> Void
) async throws -> OpenAIChatResult {
    let actorHelper = OpenAISendMessageValueHelper()

    let configuration = OpenAIConfiguration(
        token: modelInfo.token,
        host: modelInfo.host,
        port: modelInfo.port,
        scheme: modelInfo.scheme,
        basePath: modelInfo.basePath,
        extraHeaders: extraHeaders
    )

    let openAI = OpenAI(configuration: configuration)

    let query = ChatQuery(
        messages: messages,
        model: modelInfo.modelID,
        frequencyPenalty: frequencyPenalty,
        maxCompletionTokens: maxCompletionTokens,
        n: n,
        parallelToolCalls: parallelToolCalls,
        prediction: prediction,
        presencePenalty: presencePenalty,
        responseFormat: responseFormat,
        stop: stop,
        temperature: temperature,
        toolChoice: toolChoice,
        tools: tools?.map { $0.asChatCompletionTool },
        topP: topP,
        user: user,
        stream: stream,
        thinkLevel: thinkLevel,
        extraBody: extraBody
    )

    var lastSendTime = Date().timeIntervalSince1970
    var responseMetadata = ChatResponseMetadata(
        providerName: ProviderFamilyResolver.resolve(host: modelInfo.host).providerName,
        requestID: nil,
        resolvedModel: modelInfo.modelID,
        resolvedBasePath: modelInfo.basePath ?? "/v1"
    )

    for try await envelope in openAI.chatsStreamEnvelope(query: query) {
        try Task.checkCancellation()
        let result = envelope.result
        responseMetadata = envelope.metadata

        if let usage = result.usage ?? result.choices.first?.usage {
            await actorHelper.setUsage(usage)
        }

        if let choice = result.choices.first {
            await actorHelper.setText(
                thinkingText: choice.delta.reasoning ?? "",
                text: choice.delta.content ?? ""
            )

            if let toolCalls = choice.delta.toolCalls {
                for call in toolCalls {
                    if let index = await actorHelper.allToolCalls.firstIndex(where: { $0.index == call.index }) {
                        let existingCall = await actorHelper.allToolCalls[index]
                        let updatedCall = ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall(
                            index: existingCall.index,
                            id: existingCall.id ?? call.id,
                            type: existingCall.type ?? call.type,
                            function: .init(
                                name: (existingCall.function?.name ?? "") + (call.function?.name ?? ""),
                                arguments: (existingCall.function?.arguments ?? "") + (call.function?.arguments ?? "")
                            )
                        )
                        await actorHelper.setAllToolCalls(index: index, call: updatedCall)
                    } else {
                        await actorHelper.appendAllToolCalls(call)
                    }
                }
            }
        }

        let currentTime = Date().timeIntervalSince1970
        if currentTime - lastSendTime >= 0.5 {
            let currentResult = await actorHelper.getResult()
            try await action(currentResult)
            lastSendTime = currentTime
        }
    }

    let finalResult = await actorHelper.getResult()
    try await action(finalResult)

    return await OpenAIChatResult(
        fullThinkingText: actorHelper.fullThinkingText,
        fullText: actorHelper.fullText,
        allToolCalls: actorHelper.allToolCalls,
        usage: await actorHelper.usage,
        providerName: responseMetadata.providerName,
        requestID: responseMetadata.requestID,
        resolvedModel: responseMetadata.resolvedModel,
        resolvedBasePath: responseMetadata.resolvedBasePath
    )
}

nonisolated func sendCompletionsMessageSync(
    modelInfo: AIModelInfoValue.CompletionsInfo,
    messages: [ChatQuery.ChatCompletionMessageParam],
    frequencyPenalty: Double?,
    maxCompletionTokens: Int?,
    n: Int?,
    parallelToolCalls: Bool?,
    prediction: ChatQuery.PredictedOutputConfig?,
    presencePenalty: Double?,
    responseFormat: ChatQuery.ResponseFormat?,
    stop: ChatQuery.Stop?,
    temperature: Double?,
    toolChoice: ChatQuery.ChatCompletionFunctionCallOptionParam?,
    tools: [any OpenAIToolConvertible]?,
    topP: Double?,
    user: String?,
    thinkLevel: ThinkLevel?,
    extraBody: [String: AnyCodableValue]?,
    extraHeaders: [String: String]?
) async throws -> OpenAIChatResult {
    let configuration = OpenAIConfiguration(
        token: modelInfo.token,
        host: modelInfo.host,
        port: modelInfo.port,
        scheme: modelInfo.scheme,
        basePath: modelInfo.basePath,
        extraHeaders: extraHeaders
    )

    let openAI = OpenAI(configuration: configuration)
    let query = ChatQuery(
        messages: messages,
        model: modelInfo.modelID,
        frequencyPenalty: frequencyPenalty,
        maxCompletionTokens: maxCompletionTokens,
        n: n,
        parallelToolCalls: parallelToolCalls,
        prediction: prediction,
        presencePenalty: presencePenalty,
        responseFormat: responseFormat,
        stop: stop,
        temperature: temperature,
        toolChoice: toolChoice,
        tools: tools?.map { $0.asChatCompletionTool },
        topP: topP,
        user: user,
        stream: false,
        thinkLevel: thinkLevel,
        extraBody: extraBody
    )

    let envelope = try await openAI.chatCompletionEnvelope(query: query)
    let message = envelope.result.choices.first?.message
    let usage = envelope.result.usage.map {
        ChatStreamResult.Choice.UsageInfo(
            promptTokens: $0.promptTokens,
            completionTokens: $0.completionTokens,
            totalTokens: $0.totalTokens,
            cachedTokens: $0.cachedTokens,
            promptCacheHitTokens: $0.promptCacheHitTokens,
            promptCacheMissTokens: $0.promptCacheMissTokens,
            reasoningTokens: $0.reasoningTokens
        )
    }

    let allToolCalls: [ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall]
    if let toolCalls = message?.toolCalls {
        allToolCalls = toolCalls.enumerated().map { index, toolCall in
            ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall(
                index: index,
                id: toolCall.id,
                type: toolCall.type,
                function: .init(name: toolCall.function.name, arguments: toolCall.function.arguments)
            )
        }
    } else {
        allToolCalls = []
    }

    return OpenAIChatResult(
        fullThinkingText: message?.reasoning ?? "",
        fullText: message?.content ?? "",
        allToolCalls: allToolCalls,
        usage: usage,
        providerName: envelope.metadata.providerName,
        requestID: envelope.metadata.requestID,
        resolvedModel: envelope.metadata.resolvedModel,
        resolvedBasePath: envelope.metadata.resolvedBasePath
    )
}
