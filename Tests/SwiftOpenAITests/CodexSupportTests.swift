import XCTest
@testable import SwiftOpenAI

final class CodexSupportTests: XCTestCase {

    func testCodexRequestRetainsUserAndReadToolImages() throws {
        for model in [AIModelInfoValue.CodexInfo(accessToken: "t").modelID, "gpt-6.1-terra", "terra", "gpt-6.1-sol", "gpt-6-astra"] {
            let info = AIModelInfoValue.CodexInfo(accessToken: "t", modelID: model)
            let prepared = try makeResponsesURLRequest(
                config: ResponsesRequestConfig(
                    modelID: info.modelID,
                    baseURL: try APIBaseURL.parse(info.baseURL),
                    resolvedBasePath: APIBaseURL.configuredPath(of: info.baseURL),
                    providerName: "openai-codex",
                    defaultHeaders: info.defaultHeaders
                ),
                messages: [
                    .user("inspect", images: [TestFixtures.tinyPNG], detail: .high),
                    .assistant("", toolCalls: [
                        .init(id: "call_read", function: .init(name: "read", arguments: "{}"))
                    ]),
                    .tool("page 1", images: [TestFixtures.tinyPNG], detail: .low, toolCallId: "call_read")
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
                extraBody: nil,
                extraHeaders: nil
            )
            let body = try TestFixtures.requestBody(from: prepared.urlRequest)
            let input = try XCTUnwrap(body["input"] as? [[String: Any]])
            XCTAssertEqual(input.count, 3)
            let userContent = try XCTUnwrap(input[0]["content"] as? [[String: Any]])
            XCTAssertEqual(input[2]["type"] as? String, "function_call_output")
            XCTAssertEqual(input[2]["call_id"] as? String, "call_read")
            let toolContent = try XCTUnwrap(input[2]["output"] as? [[String: Any]])
            let expectedURL = "data:image/png;base64,\(TestFixtures.tinyPNG.base64EncodedString())"
            for (parts, text, detail) in [(userContent, "inspect", "high"), (toolContent, "page 1", "low")] {
                XCTAssertEqual(parts.count, 2)
                let textPart = try XCTUnwrap(parts.first { $0["type"] as? String == "input_text" })
                let imagePart = try XCTUnwrap(parts.first { $0["type"] as? String == "input_image" })
                XCTAssertEqual(textPart["text"] as? String, text)
                XCTAssertEqual(imagePart["image_url"] as? String, expectedURL, model)
                XCTAssertEqual(imagePart["detail"] as? String, detail)
            }
        }
    }

    func testCodexRequestUsesPublicResponsesAndBearerOnly() throws {
        let codexInfo = AIModelInfoValue.CodexInfo(
            accessToken: "access-token"
        )
        let prepared = try makeResponsesURLRequest(
            config: ResponsesRequestConfig(
                modelID: codexInfo.modelID,
                baseURL: try APIBaseURL.parse(codexInfo.baseURL),
                resolvedBasePath: APIBaseURL.configuredPath(of: codexInfo.baseURL),
                providerName: "openai-codex",
                defaultHeaders: codexInfo.defaultHeaders
            ),
            messages: [
                .system("codex system"),
                .user("hello"),
                .reminder("codex reminder"),
                .assistant("reply"),
                .system("updated system")
            ],
            frequencyPenalty: nil,
            maxCompletionTokens: 512,
            parallelToolCalls: nil,
            presencePenalty: nil,
            responseFormat: nil,
            stop: nil,
            temperature: 0.6,
            toolChoice: nil,
            tools: nil,
            topP: 0.9,
            thinkLevel: nil,
            extraBody: nil,
            extraHeaders: nil
        )

        XCTAssertEqual(
            prepared.urlRequest.url?.absoluteString,
            "https://api.openai.com/v1/responses"
        )
        XCTAssertEqual(prepared.urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertNil(prepared.urlRequest.value(forHTTPHeaderField: "ChatGPT-Account-ID"))

        let body = try TestFixtures.requestBody(from: prepared.urlRequest)
        XCTAssertNil(body["instructions"])
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["include"] as? [String], ["reasoning.encrypted_content"])
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 5)
        XCTAssertEqual(input.compactMap { $0["role"] as? String }, [
            "developer", "user", "developer", "assistant", "developer"
        ])
        XCTAssertEqual(input.compactMap(Self.inputText), [
            "codex system", "hello", "codex reminder", "reply", "updated system"
        ])
        XCTAssertNil(body["temperature"])
        XCTAssertNil(body["top_p"])
        XCTAssertNil(body["max_output_tokens"])
    }

    func testCodexSystemAndReminderOnlyStayInInputAsDeveloperMessages() throws {
        let body = try makeCodexResponsesRequestBody(
            modelInfo: .init(accessToken: "t", modelID: "gpt-5.4"),
            messages: [
                .system("codex system"),
                .reminder("codex reminder")
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
        XCTAssertEqual(input.compactMap { $0["role"] as? String }, ["developer", "developer"])
        XCTAssertEqual(input.compactMap(Self.inputText), ["codex system", "codex reminder"])
    }

    func testUnsupportedParametersFromExtraBodyAreOmittedOnlyForCodex() throws {
        for wireAPI in [AIModelWireAPI.responses, .codexResponses] {
            let body = try makeResponsesRequestBody(
                modelID: "gpt-5.4",
                messages: [.user("hello")],
                frequencyPenalty: nil,
                maxCompletionTokens: 512,
                parallelToolCalls: nil,
                presencePenalty: nil,
                responseFormat: nil,
                stop: nil,
                temperature: 0.6,
                toolChoice: nil,
                tools: nil,
                topP: 0.9,
                thinkLevel: nil,
                extraBody: [
                    "temperature": .double(0.4),
                    "top_p": .double(0.8),
                    "max_output_tokens": .int(1024),
                    "parallel_tool_calls": .bool(true)
                ],
                wireAPI: wireAPI
            )

            if wireAPI == .codexResponses {
                XCTAssertNil(body["temperature"])
                XCTAssertNil(body["top_p"])
                XCTAssertNil(body["max_output_tokens"])
            } else {
                XCTAssertEqual(body["temperature"] as? Double, 0.4)
                XCTAssertEqual(body["top_p"] as? Double, 0.8)
                XCTAssertEqual(body["max_output_tokens"] as? Int, 1024)
            }
            XCTAssertEqual(body["parallel_tool_calls"] as? Bool, true)
        }
    }

    private static func inputText(of item: [String: Any]) -> String? {
        let content = item["content"] as? [[String: Any]]
        return content?.first?["text"] as? String
    }
}
