import XCTest
@testable import SwiftOpenAI

final class CodexSessionAffinityTests: XCTestCase {
    func testSessionIDSurvivesPersistenceAndApprovalToolContinuation() throws {
        let initial: [OpenAIMessage] = [.system("stable instructions"), .user("<user to='you, '>\n你好\n</user>")]
        let first = try prepare(messages: initial)
        let sessionID = try XCTUnwrap(first.urlRequest.value(forHTTPHeaderField: "session-id"))
        XCTAssertNotNil(UUID(uuidString: sessionID))

        // Even a response with no text or reasoning carries the routing identity.
        let blocks = try XCTUnwrap(mergeContentBlocksForResult(
            anthropic: nil, fileBindings: [:], codexSessionID: sessionID
        ))
        let reply = OpenAIMessage.assistant("", toolCalls: [
            .init(id: "call_75571cd2cd1345cca8b8f2f366735c57", function: .init(
                name: "message_user", arguments: #"{"content":"你好，有什么需要我们帮忙的？","name":"问候"}"#
            ))
        ], contentBlocks: blocks)
        let persisted = try JSONEncoder().encode(reply)
        let restored = try JSONDecoder().decode(OpenAIMessage.self, from: persisted)
        let next = try prepare(messages: initial + [
            restored,
            .tool("已提交", toolCallId: "call_75571cd2cd1345cca8b8f2f366735c57"),
            .reminder("<system_dispatch> `问候` 已批准 </system_dispatch>")
        ])
        XCTAssertEqual(next.urlRequest.value(forHTTPHeaderField: "session-id"), sessionID)
        let firstBody = try TestFixtures.requestBody(from: first.urlRequest)
        let nextBody = try TestFixtures.requestBody(from: next.urlRequest)
        let firstInput = try XCTUnwrap(firstBody["input"] as? [[String: Any]])
        let nextInput = try XCTUnwrap(nextBody["input"] as? [[String: Any]])
        XCTAssertEqual(
            try JSONSerialization.data(withJSONObject: firstInput, options: [.sortedKeys]),
            try JSONSerialization.data(withJSONObject: Array(nextInput.prefix(firstInput.count)), options: [.sortedKeys])
        )
        XCTAssertNil(nextBody["prompt_cache_key"])
        XCTAssertNil(nextBody["session-id"])
        XCTAssertNil(nextBody["session_id"])
        let merged = blocks.merging(MessageContentBlocks(fileBindings: ["image": FileBinding(fileId: "file-1")]))
        XCTAssertEqual(merged.codexSessionID, sessionID)
    }

    func testIndependentConversationsAndExplicitHeaderOverride() throws {
        let initial: [OpenAIMessage] = [.user("hello")]
        let first = try prepare(messages: initial)
        let second = try prepare(messages: initial)
        XCTAssertNotEqual(
            first.urlRequest.value(forHTTPHeaderField: "session-id"),
            second.urlRequest.value(forHTTPHeaderField: "session-id")
        )
        let overridden = try prepare(messages: [
            .assistant("old", contentBlocks: MessageContentBlocks(codexSessionID: "old-session")), .user("continue")
        ], headers: ["Session-ID": "caller-session"])
        XCTAssertEqual(overridden.urlRequest.value(forHTTPHeaderField: "session-id"), "caller-session")
    }

    func testOrdinaryResponsesDoesNotAdoptCodexRoutingIdentity() throws {
        let prepared = try prepare(messages: [
            .assistant("history", contentBlocks: MessageContentBlocks(codexSessionID: "codex-session")), .user("continue")
        ], providerName: "openai-responses")
        XCTAssertNil(prepared.urlRequest.value(forHTTPHeaderField: "session-id"))
    }

    private func prepare(
        messages: [OpenAIMessage], headers: [String: String]? = nil, providerName: String = "openai-codex"
    ) throws -> PreparedResponsesRequest {
        let baseURL = providerName == "openai-codex" ? "https://chatgpt.com/backend-api/codex" : "https://api.openai.com/v1"
        return try makeResponsesURLRequest(
            config: ResponsesRequestConfig(
                modelID: "gpt-6.1-sol", baseURL: try APIBaseURL.parse(baseURL),
                resolvedBasePath: APIBaseURL.configuredPath(of: baseURL), providerName: providerName,
                defaultHeaders: ["Authorization": "Bearer test-token", "ChatGPT-Account-ID": "test-account"]
            ),
            messages: messages, frequencyPenalty: nil, maxCompletionTokens: nil, parallelToolCalls: true,
            presencePenalty: nil, responseFormat: nil, stop: nil, temperature: nil, toolChoice: nil,
            tools: nil, topP: nil, thinkLevel: ThinkLevel.none, extraBody: nil, extraHeaders: headers
        )
    }
}
