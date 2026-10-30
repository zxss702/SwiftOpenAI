import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if os(Windows)

nonisolated func executeResponsesStreamWithURLSession(
    preparedRequest: PreparedResponsesRequest,
    action: @escaping @Sendable (OpenAIChatStreamResult) async throws -> Void
) async throws -> OpenAIChatResult {
    try Task.checkCancellation()
    let (session, stream) = makeURLSessionStream(for: preparedRequest.urlRequest)
    defer { session.invalidateAndCancel() }

    return try await withTaskCancellationHandler {
        let actorHelper = OpenAISendMessageValueHelper()
        var state = ResponsesStreamState()
        var metadata = preparedRequest.metadata
        var statusCode = 0
        var responseBody = Data()
        var lastSendTime = Date().timeIntervalSince1970
        var codexTurnState = preparedRequest.codexTurnState(received: nil)

        streamLoop: for try await event in stream {
            try Task.checkCancellation()
            switch event {
            case .response(let response):
                statusCode = response.statusCode
                metadata = metadata.withRequestID(ProviderResponseNormalizer.requestID(from: response))
                codexTurnState = preparedRequest.codexTurnState(
                    received: response.value(forHTTPHeaderField: "x-codex-turn-state")
                )
            case .data(let data):
                if !(200...299).contains(statusCode) {
                    responseBody.append(data)
                    continue
                }
                try await processResponsesSSEBytes(
                    data,
                    actorHelper: actorHelper,
                    state: &state,
                    metadata: &metadata
                )
                if state.isComplete {
                    break streamLoop
                }

                let currentTime = Date().timeIntervalSince1970
                if currentTime - lastSendTime >= 0.5, await actorHelper.hasPendingDelta() {
                    let currentResult = await actorHelper.getResult()
                    try await action(currentResult)
                    lastSendTime = currentTime
                }
            }
        }

        try Task.checkCancellation()
        session.invalidateAndCancel()
        guard (200...299).contains(statusCode) else {
            let text = String(data: responseBody, encoding: .utf8) ?? "无法解析响应内容（非UTF-8）"
            throw mapDeepSeekBodyLimitError(message: text, code: statusCode)
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
        try Task.checkCancellation()

        return await OpenAIChatResult(
            fullThinkingText: actorHelper.fullThinkingText,
            fullText: actorHelper.fullText,
            allToolCalls: actorHelper.allToolCalls,
            usage: state.usage,
            providerName: metadata.providerName,
            requestID: metadata.requestID,
            resolvedModel: metadata.resolvedModel,
            resolvedBasePath: metadata.resolvedBasePath,
            contentBlocks: mergeContentBlocksForResult(
                anthropic: nil,
                fileBindings: preparedRequest.fileBindings,
                responses: ResponsesMessageContext(outputItems: state.outputItems),
                codexSessionID: metadata.providerName == "openai-codex"
                    ? preparedRequest.urlRequest.value(forHTTPHeaderField: "session-id") : nil,
                codexTurnState: codexTurnState,
                codexTurnScope: codexTurnState == nil ? nil : preparedRequest.codexTurnScope
            )
        )
    } onCancel: {
        session.invalidateAndCancel()
    }
}

#endif
