import XCTest
@testable import SwiftOpenAI

final class AIModelInfoTests: XCTestCase {

    func testCompletionsDefaults() {
        let info = AIModelInfoValue(token: "sk-test", modelID: "gpt-4")
        XCTAssertEqual(info.wireAPI, .completions)
        XCTAssertEqual(info.token, "sk-test")
        XCTAssertEqual(info.modelID, "gpt-4")
        XCTAssertEqual(info.baseURL, "https://api.openai.com/v1")
        XCTAssertEqual(info.configuredPath, "/v1")
        XCTAssertEqual(info.resolvedURL?.absoluteString, "https://api.openai.com/v1")
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
        XCTAssertEqual(info.baseURL, "https://api.openai.com/v1")
        XCTAssertEqual(info.configuredPath, "/v1")
        XCTAssertEqual(info.responsesInfo?.defaultHeaders["Authorization"], "Bearer api-key")
    }

    func testCodexInfoUsesSIWCBearerAndPublicAPI() {
        let info = AIModelInfoValue.codex(
            .init(
                accessToken: "access-token",
                modelID: "gpt-5.4"
            )
        )
        XCTAssertTrue(info.isCodex)
        XCTAssertEqual(info.wireAPI, .codexResponses)
        XCTAssertEqual(info.token, "access-token")
        XCTAssertEqual(info.baseURL, "https://api.openai.com/v1")
        XCTAssertEqual(info.configuredPath, "/v1")
        XCTAssertEqual(info.codexInfo?.defaultHeaders["Authorization"], "Bearer access-token")
        XCTAssertNil(info.codexInfo?.defaultHeaders["ChatGPT-Account-ID"])
        XCTAssertNil(info.codexInfo?.defaultHeaders["X-OpenAI-Fedramp"])
    }

    func testAnthropicInfoExposesKeyHeadersAndBaseURL() {
        let info = AIModelInfoValue.anthropic(
            .init(token: "anth-key", modelID: "claude-sonnet-4-5")
        )
        XCTAssertTrue(info.isAnthropic)
        XCTAssertEqual(info.wireAPI, .anthropic)
        XCTAssertEqual(info.token, "anth-key")
        XCTAssertEqual(info.baseURL, "https://api.anthropic.com")
        XCTAssertEqual(info.configuredPath, "")
        XCTAssertEqual(info.anthropicInfo?.defaultHeaders["x-api-key"], "anth-key")
        XCTAssertEqual(info.anthropicInfo?.defaultHeaders["anthropic-version"], "2023-06-01")
        XCTAssertNil(info.completionsInfo)
        XCTAssertNil(info.responsesInfo)
        XCTAssertFalse(info.isResponses)
        XCTAssertFalse(info.isCodex)
    }

    func testThinkLevelEnablesReasoning() {
        XCTAssertFalse(ThinkLevel.none.enablesReasoning)
        XCTAssertTrue(ThinkLevel.high.enablesReasoning)
        XCTAssertTrue(ThinkLevel.max.enablesReasoning)
    }
}
