import XCTest
@testable import SwiftOpenAI

final class CodexSupportTests: XCTestCase {

    func testCodexRequestInjectsDefaultInstructionsAndChatGPTHeaders() throws {
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
                defaultHeaders: codexInfo.defaultHeaders,
                requireDefaultInstructions: true
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
        XCTAssertEqual(body["instructions"] as? String, "You are a helpful assistant.")
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertEqual(body["stream"] as? Bool, true)
    }

    func testMakeCodexResponsesRequestBodyRequiresDefaultInstructions() throws {
        let body = try makeCodexResponsesRequestBody(
            modelInfo: .init(accessToken: "t", accountID: "a", modelID: "gpt-5.4"),
            messages: [.user("hi")],
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
        XCTAssertEqual(body["instructions"] as? String, "You are a helpful assistant.")
        XCTAssertEqual(body["model"] as? String, "gpt-5.4")
        XCTAssertEqual(body["store"] as? Bool, false)
    }
}
