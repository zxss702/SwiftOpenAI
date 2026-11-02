import XCTest
@testable import SwiftOpenAI

final class CodexSessionAffinityTests: XCTestCase {
    func testCodexDoesNotEmitBackendRoutingHeaders() throws {
        let info = AIModelInfoValue.CodexInfo(accessToken: "token")
        let prepared = try makeResponsesURLRequest(
            config: .init(modelID: info.modelID, baseURL: XCTUnwrap(info.resolvedURL),
                resolvedBasePath: "/v1", providerName: "openai-codex", defaultHeaders: info.defaultHeaders),
            messages: [.system("rules"), .user("hello")], frequencyPenalty: nil,
            maxCompletionTokens: nil, parallelToolCalls: nil, presencePenalty: nil, responseFormat: nil,
            stop: nil, temperature: nil, toolChoice: nil, tools: nil, topP: nil, thinkLevel: nil,
            extraBody: nil, extraHeaders: nil)
        XCTAssertNil(prepared.urlRequest.value(forHTTPHeaderField: "session-id"))
        XCTAssertNil(prepared.urlRequest.value(forHTTPHeaderField: "x-codex-turn-state"))
        XCTAssertNil(prepared.urlRequest.value(forHTTPHeaderField: "ChatGPT-Account-ID"))
        XCTAssertEqual(prepared.urlRequest.url?.absoluteString, "https://api.openai.com/v1/responses")
    }
}
