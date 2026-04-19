import XCTest
@testable import SwiftOpenAI

final class CodexResponsesSupportTests: XCTestCase {

    func testCodexModelInfoExposesRuntimeFields() {
        let info = AIModelInfoValue.codex(
            .init(
                accessToken: "access-token",
                accountID: "account-id",
                modelID: "codex-mini-latest",
                isFedRAMPAccount: true
            )
        )

        XCTAssertTrue(info.isCodex)
        XCTAssertEqual(info.wireAPI, .codexResponses)
        XCTAssertEqual(info.token, "access-token")
        XCTAssertEqual(info.modelID, "codex-mini-latest")
        XCTAssertEqual(info.host, "chatgpt.com")
        XCTAssertEqual(info.resolvedBasePath, "/backend-api/codex")
        XCTAssertEqual(info.baseURL?.absoluteString, "https://chatgpt.com/backend-api/codex")
        XCTAssertEqual(info.codexInfo?.defaultHeaders["Authorization"], "Bearer access-token")
        XCTAssertEqual(info.codexInfo?.defaultHeaders["ChatGPT-Account-ID"], "account-id")
        XCTAssertEqual(info.codexInfo?.defaultHeaders["X-OpenAI-Fedramp"], "true")
    }

    func testCodexResponsesRequestBodyMapsExistingMessagesAndTools() throws {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let tool = ChatQuery.ChatCompletionToolParam(
            type: "function",
            function: .init(
                name: "lookup_weather",
                description: "Look up the weather",
                parameters: [
                    "type": .string("object"),
                    "properties": .object([
                        "city": .object([
                            "type": .string("string")
                        ])
                    ])
                ]
            )
        )

        let body = try makeCodexResponsesRequestBody(
            modelInfo: .init(
                accessToken: "access-token",
                accountID: "account-id",
                modelID: "codex-mini-latest"
            ),
            messages: [
                .system("system prompt"),
                .user("show me", images: [imageData], detail: .high),
                .assistant(
                    "calling tool",
                    toolCalls: [
                        .init(
                            id: "call_123",
                            function: .init(
                                name: "lookup_weather",
                                arguments: #"{"city":"Shanghai"}"#
                            )
                        )
                    ]
                ),
                .tool(
                    "tool result",
                    images: [imageData],
                    detail: .low,
                    toolCallId: "call_123"
                )
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
            think: true,
            extraBody: [
                "metadata": .object([
                    "source": .string("unit-test")
                ])
            ]
        )

        XCTAssertEqual(body["model"] as? String, "codex-mini-latest")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertEqual(body["parallel_tool_calls"] as? Bool, true)
        XCTAssertEqual(body["frequency_penalty"] as? Double, 0.2)
        XCTAssertEqual(body["max_output_tokens"] as? Int, 512)
        XCTAssertEqual(body["presence_penalty"] as? Double, 0.3)
        XCTAssertEqual(body["temperature"] as? Double, 0.6)
        XCTAssertEqual(body["top_p"] as? Double, 0.9)
        XCTAssertEqual(body["stop"] as? [String], ["END"])
        XCTAssertEqual(body["tool_choice"] as? String, "required")

        let reasoning = try XCTUnwrap(body["reasoning"] as? [String: Any])
        XCTAssertEqual(reasoning["effort"] as? String, "medium")

        let metadata = try XCTUnwrap(body["metadata"] as? [String: Any])
        XCTAssertEqual(metadata["source"] as? String, "unit-test")

        let text = try XCTUnwrap(body["text"] as? [String: Any])
        let format = try XCTUnwrap(text["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(format["name"] as? String, "weather_response")

        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools.first?["type"] as? String, "function")
        XCTAssertEqual(tools.first?["name"] as? String, "lookup_weather")

        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 5)

        XCTAssertEqual(input[0]["type"] as? String, "message")
        XCTAssertEqual(input[0]["role"] as? String, "system")

        let userContent = try XCTUnwrap(input[1]["content"] as? [[String: Any]])
        XCTAssertEqual(userContent.first?["type"] as? String, "input_image")
        XCTAssertEqual(userContent.first?["detail"] as? String, "high")
        XCTAssertEqual(userContent.last?["type"] as? String, "input_text")
        XCTAssertEqual(userContent.last?["text"] as? String, "show me")

        XCTAssertEqual(input[2]["type"] as? String, "message")
        XCTAssertEqual(input[2]["role"] as? String, "assistant")

        XCTAssertEqual(input[3]["type"] as? String, "function_call")
        XCTAssertEqual(input[3]["call_id"] as? String, "call_123")
        XCTAssertEqual(input[3]["name"] as? String, "lookup_weather")
        XCTAssertEqual(input[3]["arguments"] as? String, #"{"city":"Shanghai"}"#)

        XCTAssertEqual(input[4]["type"] as? String, "function_call_output")
        XCTAssertEqual(input[4]["call_id"] as? String, "call_123")
        let output = try XCTUnwrap(input[4]["output"] as? [[String: Any]])
        XCTAssertEqual(output.first?["type"] as? String, "input_image")
        XCTAssertEqual(output.first?["detail"] as? String, "low")
        XCTAssertEqual(output.last?["type"] as? String, "input_text")
        XCTAssertEqual(output.last?["text"] as? String, "tool result")
    }

    func testCodexSSEProcessingAccumulatesTextReasoningToolCallsAndUsage() async throws {
        let helper = OpenAISendMessageValueHelper()
        var state = CodexResponsesStreamState()
        var metadata = ChatResponseMetadata(
            providerName: "openai-codex",
            requestID: nil,
            resolvedModel: "codex-mini-latest",
            resolvedBasePath: "/backend-api/codex"
        )

        let firstChunk = try (
            [
            makeSSELine([
                "type": "response.created",
                "response": [
                    "id": "resp_123",
                    "model": "codex-mini-latest"
                ]
            ]),
            makeSSELine([
                "type": "response.output_item.added",
                "item": [
                    "id": "item_1",
                    "type": "function_call",
                    "call_id": "call_123",
                    "name": "lookup_weather",
                    "arguments": "Shang"
                ]
            ])
            ].joined(separator: "\n") + "\n"
        )
        let secondChunk = try [
            makeSSELine([
                "type": "response.function_call_arguments.delta",
                "item_id": "item_1",
                "delta": "hai"
            ]),
            makeSSELine([
                "type": "response.reasoning_summary_text.delta",
                "delta": "thinking..."
            ]),
            makeSSELine([
                "type": "response.output_text.delta",
                "delta": "final answer"
            ]),
            makeSSELine([
                "type": "response.completed",
                "response": [
                    "id": "resp_123",
                    "model": "codex-ultra",
                    "usage": [
                        "input_tokens": 11,
                        "output_tokens": 7,
                        "total_tokens": 18,
                        "input_tokens_details": [
                            "cached_tokens": 3
                        ],
                        "output_tokens_details": [
                            "reasoning_tokens": 5
                        ]
                    ]
                ]
            ])
        ].joined(separator: "\n")

        try await processCodexResponsesSSEText(
            firstChunk,
            actorHelper: helper,
            state: &state,
            metadata: &metadata
        )
        try await processCodexResponsesSSEText(
            secondChunk,
            actorHelper: helper,
            state: &state,
            metadata: &metadata,
            finalize: true
        )

        let fullThinkingText = await helper.fullThinkingText
        let fullText = await helper.fullText
        XCTAssertEqual(fullThinkingText, "thinking...")
        XCTAssertEqual(fullText, "final answer")

        let toolCalls = await helper.allToolCalls
        XCTAssertEqual(toolCalls.count, 1)
        XCTAssertEqual(toolCalls[0].id, "call_123")
        XCTAssertEqual(toolCalls[0].function?.name, "lookup_weather")
        XCTAssertEqual(toolCalls[0].function?.arguments, "Shanghai")

        XCTAssertEqual(state.usage?.promptTokens, 11)
        XCTAssertEqual(state.usage?.completionTokens, 7)
        XCTAssertEqual(state.usage?.totalTokens, 18)
        XCTAssertEqual(state.usage?.cachedTokens, 3)
        XCTAssertEqual(state.usage?.reasoningTokens, 5)
        XCTAssertEqual(metadata.resolvedModel, "codex-ultra")
    }

    func testSendMessageUsesCodexBranchWithoutChangingPublicMessageAPI() async throws {
        do {
            _ = try await sendMessage(
                modelInfo: .codex(
                    .init(
                        accessToken: "access-token",
                        accountID: "account-id"
                    )
                ),
                messages: [.user("hello")],
                prediction: .init(type: "content", content: "prefill")
            ) { _ in }
            XCTFail("Expected Codex branch to reject unsupported prediction before issuing a request")
        } catch let error as OpenAIError {
            switch error {
            case .providerUnsupported(let message):
                XCTAssertTrue(message.contains("prediction"))
            default:
                XCTFail("Unexpected OpenAIError: \(error)")
            }
        }
    }

    private func makeSSELine(_ payload: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        return "data: " + String(decoding: data, as: UTF8.self)
    }
}
