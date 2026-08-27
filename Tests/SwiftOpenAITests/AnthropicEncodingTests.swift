import XCTest
@testable import SwiftOpenAI

final class AnthropicEncodingTests: XCTestCase {

    func testAppendMessagesPathDoesNotDuplicate() throws {
        let root = try XCTUnwrap(URL(string: "https://api.anthropic.com"))
        XCTAssertEqual(appendMessagesPath(to: root).absoluteString, "https://api.anthropic.com/v1/messages")

        let base = try XCTUnwrap(URL(string: "https://api.anthropic.com/v1"))
        XCTAssertEqual(appendMessagesPath(to: base).absoluteString, "https://api.anthropic.com/v1/messages")

        let already = try XCTUnwrap(URL(string: "https://api.anthropic.com/v1/messages"))
        XCTAssertEqual(appendMessagesPath(to: already).absoluteString, "https://api.anthropic.com/v1/messages")

        let deepseek = try XCTUnwrap(URL(string: "https://api.deepseek.com/anthropic"))
        XCTAssertEqual(
            appendMessagesPath(to: deepseek).absoluteString,
            "https://api.deepseek.com/anthropic/v1/messages"
        )
    }

    func testURLRequestUsesAnthropicHeadersAndPath() throws {
        let prepared = try makeAnthropicURLRequest(
            modelInfo: .init(token: "anth-key", modelID: "claude-sonnet-4-5"),
            messages: [.user("hello")],
            maxCompletionTokens: nil,
            parallelToolCalls: nil,
            stop: nil,
            temperature: nil,
            toolChoice: nil,
            tools: nil,
            topP: nil,
            thinkLevel: nil,
            extraBody: nil,
            extraHeaders: nil
        )

        XCTAssertEqual(prepared.urlRequest.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(prepared.urlRequest.value(forHTTPHeaderField: "x-api-key"), "anth-key")
        XCTAssertEqual(prepared.urlRequest.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(prepared.metadata.providerName, "anthropic")

        let body = try TestFixtures.requestBody(from: prepared.urlRequest)
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["max_tokens"] as? Int, 4096)
        XCTAssertNil(body["system"])
    }

    func testSystemAndReminderFoldIntoSystem() throws {
        let body = try makeAnthropicRequestBody(
            modelID: "claude-sonnet-4-5",
            messages: [
                .system("sys"),
                .reminder("note"),
                .user("hi")
            ],
            maxCompletionTokens: 128,
            parallelToolCalls: nil,
            stop: nil,
            temperature: 0.5,
            toolChoice: nil,
            tools: nil,
            topP: nil,
            thinkLevel: nil,
            extraBody: nil
        )

        XCTAssertEqual(body["system"] as? String, "sys\n\nnote")
        XCTAssertEqual(body["max_tokens"] as? Int, 128)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "user")
    }

    func testToolsInputSchemaToolResultAndThinking() throws {
        let tool = TestFixtures.weatherTool()
        let body = try makeAnthropicRequestBody(
            modelID: "claude-sonnet-4-5",
            messages: [
                .user("weather?"),
                .assistant(
                    "calling",
                    toolCalls: [
                        .init(id: "toolu_1", function: .init(name: "get_weather", arguments: #"{"city":"Shanghai"}"#))
                    ]
                ),
                .tool("sunny", toolCallId: "toolu_1")
            ],
            maxCompletionTokens: 256,
            parallelToolCalls: false,
            stop: .string("STOP"),
            temperature: nil,
            toolChoice: .required,
            tools: [tool],
            topP: 0.9,
            thinkLevel: .medium,
            extraBody: ["metadata": .object(["source": .string("unit-test")])]
        )

        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.first?["name"] as? String, "get_weather")
        XCTAssertNotNil(tools.first?["input_schema"])

        let toolChoice = try XCTUnwrap(body["tool_choice"] as? [String: Any])
        // thinking enabled: forced tool_choice is coerced to auto
        XCTAssertEqual(toolChoice["type"] as? String, "auto")
        XCTAssertEqual(toolChoice["disable_parallel_tool_use"] as? Bool, true)

        let thinking = try XCTUnwrap(body["thinking"] as? [String: Any])
        XCTAssertEqual(thinking["type"] as? String, "enabled")
        XCTAssertEqual(thinking["budget_tokens"] as? Int, 8192)
        // budget 8192 → max_tokens at least budget + 4096
        XCTAssertEqual(body["max_tokens"] as? Int, 12288)

        XCTAssertEqual(body["stop_sequences"] as? [String], ["STOP"])
        XCTAssertEqual((body["metadata"] as? [String: Any])?["source"] as? String, "unit-test")

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 3)

        let assistantContent = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(assistantContent.last?["type"] as? String, "tool_use")
        XCTAssertEqual(assistantContent.last?["id"] as? String, "toolu_1")
        XCTAssertEqual((assistantContent.last?["input"] as? [String: Any])?["city"] as? String, "Shanghai")

        let toolResult = try XCTUnwrap(messages[2]["content"] as? [[String: Any]])
        XCTAssertEqual(toolResult.first?["type"] as? String, "tool_result")
        XCTAssertEqual(toolResult.first?["tool_use_id"] as? String, "toolu_1")
        XCTAssertEqual(toolResult.first?["content"] as? String, "sunny")
    }

