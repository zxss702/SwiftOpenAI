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
    temperature: Double? = 0.6,
    toolChoice: ChatQuery.ChatCompletionFunctionCallOptionParam? = nil,
    tools: [any OpenAIToolConvertible]? = nil,
    topP: Double? = nil,
    user: String? = nil,
    stream: Bool = true,
    extraBody: [String: AnyCodableValue]? = nil,
    extraHeaders: [String: String]? = nil,
    action: @escaping @Sendable (OpenAIChatStreamResult) async throws -> Void
) async throws -> OpenAIChatResult {
    let actorHelper = OpenAISendMessageValueHelper()
    let resolvedModelInfo = modelInfo
    
    let configuration = OpenAIConfiguration(
        token: resolvedModelInfo.token,
        host: resolvedModelInfo.host,
        port: resolvedModelInfo.port,
        scheme: resolvedModelInfo.scheme,
        basePath: resolvedModelInfo.basePath,
        extraHeaders: extraHeaders
    )
    
    let openAI = OpenAI(configuration: configuration)
    
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
        tools: tools?.map { $0.asChatCompletionTool },
        topP: topP,
        user: user,
        stream: stream,
        extraBody: extraBody
    )
    
    let task = Task.detached { [weak actorHelper] in
        while !Task.isCancelled, let actorHelper {
            if await actorHelper.hasPendingDelta() {
                let result = await actorHelper.peekResult()
                try await action(result)
                await actorHelper.clearPendingDelta()
            }
            try await Task.sleep(for: .seconds(0.2))
        }
    }
    defer {
        task.cancel()
    }
    
    for try await result in openAI.chatsStream(query: query) {
        try Task.checkCancellation()
        
        // 捕获 usage 信息（通常在最后一个 chunk 中返回）
        if let usage = result.choices.first?.usage {
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
                            function: ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall.ChoiceDeltaToolCallFunction(
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
    }
    
    task.cancel()
    
    if await actorHelper.hasPendingDelta() {
        let result = await actorHelper.peekResult()
        try await action(result)
        await actorHelper.clearPendingDelta()
    }
    
    await actorHelper.setState(.text)
    
    return await OpenAIChatResult(
        fullThinkingText: actorHelper.fullThinkingText,
        fullText: actorHelper.fullText,
        state: actorHelper.state,
        allToolCalls: actorHelper.allToolCalls,
        usage: await actorHelper.usage
    )
}
