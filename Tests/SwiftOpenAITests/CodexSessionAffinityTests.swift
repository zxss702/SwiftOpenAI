import XCTest
@testable import SwiftOpenAI

final class CodexSessionAffinityTests: XCTestCase {
    func testSIWCGeneratesSessionIDForNewHistory() throws {
        let first = try prepare()
        let second = try prepare()
        let sessionID = try XCTUnwrap(first.codexSessionID)
        XCTAssertNotNil(UUID(uuidString: sessionID))
        XCTAssertNotEqual(sessionID, second.codexSessionID)
        XCTAssertNil(first.urlRequest.value(forHTTPHeaderField: "x-codex-turn-state"))
        XCTAssertNil(first.urlRequest.value(forHTTPHeaderField: "ChatGPT-Account-ID"))
        XCTAssertEqual(first.urlRequest.url?.absoluteString, "https://api.openai.com/v1/responses")
    }

    func testSIWCReusesLatestSessionIDAndHonorsExplicitOverride() throws {
        let messages: [OpenAIMessage] = [
            .assistant("older", contentBlocks: .init(codexSessionID: "old-session")),
            .assistant("latest", contentBlocks: .init(codexSessionID: "saved-session")),
            .user("continue")
        ]
        XCTAssertEqual(try prepare(messages: messages).codexSessionID, "saved-session")
        XCTAssertEqual(
            try prepare(messages: messages, headers: ["Session-ID": "explicit-session"]).codexSessionID,
            "explicit-session"
        )
        let ordinaryResponses = try prepare(messages: messages, provider: "openai")
        XCTAssertNil(ordinaryResponses.urlRequest.value(forHTTPHeaderField: "session-id"))
        XCTAssertNil(ordinaryResponses.codexSessionID)
    }

    private func prepare(
        messages: [OpenAIMessage] = [.system("rules"), .user("hello")],
        headers: [String: String]? = nil,
        provider: String = "openai-codex"
    ) throws -> PreparedResponsesRequest {
        let info = AIModelInfoValue.CodexInfo(accessToken: "token")
        return try makeResponsesURLRequest(
            config: .init(modelID: info.modelID, baseURL: XCTUnwrap(info.resolvedURL),
                resolvedBasePath: "/v1", providerName: provider, defaultHeaders: info.defaultHeaders),
            messages: messages, frequencyPenalty: nil,
            maxCompletionTokens: nil, parallelToolCalls: nil, presencePenalty: nil, responseFormat: nil,
            stop: nil, temperature: nil, toolChoice: nil, tools: nil, topP: nil, thinkLevel: nil,
            extraBody: nil, extraHeaders: headers)
    }
}
