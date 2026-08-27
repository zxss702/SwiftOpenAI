import XCTest
@testable import SwiftOpenAI

final class ResponsesEncodingTests: XCTestCase {

    func testAppendResponsesPathDoesNotDuplicate() throws {
        let base = try XCTUnwrap(URL(string: "https://api.openai.com/v1"))
        XCTAssertEqual(appendResponsesPath(to: base).absoluteString, "https://api.openai.com/v1/responses")

        let already = try XCTUnwrap(URL(string: "https://api.openai.com/v1/responses"))
        XCTAssertEqual(appendResponsesPath(to: already).absoluteString, "https://api.openai.com/v1/responses")

        let root = try XCTUnwrap(URL(string: "https://api.deepseek.com"))
        XCTAssertEqual(appendResponsesPath(to: root).absoluteString, "https://api.deepseek.com/v1/responses")
    }

    func testGenericResponsesOmitsInstructionsAndUsesBearer() throws {
        let prepared = try makeResponsesURLRequest(
            config: ResponsesRequestConfig(
                modelID: "gpt-5",
                baseURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1")),
                resolvedBasePath: "/v1",
                providerName: "openai-responses",
                defaultHeaders: ["Authorization": "Bearer api-key"]
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
        XCTAssertEqual(body["store"] as? Bool, false)
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
            extraBody: ["metadata": .object(["source": .string("unit-test")])]
        )

        XCTAssertNil(body["instructions"])
        XCTAssertEqual(body["max_output_tokens"] as? Int, 512)
        XCTAssertEqual(body["tool_choice"] as? String, "required")
        XCTAssertEqual((body["reasoning"] as? [String: Any])?["effort"] as? String, "high")
        XCTAssertEqual((body["metadata"] as? [String: Any])?["source"] as? String, "unit-test")

        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.first?["name"] as? String, "lookup_weather")

        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 5)
        XCTAssertEqual(input[0]["role"] as? String, "system")
        XCTAssertEqual(Self.inputText(of: input[0]), "system prompt")
        XCTAssertEqual(input[1]["role"] as? String, "user")
        XCTAssertEqual(input[3]["type"] as? String, "function_call")
        XCTAssertEqual(input[4]["type"] as? String, "function_call_output")
    }

    func testInterleavedSystemReminderStayInInputInOrder() throws {
        let body = try makeResponsesRequestBody(
            modelID: "gpt-5.4",
            messages: [
                .system("sys-1"),
                .user("hello"),
                .reminder("rem-1"),
                .system("sys-2")
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
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 4)
        XCTAssertEqual(input[0]["role"] as? String, "system")
        XCTAssertEqual(Self.inputText(of: input[0]), "sys-1")
        XCTAssertEqual(input[1]["role"] as? String, "user")
        XCTAssertEqual(Self.inputText(of: input[1]), "hello")
        XCTAssertEqual(input[2]["role"] as? String, "system")
        XCTAssertEqual(Self.inputText(of: input[2]), "rem-1")
        XCTAssertEqual(input[3]["role"] as? String, "system")
        XCTAssertEqual(Self.inputText(of: input[3]), "sys-2")
    }

    func testSystemAndReminderOnlyProducesNonEmptyInput() throws {
        let body = try makeResponsesRequestBody(
            modelID: "gpt-5.4",
            messages: [
                .system("agent init"),
                .reminder("<system_hello_summary>join briefing</system_hello_summary>")
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
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 2)
        XCTAssertFalse(input.isEmpty)
        XCTAssertEqual(Self.inputText(of: input[0]), "agent init")
        XCTAssertEqual(
            Self.inputText(of: input[1]),
            "<system_hello_summary>join briefing</system_hello_summary>"
        )
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
            extraBody: nil
        )
        XCTAssertNil(body["instructions"])
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 3)
        XCTAssertEqual(input[0]["role"] as? String, "system")
        XCTAssertEqual(input[1]["role"] as? String, "user")
        XCTAssertEqual(input[2]["role"] as? String, "user")
    }

    private static func inputText(of item: [String: Any]) -> String? {
        let content = item["content"] as? [[String: Any]]
        return content?.first?["text"] as? String
    }
}