    func testThinkLevelNoneDisablesThinking() throws {
        let body = try makeAnthropicRequestBody(
            modelID: "claude-sonnet-4-5",
            messages: [.user("hi")],
            maxCompletionTokens: nil,
            parallelToolCalls: nil,
            stop: nil,
            temperature: nil,
            toolChoice: nil,
            tools: nil,
            topP: nil,
            thinkLevel: ThinkLevel.none,
            extraBody: nil
        )
        XCTAssertEqual((body["thinking"] as? [String: Any])?["type"] as? String, "disabled")
        XCTAssertEqual(body["max_tokens"] as? Int, 4096)
    }

    func testThinkingRaisesMaxTokensAboveBudget() throws {
        let body = try makeAnthropicRequestBody(
            modelID: "claude-sonnet-4-5",
            messages: [.user("hi")],
            maxCompletionTokens: nil,
            parallelToolCalls: nil,
            stop: nil,
            temperature: nil,
            toolChoice: nil,
            tools: nil,
            topP: nil,
            thinkLevel: .medium,
            extraBody: nil
        )
        let budget = try XCTUnwrap((body["thinking"] as? [String: Any])?["budget_tokens"] as? Int)
        let maxTokens = try XCTUnwrap(body["max_tokens"] as? Int)
        XCTAssertEqual(budget, 8192)
        XCTAssertGreaterThan(maxTokens, budget)
        XCTAssertEqual(maxTokens, budget + 4096)
    }

    func testEchoesAnthropicContentBlocksVerbatim() throws {
        let blocks: [[String: AnyCodableValue]] = [
            [
                "type": .string("thinking"),
                "thinking": .string("plan"),
                "signature": .string("sig_abc")
            ],
            [
                "type": .string("tool_use"),
                "id": .string("toolu_1"),
                "name": .string("get_weather"),
                "input": .object(["city": .string("Paris")])
            ]
        ]
        let body = try makeAnthropicRequestBody(
            modelID: "claude-sonnet-4-5",
            messages: [
                .user("weather?"),
                .assistant(
                    AssistantMessageParam(
                        content: "ignored-when-blocks-present",
                        toolCalls: nil,
                        reasoningContent: "plan",
                        anthropicContentBlocks: blocks
                    )
                ),
                .tool("sunny", toolCallId: "toolu_1")
            ],
            maxCompletionTokens: 2048,
            parallelToolCalls: nil,
            stop: nil,
            temperature: nil,
            toolChoice: nil,
            tools: [TestFixtures.weatherTool()],
            topP: nil,
            thinkLevel: .low,
            extraBody: nil
        )

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let assistantContent = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(assistantContent.first?["type"] as? String, "thinking")
        XCTAssertEqual(assistantContent.first?["signature"] as? String, "sig_abc")
        XCTAssertEqual(assistantContent.last?["type"] as? String, "tool_use")
    }

    func testMergesConsecutiveToolResultsIntoOneUserMessage() throws {
        let body = try makeAnthropicRequestBody(
            modelID: "claude-sonnet-4-5",
            messages: [
                .user("hi"),
                .assistant(
                    "",
                    toolCalls: [
                        .init(id: "t1", function: .init(name: "a", arguments: "{}")),
                        .init(id: "t2", function: .init(name: "b", arguments: "{}"))
                    ]
                ),
                .tool("r1", toolCallId: "t1"),
                .tool("r2", toolCallId: "t2")
            ],
            maxCompletionTokens: 1024,
            parallelToolCalls: nil,
            stop: nil,
            temperature: nil,
            toolChoice: nil,
            tools: nil,
            topP: nil,
            thinkLevel: ThinkLevel.none,
            extraBody: nil
        )
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 3)
        XCTAssertEqual(messages[2]["role"] as? String, "user")
        let content = try XCTUnwrap(messages[2]["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 2)
        XCTAssertEqual(content[0]["tool_use_id"] as? String, "t1")
        XCTAssertEqual(content[1]["tool_use_id"] as? String, "t2")
    }

    func testValidateRejectsUnsupportedParameters() {
        XCTAssertThrowsError(
            try validateAnthropicParameters(
                prediction: .init(type: "content", content: "x"),
                n: nil,
                frequencyPenalty: nil,
                presencePenalty: nil,
                user: nil,
                responseFormat: nil
            )
        )
        XCTAssertThrowsError(
            try validateAnthropicParameters(
                prediction: nil,
                n: 2,
                frequencyPenalty: nil,
                presencePenalty: nil,
                user: nil,
                responseFormat: nil
            )
        )
        XCTAssertThrowsError(
            try validateAnthropicParameters(
                prediction: nil,
                n: nil,
                frequencyPenalty: 0.1,
                presencePenalty: nil,
                user: nil,
                responseFormat: nil
            )
        )
        XCTAssertThrowsError(
            try validateAnthropicParameters(
                prediction: nil,
                n: nil,
                frequencyPenalty: nil,
                presencePenalty: 0.1,
                user: nil,
                responseFormat: nil
            )
        )
        XCTAssertThrowsError(
            try validateAnthropicParameters(
                prediction: nil,
                n: nil,
                frequencyPenalty: nil,
                presencePenalty: nil,
                user: "uid",
                responseFormat: nil
            )
        )
        XCTAssertThrowsError(
            try validateAnthropicParameters(
                prediction: nil,
                n: nil,
                frequencyPenalty: nil,
                presencePenalty: nil,
                user: nil,
                responseFormat: TestFixtures.sampleJsonSchemaFormat()
            )
        )
    }
}
