import Foundation

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
    thinkLevel: ThinkLevel? = nil,
    extraBody: [String: AnyCodableValue]? = nil,
    extraHeaders: [String: String]? = nil,
    action: @escaping @Sendable (OpenAIChatStreamResult) async throws -> Void
) async throws -> OpenAIChatResult {
    try validateResponsesParameters(
        prediction: prediction,
        n: n,
        user: user,
        pathLabel: "Codex responses"
    )

    let priorBindings = MessageContentBlocks.aggregatedFileBindings(from: messages)
    let offload = try await offloadDeepSeekVisionImagesIfNeeded(
        messages: messages,
        baseURL: modelInfo.baseURL,
        modelID: modelInfo.modelID,
        bearerToken: modelInfo.accessToken,
        priorBindings: priorBindings,
        extraHeaders: extraHeaders
    )

    let prepared = try makeResponsesURLRequest(
        config: ResponsesRequestConfig(
            modelID: modelInfo.modelID,
            baseURL: try APIBaseURL.parse(modelInfo.baseURL),
            resolvedBasePath: APIBaseURL.configuredPath(of: modelInfo.baseURL),
            providerName: "openai-codex",
            defaultHeaders: modelInfo.defaultHeaders
        ),
        messages: offload.messages,
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
        extraHeaders: extraHeaders,
        fileBindings: offload.fileBindings
    )

    return try await executeResponsesStream(
        preparedRequest: prepared,
        action: action
    )
}
