import XCTest
@testable import SwiftOpenAI

final class ResponsesSSETests: XCTestCase {

    func testSSEAccumulatesTextReasoningToolCallsAndUsage() async throws {
        let helper = OpenAISendMessageValueHelper()
        var state = ResponsesStreamState()
        var metadata = ChatResponseMetadata(
            providerName: "openai-responses",
            requestID: nil,
            resolvedModel: "model-a",
            resolvedBasePath: "/v1"
        )

        let firstChunk = try [
            TestFixtures.makeSSELine([
                "type": "response.created",
                "response": ["id": "resp_123", "model": "model-a"]
            ]),
            TestFixtures.makeSSELine([
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

        let secondChunk = try [
            TestFixtures.makeSSELine([
                "type": "response.function_call_arguments.delta",
                "item_id": "item_1",
                "delta": "hai"
            ]),
            TestFixtures.makeSSELine([
                "type": "response.reasoning_summary_text.delta",
                "delta": "thinking..."
            ]),
            TestFixtures.makeSSELine([
                "type": "response.output_text.delta",
                "delta": "final answer"
            ]),
            TestFixtures.makeSSELine([
                "type": "response.completed",
                "response": [
                    "id": "resp_123",
                    "model": "model-b",
                    "usage": [
                        "input_tokens": 11,
                        "output_tokens": 7,
                        "total_tokens": 18,
                        "input_tokens_details": ["cached_tokens": 3],
                        "output_tokens_details": ["reasoning_tokens": 5]
                    ]
                ]
            ])
        ].joined(separator: "\n")

        try await processResponsesSSEBytes(
            Data(firstChunk.utf8),
            actorHelper: helper,
            state: &state,
            metadata: &metadata
        )
        try await processResponsesSSEBytes(
            Data(secondChunk.utf8),
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
        XCTAssertEqual(toolCalls[0].function?.arguments, "Shanghai")

        XCTAssertEqual(state.usage?.promptTokens, 11)
        XCTAssertEqual(state.usage?.cachedTokens, 3)
        XCTAssertEqual(state.usage?.reasoningTokens, 5)
        XCTAssertEqual(metadata.resolvedModel, "model-b")
    }

    func testFailedEventThrows() async throws {
        let helper = OpenAISendMessageValueHelper()
        var state = ResponsesStreamState()
        var metadata = ChatResponseMetadata(
            providerName: "openai-responses",
            requestID: nil,
            resolvedModel: "m",
            resolvedBasePath: "/v1"
        )
        let line = try TestFixtures.makeSSELine([
            "type": "response.failed",
            "response": [
                "error": ["message": "boom"]
            ]
        ]) + "\n"

        do {
            try await processResponsesSSEBytes(
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
                XCTAssertTrue(message.contains("boom"))
            default:
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
}
