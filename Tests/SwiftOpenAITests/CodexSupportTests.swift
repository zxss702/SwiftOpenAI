import XCTest
@testable import SwiftOpenAI

final class CodexSupportTests: XCTestCase {

    func testCodexRequestOmitsInstructionsAndUsesChatGPTHeaders() throws {
        let codexInfo = AIModelInfoValue.CodexInfo(
            accessToken: "access-token",
            accountID: "account-id"
        )
        let prepared = try makeResponsesURLRequest(
            config: ResponsesRequestConfig(
                modelID: codexInfo.modelID,
                baseURL: try APIBaseURL.parse(codexInfo.baseURL),
                resolvedBasePath: APIBaseURL.configuredPath(of: codexInfo.baseURL),
                providerName: "openai-codex",
                defaultHeaders: codexInfo.defaultHeaders
            ),
            messages: [.user("hello")],
            frequencyPenalty: nil,
            maxCompletionTokens: nil,
            parallelToolCalls: nil,
            presencePenalty: nil,
            responseFormat: nil,
            stop: nil,
            temperature: nil,
            toolChoice: nil,
            tools: nil,
            topP: nil,
            thinkLevel: nil,
            extraBody: nil,
            extraHeaders: nil
        )

        XCTAssertEqual(
            prepared.urlRequest.url?.absoluteString,
            "https://chatgpt.com/backend-api/codex/responses"
        )
        XCTAssertEqual(prepared.urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(prepared.urlRequest.value(forHTTPHeaderField: "ChatGPT-Account-ID"), "account-id")

        let body = try TestFixtures.requestBody(from: prepared.urlRequest)
        XCTAssertNil(body["instructions"])
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertEqual(body["stream"] as? Bool, true)
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 1)
        XCTAssertEqual(input[0]["role"] as? String, "user")
    }

    func testMakeCodexResponsesRequestBodyPutsHistoryInInput() throws {
        let body = try makeCodexResponsesRequestBody(
            modelInfo: .init(accessToken: "t", accountID: "a", modelID: "gpt-5.4"),
            messages: [
                .system("codex system"),
                .user("hi")
            ],
            frequencyPenalty: nil,
            maxCompletionTokens: nil,
            parallelToolCalls: nil,
            presencePenalty: nil,
            responseFormat: nil,
            stop: nil,
            temperature: nil,
            toolChoice: nil,
            tools: nil,
            topP: nil,
            thinkLevel: nil,
            extraBody: nil
        )
        XCTAssertNil(body["instructions"])
        XCTAssertEqual(body["model"] as? String, "gpt-5.4")
        XCTAssertEqual(body["store"] as? Bool, false)
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 2)
        XCTAssertEqual(input[0]["role"] as? String, "system")
        XCTAssertEqual(input[1]["role"] as? String, "user")
    }
}
