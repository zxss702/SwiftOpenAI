import XCTest
@testable import SwiftOpenAI

final class AnthropicSSETests: XCTestCase {

    func testSSEAccumulatesTextThinkingToolPartialJSONAndUsage() async throws {
        let helper = OpenAISendMessageValueHelper()
        var state = AnthropicStreamState()
        var metadata = ChatResponseMetadata(
            providerName: "anthropic",
            requestID: nil,
            resolvedModel: "claude-a",
            resolvedBasePath: "/v1"
        )

        let firstChunk = try [
            TestFixtures.makeSSELine([
                "type": "message_start",
                "message": [
                    "id": "msg_1",
                    "model": "claude-a",
                    "usage": ["input_tokens": 10, "output_tokens": 0]
                ]
            ]),
            TestFixtures.makeSSELine([
                "type": "content_block_start",
                "index": 0,
                "content_block": ["type": "text", "text": ""]
            ]),
            "event: content_block_delta",
            TestFixtures.makeSSELine([
                "type": "content_block_delta",
                "index": 0,
                "delta": ["type": "text_delta", "text": "Hello"]
            ])
        ].joined(separator: "\n") + "\n"

        let secondChunk = try [
            TestFixtures.makeSSELine([
                "type": "content_block_delta",
                "index": 1,
                "delta": ["type": "thinking_delta", "thinking": "ponder"]
            ]),
            TestFixtures.makeSSELine([
                "type": "content_block_start",
                "index": 2,
                "content_block": [
                    "type": "tool_use",
                    "id": "toolu_1",
                    "name": "get_weather",
                    "input": [:] as [String: Any]
                ]
            ]),
            TestFixtures.makeSSELine([
                "type": "content_block_delta",
                "index": 2,
                "delta": ["type": "input_json_delta", "partial_json": #"{"city":""#]
            ]),
            TestFixtures.makeSSELine([
                "type": "content_block_delta",
                "index": 2,
                "delta": ["type": "input_json_delta", "partial_json": #"Shanghai"}"#]
            ]),
            TestFixtures.makeSSELine([
                "type": "message_delta",
                "delta": ["stop_reason": "tool_use"],
                "usage": ["output_tokens": 22]
            ]),
            TestFixtures.makeSSELine([
                "type": "message_stop"
            ]),
            TestFixtures.makeSSELine([
                "type": "ping"
            ])
        ].joined(separator: "\n")

        try await processAnthropicSSEBytes(
            Data(firstChunk.utf8),
            actorHelper: helper,
            state: &state,
            metadata: &metadata
        )
        try await processAnthropicSSEBytes(
            Data(secondChunk.utf8),
            actorHelper: helper,
            state: &state,
            metadata: &metadata,
            finalize: true
        )

        let fullText = await helper.fullText
        let fullThinkingText = await helper.fullThinkingText
        XCTAssertEqual(fullText, "Hello")
        XCTAssertEqual(fullThinkingText, "ponder")

        let toolCalls = await helper.allToolCalls
        XCTAssertEqual(toolCalls.count, 1)
        XCTAssertEqual(toolCalls[0].id, "toolu_1")
        XCTAssertEqual(toolCalls[0].function?.name, "get_weather")
        XCTAssertEqual(toolCalls[0].function?.arguments, #"{"city":"Shanghai"}"#)

        XCTAssertEqual(state.usage?.promptTokens, 10)
        XCTAssertEqual(state.usage?.completionTokens, 22)
        XCTAssertEqual(state.usage?.totalTokens, 32)
    }

    func testErrorEventThrows() async throws {
        let helper = OpenAISendMessageValueHelper()
        var state = AnthropicStreamState()
        var metadata = ChatResponseMetadata(
            providerName: "anthropic",
            requestID: nil,
            resolvedModel: "m",
            resolvedBasePath: "/v1"
        )
        let line = try TestFixtures.makeSSELine([
            "type": "error",
            "error": [
                "type": "api_error",
                "message": "rate limited"
            ]
        ]) + "\n"

        do {
            try await processAnthropicSSEBytes(
                Data(line.utf8),
                actorHelper: helper,
                state: &state,
                metadata: &metadata,
                finalize: true
            )
            XCTFail("Expected failure")
        } catch let error as OpenAIError {
            switch error {
            case .invalidResponse(let message, _):
                XCTAssertTrue(message.contains("rate limited"))
            default:
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
}
