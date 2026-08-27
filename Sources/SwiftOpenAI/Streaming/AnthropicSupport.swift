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

private let anthropicRequestTimeout: TimeAmount = .seconds(300)
private let anthropicBodyLimit = 64 * 1024 * 1024

#endif

nonisolated func sendAnthropicMessage(
    modelInfo: AIModelInfoValue.AnthropicInfo,
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
    try validateAnthropicParameters(
        prediction: prediction,
        n: n,
        frequencyPenalty: frequencyPenalty,
        presencePenalty: presencePenalty,
        user: user,
        responseFormat: responseFormat
    )

    let prepared = try makeAnthropicURLRequest(
        modelInfo: modelInfo,
        messages: messages,
        maxCompletionTokens: maxCompletionTokens,
        parallelToolCalls: parallelToolCalls,
        stop: stop,
        temperature: temperature,
        toolChoice: toolChoice,
        tools: tools,
        topP: topP,
        thinkLevel: thinkLevel,
        extraBody: extraBody,
        extraHeaders: extraHeaders
    )

    return try await executeAnthropicStream(
        preparedRequest: prepared,
        action: action
    )
}

nonisolated func executeAnthropicStream(
    preparedRequest: PreparedAnthropicRequest,
    action: @escaping @Sendable (OpenAIChatStreamResult) async throws -> Void
) async throws -> OpenAIChatResult {
#if !os(Windows)
    try await executeAnthropicStreamWithHTTPClient(
        preparedRequest: preparedRequest,
        action: action
    )
#else
    try await executeAnthropicStreamWithURLSession(
        preparedRequest: preparedRequest,
        action: action
    )
#endif
}

#if !os(Windows)

private nonisolated func executeAnthropicStreamWithHTTPClient(
    preparedRequest: PreparedAnthropicRequest,
    action: @escaping @Sendable (OpenAIChatStreamResult) async throws -> Void
) async throws -> OpenAIChatResult {
    let request = try makeAnthropicHTTPClientRequest(from: preparedRequest.urlRequest)
    let actorHelper = OpenAISendMessageValueHelper()
    let response = try await HTTPClient.shared.execute(request, timeout: anthropicRequestTimeout)

    guard (200...299).contains(Int(response.status.code)) else {
        let responseBody = try await anthropicBodyString(from: response.body)
        throw OpenAIError.invalidResponse(responseBody, code: Int(response.status.code))
    }

    var lastSendTime = Date().timeIntervalSince1970
    var state = AnthropicStreamState()
    var metadata = preparedRequest.metadata.withRequestID(
        ProviderResponseNormalizer.requestID(from: response.headers)
    )

    for try await part in response.body {
        try Task.checkCancellation()
        try await processAnthropicSSEBytes(
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

    try await processAnthropicSSEBytes(
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

private nonisolated func makeAnthropicHTTPClientRequest(from urlRequest: URLRequest) throws -> HTTPClientRequest {
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

private nonisolated func anthropicCollectBodyData(
    from body: HTTPClientResponse.Body?
) async throws -> Data {
    guard let body else { return Data() }
    let buffer = try await body.collect(upTo: anthropicBodyLimit)
    guard let bytes = buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes) else {
        return Data()
    }
    return Data(bytes)
}

private nonisolated func anthropicBodyString(
    from body: HTTPClientResponse.Body?
) async throws -> String {
    let data = try await anthropicCollectBodyData(from: body)
    return String(data: data, encoding: .utf8) ?? "无法解析响应内容（非UTF-8）"
}

#endif
