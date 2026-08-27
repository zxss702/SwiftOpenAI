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

private let responsesRequestTimeout: TimeAmount = .seconds(300)
private let responsesBodyLimit = 64 * 1024 * 1024

#endif

nonisolated func sendResponsesMessage(
    modelInfo: AIModelInfoValue.ResponsesInfo,
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
        pathLabel: "Responses"
    )

    guard let baseURL = modelInfo.baseURL else {
        throw OpenAIError.invalidURL
    }

    let prepared = try makeResponsesURLRequest(
        config: ResponsesRequestConfig(
            modelID: modelInfo.modelID,
            baseURL: baseURL,
            resolvedBasePath: modelInfo.basePath ?? "/v1",
            providerName: "openai-responses",
            defaultHeaders: modelInfo.defaultHeaders,
            requireDefaultInstructions: false
        ),
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
        thinkLevel: thinkLevel,
        extraBody: extraBody,
        extraHeaders: extraHeaders
    )

    return try await executeResponsesStream(
        preparedRequest: prepared,
        action: action
    )
}

nonisolated func executeResponsesStream(
    preparedRequest: PreparedResponsesRequest,
    action: @escaping @Sendable (OpenAIChatStreamResult) async throws -> Void
) async throws -> OpenAIChatResult {
#if !os(Windows)
    try await executeResponsesStreamWithHTTPClient(
        preparedRequest: preparedRequest,
        action: action
    )
#else
    try await executeResponsesStreamWithURLSession(
        preparedRequest: preparedRequest,
        action: action
    )
#endif
}

#if !os(Windows)

private nonisolated func executeResponsesStreamWithHTTPClient(
    preparedRequest: PreparedResponsesRequest,
    action: @escaping @Sendable (OpenAIChatStreamResult) async throws -> Void
) async throws -> OpenAIChatResult {
    let request = try makeHTTPClientRequest(from: preparedRequest.urlRequest)
    let actorHelper = OpenAISendMessageValueHelper()
    let response = try await HTTPClient.shared.execute(request, timeout: responsesRequestTimeout)

    guard (200...299).contains(Int(response.status.code)) else {
        let responseBody = try await responsesBodyString(from: response.body)
        throw OpenAIError.invalidResponse(responseBody, code: Int(response.status.code))
    }

    var lastSendTime = Date().timeIntervalSince1970
    var state = ResponsesStreamState()
    var metadata = preparedRequest.metadata.withRequestID(
        ProviderResponseNormalizer.requestID(from: response.headers)
    )

    for try await part in response.body {
        try Task.checkCancellation()
        try await processResponsesSSEBytes(
            part.sseDataBytes,
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

    try await processResponsesSSEBytes(
        Data(),
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

private nonisolated func makeHTTPClientRequest(from urlRequest: URLRequest) throws -> HTTPClientRequest {
    guard let url = urlRequest.url else {
        throw OpenAIError.invalidURL
    }

    var request = HTTPClientRequest(url: url.absoluteString)
    request.method = .POST

    if let headers = urlRequest.allHTTPHeaderFields {
        for (name, value) in headers {
            request.headers.add(name: name, value: value)
        }
    }

    if let body = urlRequest.httpBody {
        request.body = .bytes(body)
    }

    return request
}

private nonisolated func responsesCollectBodyData(
    from body: HTTPClientResponse.Body?
) async throws -> Data {
    guard let body else { return Data() }
    let buffer = try await body.collect(upTo: responsesBodyLimit)
    guard let bytes = buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes) else {
        return Data()
    }
    return Data(bytes)
}

private nonisolated func responsesBodyString(
    from body: HTTPClientResponse.Body?
) async throws -> String {
    let data = try await responsesCollectBodyData(from: body)
    return String(data: data, encoding: .utf8) ?? "无法解析响应内容（非UTF-8）"
}

#endif
