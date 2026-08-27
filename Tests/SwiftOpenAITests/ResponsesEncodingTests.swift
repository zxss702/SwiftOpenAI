import XCTest
@testable import SwiftOpenAI

final class ResponsesEncodingTests: XCTestCase {

    func testAppendResponsesPathDoesNotDuplicate() throws {
        let base = try XCTUnwrap(URL(string: "https://api.openai.com/v1"))
        XCTAssertEqual(appendResponsesPath(to: base).absoluteString, "https://api.openai.com/v1/responses")

        let already = try XCTUnwrap(URL(string: "https://api.openai.com/v1/responses"))
        XCTAssertEqual(appendResponsesPath(to: already).absoluteString, "https://api.openai.com/v1/responses")
    }

    func testGenericResponsesOmitsDefaultInstructionsAndUsesBearer() throws {
        let prepared = try makeResponsesURLRequest(
            config: ResponsesRequestConfig(
                modelID: "gpt-5",
                baseURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1")),
                resolvedBasePath: "/v1",
                providerName: "openai-responses",
                defaultHeaders: ["Authorization": "Bearer api-key"],
                requireDefaultInstructions: false
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

        XCTAssertEqual(prepared.urlRequest.url?.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(prepared.urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer api-key")
        let body = try TestFixtures.requestBody(from: prepared.urlRequest)
        XCTAssertNil(body["instructions"])
        XCTAssertEqual(body["stream"] as? Bool, true)
    }

    func testRequestBodyMapsMessagesToolsReasoningAndText() throws {
        let tool = ChatQuery.ChatCompletionToolParam(
            type: "function",
            function: .init(
                name: "lookup_weather",
                description: "Look up the weather",
                parameters: [
                    "type": .string("object"),
                    "properties": .object([
                        "city": .object(["type": .string("string")])
                    ])
                ]
            )
        )

        let body = try makeResponsesRequestBody(
            modelID: "gpt-5.4",
            messages: [
                .system("system prompt"),
                .user("show me", images: [TestFixtures.tinyPNG], detail: .high),
                .assistant(
                    "calling tool",
                    toolCalls: [
                        .init(id: "call_123", function: .init(name: "lookup_weather", arguments: #"{"city":"Shanghai"}"#))
                    ]
                ),
                .tool("tool result", images: [TestFixtures.tinyPNG], detail: .low, toolCallId: "call_123")
            ],
            frequencyPenalty: 0.2,
            maxCompletionTokens: 512,
            parallelToolCalls: nil,
            presencePenalty: 0.3,
            responseFormat: .init(
                type: "json_schema",
                jsonSchema: .init(
                    name: "weather_response",
                    schema: #"{"type":"object","properties":{"summary":{"type":"string"}}}"#
                )
            ),
            stop: .array(["END"]),
            temperature: 0.6,
            toolChoice: .required,
            tools: [tool],
            topP: 0.9,
            thinkLevel: .high,
            extraBody: ["metadata": .object(["source": .string("unit-test")])],
            requireDefaultInstructions: true
        )

        XCTAssertEqual(body["instructions"] as? String, "system prompt")
        XCTAssertEqual(body["max_output_tokens"] as? Int, 512)
        XCTAssertEqual(body["tool_choice"] as? String, "required")
        XCTAssertEqual((body["reasoning"] as? [String: Any])?["effort"] as? String, "high")
        XCTAssertEqual((body["metadata"] as? [String: Any])?["source"] as? String, "unit-test")

        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.first?["name"] as? String, "lookup_weather")

        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 4)
        XCTAssertEqual(input[2]["type"] as? String, "function_call")
        XCTAssertEqual(input[3]["type"] as? String, "function_call_output")
    }

    func testAssistantReasoningHistoryIsOmittedFromInput() throws {
        let body = try makeResponsesRequestBody(
            modelID: "gpt-5.4",
            messages: [
                .system("system prompt"),
                .user("你好"),
                .assistant("", reasoningContent: "internal reasoning that should not be replayed"),
                .user("你是谁？")
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
            thinkLevel: .medium,
            extraBody: nil,
            requireDefaultInstructions: true
        )
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 2)
        XCTAssertEqual(input[0]["role"] as? String, "user")
        XCTAssertEqual(input[1]["role"] as? String, "user")
    }
}
