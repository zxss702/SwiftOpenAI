import Foundation

/// 发送聊天消息（流式）
///
/// 提供简化的流式聊天接口，自动处理流式响应并提供增量回调。
///
/// - Parameters:
///   - modelInfo: AI 模型配置信息
///   - messages: 对话消息列表
///   - frequencyPenalty: 频率惩罚系数（-2.0 到 2.0）
///   - maxCompletionTokens: 最大生成 token 数
///   - n: 生成的完成数量
///   - parallelToolCalls: 是否允许并行工具调用
///   - prediction: 预测输出配置
///   - presencePenalty: 存在惩罚系数（-2.0 到 2.0）
///   - responseFormat: 响应格式配置
///   - stop: 停止词
///   - temperature: 温度参数（0.0 到 2.0），默认为 0.6
///   - toolChoice: 工具选择策略
///   - tools: 可用工具列表（支持直接传入工具对象）
///   - topP: nucleus sampling 参数
///   - user: 终端用户标识符
///   - stream: 是否使用流式传输，默认为 true
///   - think: 统一的思考开关，按厂商自动映射
///   - reasoningEffort: OpenAI/GPT 推理强度
///   - extraBody: 额外的请求体参数
///   - extraHeaders: 额外的 HTTP 请求头
///   - action: 流式结果回调闭包
///
/// - Returns: 最终的聊天结果
/// - Throws: 如果请求失败或被取消
///
/// ## Example
///
/// ```swift
/// let result = try await sendMessage(
///     modelInfo: modelInfo,
///     messages: [.user("你好")],
///     tools: [MyTool.self]
/// ) { streamResult in
///     print(streamResult.subText)
/// }
/// print(result.fullText)
/// ```
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
    temperature: Double? = 1,
    toolChoice: ChatQuery.ChatCompletionFunctionCallOptionParam? = nil,
    tools: [any OpenAIToolConvertible]? = nil,
    topP: Double? = nil,
    user: String? = nil,
    stream: Bool = true,
    think: Bool? = nil,
    reasoningEffort: OpenAIReasoningEffort? = nil,
    extraBody: [String: AnyCodableValue]? = nil,
    extraHeaders: [String: String]? = nil,
    action: @escaping @Sendable (OpenAIChatStreamResult) async throws -> Void
) async throws -> OpenAIChatResult {
    switch modelInfo {
    case .completions(let completionsInfo):
        return try await sendCompletionsMessage(
            modelInfo: completionsInfo,
            messages: messages,
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
            tools: tools,
            topP: topP,
            user: user,
            stream: stream,
            think: think,
            reasoningEffort: reasoningEffort,
            extraBody: extraBody,
            extraHeaders: extraHeaders,
            action: action
        )
    case .codex(let codexInfo):
        return try await sendCodexResponsesMessage(
            modelInfo: codexInfo,
            messages: messages,
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
            tools: tools?.map(\.asChatCompletionTool),
            topP: topP,
            user: user,
            think: think,
            reasoningEffort: reasoningEffort,
            extraBody: extraBody,
            extraHeaders: extraHeaders,
            action: action
        )
    }
}

/// 发送聊天消息（非流式）
///
/// 提供简化的非流式聊天接口，等待完整响应后返回统一结果。
nonisolated public func sendMessageSync(
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
    tools: [any OpenAIToolConvertible]? = nil,
    topP: Double? = nil,
    user: String? = nil,
    think: Bool? = nil,
    reasoningEffort: OpenAIReasoningEffort? = nil,
    extraBody: [String: AnyCodableValue]? = nil,
    extraHeaders: [String: String]? = nil
) async throws -> OpenAIChatResult {
    switch modelInfo {
    case .completions(let completionsInfo):
        return try await sendCompletionsMessageSync(
            modelInfo: completionsInfo,
            messages: messages,
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
            tools: tools,
            topP: topP,
            user: user,
            think: think,
            reasoningEffort: reasoningEffort,
            extraBody: extraBody,
            extraHeaders: extraHeaders
        )
    case .codex(let codexInfo):
        return try await sendCodexResponsesMessage(
            modelInfo: codexInfo,
            messages: messages,
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
            tools: tools?.map(\.asChatCompletionTool),
            topP: topP,
            user: user,
            think: think,
            reasoningEffort: reasoningEffort,
            extraBody: extraBody,
            extraHeaders: extraHeaders
        ) { _ in }
    }
}

private nonisolated func sendCompletionsMessage(
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
    think: Bool?,
    reasoningEffort: OpenAIReasoningEffort?,
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
        think: think,
        reasoningEffort: reasoningEffort,
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

private nonisolated func sendCompletionsMessageSync(
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
    think: Bool?,
    reasoningEffort: OpenAIReasoningEffort?,
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
        think: think,
        reasoningEffort: reasoningEffort,
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
