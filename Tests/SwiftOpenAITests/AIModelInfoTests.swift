import XCTest
@testable import SwiftOpenAI

final class AIModelInfoTests: XCTestCase {

    func testCompletionsDefaults() {
        let info = AIModelInfoValue(token: "sk-test", modelID: "gpt-4")
        XCTAssertEqual(info.wireAPI, .completions)
        XCTAssertEqual(info.token, "sk-test")
        XCTAssertEqual(info.modelID, "gpt-4")
        XCTAssertEqual(info.host, "api.openai.com")
        XCTAssertEqual(info.resolvedBasePath, "/v1")
        XCTAssertEqual(info.baseURL?.absoluteString, "https://api.openai.com/v1")
        XCTAssertNotNil(info.completionsInfo)
        XCTAssertNil(info.responsesInfo)
        XCTAssertFalse(info.isResponses)
        XCTAssertFalse(info.isCodex)
    }

    func testResponsesInfoExposesBearerAndBaseURL() {
        let info = AIModelInfoValue.responses(
            .init(token: "api-key", modelID: "gpt-5")
        )
        XCTAssertTrue(info.isResponses)
        XCTAssertEqual(info.wireAPI, .responses)
        XCTAssertEqual(info.token, "api-key")
        XCTAssertEqual(info.resolvedBasePath, "/v1")
        XCTAssertEqual(info.baseURL?.absoluteString, "https://api.openai.com/v1")
        XCTAssertEqual(info.responsesInfo?.defaultHeaders["Authorization"], "Bearer api-key")
    }

    func testCodexInfoExposesChatGPTHeaders() {
        let info = AIModelInfoValue.codex(
            .init(
                accessToken: "access-token",
                accountID: "account-id",
                modelID: "gpt-5.4",
                isFedRAMPAccount: true
            )
        )
        XCTAssertTrue(info.isCodex)
        XCTAssertEqual(info.wireAPI, .codexResponses)
        XCTAssertEqual(info.token, "access-token")
        XCTAssertEqual(info.host, "chatgpt.com")
        XCTAssertEqual(info.resolvedBasePath, "/backend-api/codex")
        XCTAssertEqual(info.baseURL?.absoluteString, "https://chatgpt.com/backend-api/codex")
        XCTAssertEqual(info.codexInfo?.defaultHeaders["Authorization"], "Bearer access-token")
        XCTAssertEqual(info.codexInfo?.defaultHeaders["ChatGPT-Account-ID"], "account-id")
        XCTAssertEqual(info.codexInfo?.defaultHeaders["X-OpenAI-Fedramp"], "true")
    }

    func testThinkLevelEnablesReasoning() {
        XCTAssertFalse(ThinkLevel.none.enablesReasoning)
        XCTAssertTrue(ThinkLevel.high.enablesReasoning)
        XCTAssertTrue(ThinkLevel.max.enablesReasoning)
    }
}
