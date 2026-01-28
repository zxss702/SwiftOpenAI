import Foundation

/// 发送消息的主函数，提供与MacPaw OpenAI相似的使用方式（支持直接传入工具对象）
nonisolated public func sendMessage(
    modelInfo: AIModelInfoValue,
    messages: [ChatQuery.ChatCompletionMessageParam],
    frequencyPenalty: Double? = nil,
    maxCompletionTokens: Int? = nil,
    n: Int? = nil,
    parallelToolCalls: Bool? = nil,
    prediction: ChatQuery.PredictedOutputConfig? = nil,
    presencePenalty: Double? = nil,
    responseFormat: ChatQuery.ResponseFormat? = nil,
    stop: ChatQuery.Stop? = nil,
    temperature: Double? = 0.6,
    toolChoice: ChatQuery.ChatCompletionFunctionCallOptionParam? = nil,
    tools: [any OpenAIToolConvertible]? = nil,  // 🆕 直接支持工具对象
    topP: Double? = nil,
    user: String? = nil,
    stream: Bool = true,
    extraBody: [String: AnyCodableValue]? = nil,
    extraHeaders: [String: String]? = nil,
    action: (OpenAIChatStreamResult) async throws -> Void
) async throws -> OpenAIChatResult {
    let actorHelper = OpenAISendMessageValueHelper()
    let resolvedModelInfo = modelInfo
    
    // 创建OpenAI配置
    let configuration = OpenAIConfiguration(
        token: resolvedModelInfo.token,
        host: resolvedModelInfo.host,
        port: resolvedModelInfo.port,
        scheme: resolvedModelInfo.scheme,
        basePath: resolvedModelInfo.basePath,
        extraHeaders: extraHeaders
    )
    
    let openAI = OpenAI(configuration: configuration)
    
    // 创建查询
    let query = ChatQuery(
        messages: messages,
        model: resolvedModelInfo.modelID,
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
        tools: tools?.map { $0.asChatCompletionTool }, // 自动转换工具对象为ChatCompletionToolParam
        topP: topP,
        user: user,
        stream: stream,
        extraBody: extraBody
    )
    
    // 处理流式响应
    for try await result in openAI.chatsStream(query: query) {
        try Task.checkCancellation()
        
        if let choice = result.choices.first {
            await actorHelper.setText(
                thinkingText: choice.delta.reasoning ?? "",
                text: choice.delta.content ?? ""
            )
            
            if let toolCalls = choice.delta.toolCalls {
                for call in toolCalls {
                    if let index = await actorHelper.allToolCalls.firstIndex(where: { $0.index == call.index }) {
                        // 更新已存在的tool call
                        let existingCall = await actorHelper.allToolCalls[index]
                        let updatedCall = ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall(
                            index: existingCall.index,
                            id: existingCall.id ?? call.id,
                            type: existingCall.type ?? call.type,
                            function: ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall.ChoiceDeltaToolCallFunction(
                                name: (existingCall.function?.name ?? "") + (call.function?.name ?? ""),
                                arguments: (existingCall.function?.arguments ?? "") + (call.function?.arguments ?? "")
                            )
                        )
                        await actorHelper.setAllToolCalls(index: index, call: updatedCall)
                    } else {
                        // 添加新的tool call
                        await actorHelper.appendAllToolCalls(call)
                    }
                }
            }
            
            // 调用用户提供的action回调
            try await action(OpenAIChatStreamResult(
                subThinkingText: choice.delta.reasoning ?? "",
                subText: choice.delta.content ?? "",
                fullThinkingText: await actorHelper.fullThinkingText,
                fullText: await actorHelper.fullText,
                state: await actorHelper.state,
                allToolCalls: await actorHelper.allToolCalls
            ))
        }
    }
    
    // 设置完成状态
    await actorHelper.setState(.text)
    
    // 返回最终结果
    return await OpenAIChatResult(
        fullThinkingText: actorHelper.fullThinkingText,
        fullText: actorHelper.fullText,
        state: actorHelper.state,
        allToolCalls: actorHelper.allToolCalls
    )
}
