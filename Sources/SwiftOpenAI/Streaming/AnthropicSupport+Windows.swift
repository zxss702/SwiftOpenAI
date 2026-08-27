import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if os(Windows)

nonisolated func executeAnthropicStreamWithURLSession(
    preparedRequest: PreparedAnthropicRequest,
    action: @escaping @Sendable (OpenAIChatStreamResult) async throws -> Void
) async throws -> OpenAIChatResult {
    try await withCheckedThrowingContinuation { continuation in
        let delegate = AnthropicStreamDelegate(
            action: action,
            completion: continuation,
            metadata: preparedRequest.metadata,
            fileBindings: preparedRequest.fileBindings
        )
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: preparedRequest.urlRequest)
        task.resume()
    }
}

private final class AnthropicStreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let action: @Sendable (OpenAIChatStreamResult) async throws -> Void
    private let completion: CheckedContinuation<OpenAIChatResult, Error>
    private let lock = NSLock()
    private let fileBindings: [String: FileBinding]

    private(set) var actorHelper = OpenAISendMessageValueHelper()
    private(set) var state = AnthropicStreamState()
    private(set) var metadata: ChatResponseMetadata
    private(set) var statusCode: Int = 0
    private var receivedResponse = false
    private var responseBody = Data()
    private var lastSendTime = Date().timeIntervalSince1970
    private var isFinished = false

    init(
        action: @escaping @Sendable (OpenAIChatStreamResult) async throws -> Void,
        completion: CheckedContinuation<OpenAIChatResult, Error>,
        metadata: ChatResponseMetadata,
        fileBindings: [String: FileBinding]
    ) {
        self.action = action
        self.completion = completion
        self.metadata = metadata
        self.fileBindings = fileBindings
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let httpResponse = response as? HTTPURLResponse {
            receivedResponse = true
            statusCode = httpResponse.statusCode
            metadata = ChatResponseMetadata(
                providerName: metadata.providerName,
                requestID: ProviderResponseNormalizer.requestID(from: httpResponse),
                resolvedModel: metadata.resolvedModel,
                resolvedBasePath: metadata.resolvedBasePath
            )
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard receivedResponse else { return }

        if !(200...299).contains(statusCode) {
            responseBody.append(data)
            return
        }

        Task {
            do {
                try await processAnthropicSSEBytes(
                    data,
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
            } catch {
                dataTask.cancel()
                session.invalidateAndCancel()
                finish(with: .failure(error))
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(with: .failure(error))
            return
        }

        if !(200...299).contains(statusCode) {
            let text = String(data: responseBody, encoding: .utf8) ?? "无法解析响应内容（非UTF-8）"
            finish(with: .failure(mapDeepSeekBodyLimitError(message: text, code: statusCode)))
            return
        }

        Task {
            do {
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

                let result = await OpenAIChatResult(
                    fullThinkingText: actorHelper.fullThinkingText,
                    fullText: actorHelper.fullText,
                    allToolCalls: actorHelper.allToolCalls,
                    usage: state.usage,
                    providerName: metadata.providerName,
                    requestID: metadata.requestID,
                    resolvedModel: metadata.resolvedModel,
                    resolvedBasePath: metadata.resolvedBasePath,
                    contentBlocks: mergeContentBlocksForResult(
                        anthropic: actorHelper.anthropicContentBlocks.isEmpty
                            ? nil
                            : actorHelper.anthropicContentBlocks,
                        fileBindings: fileBindings
                    )
                )
                session.finishTasksAndInvalidate()
                finish(with: .success(result))
            } catch {
                session.invalidateAndCancel()
                finish(with: .failure(error))
            }
        }
    }

    private func finish(with result: Result<OpenAIChatResult, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else { return }
        isFinished = true
        completion.resume(with: result)
    }
}

#endif
