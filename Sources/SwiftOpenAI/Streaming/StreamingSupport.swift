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
///   - thinkLevel: 统一思考强度（none 关闭，其余为等级），按厂商自动映射
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
    thinkLevel: ThinkLevel? = nil,
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
            thinkLevel: thinkLevel,
            extraBody: extraBody,
            extraHeaders: extraHeaders,
            action: action
        )
    case .responses(let responsesInfo):
        return try await sendResponsesMessage(
            modelInfo: responsesInfo,
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
            thinkLevel: thinkLevel,
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
            thinkLevel: thinkLevel,
            extraBody: extraBody,
            extraHeaders: extraHeaders,
            action: action
        )
    case .anthropic(let anthropicInfo):
        return try await sendAnthropicMessage(
            modelInfo: anthropicInfo,
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
            thinkLevel: thinkLevel,
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
    thinkLevel: ThinkLevel? = nil,
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
            thinkLevel: thinkLevel,
            extraBody: extraBody,
            extraHeaders: extraHeaders
        )
    case .responses(let responsesInfo):
        return try await sendResponsesMessage(
            modelInfo: responsesInfo,
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
            thinkLevel: thinkLevel,
            extraBody: extraBody,
            extraHeaders: extraHeaders
        ) { _ in }
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
            thinkLevel: thinkLevel,
            extraBody: extraBody,
            extraHeaders: extraHeaders
        ) { _ in }
    case .anthropic(let anthropicInfo):
        return try await sendAnthropicMessage(
            modelInfo: anthropicInfo,
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
            thinkLevel: thinkLevel,
            extraBody: extraBody,
            extraHeaders: extraHeaders
        ) { _ in }
    }
}
