import XCTest
@testable import SwiftOpenAI

final class CompletionsDecodingTests: XCTestCase {

    func testCompletionDecodesReasoningDetailsAndUsage() throws {
        let json = """
        {
          "id": "chatcmpl-test",
          "object": "chat.completion",
          "created": 1,
          "model": "MiniMax-M2.7",
          "choices": [
            {
              "index": 0,
              "message": {
                "role": "assistant",
                "content": "done",
                "reasoning_details": [
                  { "text": "thinking-output" }
                ]
              },
              "finish_reason": "stop"
            }
          ],
          "usage": {
            "prompt_tokens": 10,
            "completion_tokens": 5,
            "total_tokens": 15,
            "prompt_tokens_details": { "cached_tokens": 3 },
            "completion_tokens_details": { "reasoning_tokens": 2 }
          }
        }
        """
        let result = try JSONDecoder().decode(ChatCompletionResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.choices.first?.message.reasoning, "thinking-output")
        XCTAssertEqual(result.usage?.cachedTokens, 3)
        XCTAssertEqual(result.usage?.reasoningTokens, 2)
    }

    func testStreamDecodesTopLevelUsageAndReasoningDetails() throws {
        let json = """
        {
          "id": "chunk-1",
          "object": "chat.completion.chunk",
          "created": 1,
          "model": "MiniMax-M2.7",
          "choices": [
            {
              "index": 0,
              "delta": {
                "content": "hello",
                "reasoning_details": [{ "text": "step-one" }]
              }
            }
          ],
          "usage": {
            "prompt_tokens": 12,
            "completion_tokens": 4,
            "total_tokens": 16,
            "prompt_tokens_details": { "cached_tokens": 1 },
            "completion_tokens_details": { "reasoning_tokens": 6 }
          }
        }
        """
        let result = try JSONDecoder().decode(ChatStreamResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.choices.first?.delta.reasoning, "step-one")
        XCTAssertEqual(result.usage?.cachedTokens, 1)
        XCTAssertEqual(result.usage?.reasoningTokens, 6)
    }

    func testFinalUsageChunkAllowsEmptyChoices() throws {
        let json = """
        {
          "id": "chunk-final",
          "object": "chat.completion.chunk",
          "created": 1,
          "model": "MiniMax-M2.7",
          "choices": [],
          "usage": {
            "prompt_tokens": 2052,
            "completion_tokens": 89,
            "total_tokens": 2141,
            "completion_tokens_details": { "reasoning_tokens": 74 }
          }
        }
        """
        let result = try JSONDecoder().decode(ChatStreamResult.self, from: Data(json.utf8))
        XCTAssertTrue(result.choices.isEmpty)
        XCTAssertEqual(result.usage?.reasoningTokens, 74)
    }

    func testMiniMaxNormalizerConvertsCumulativeDeltas() {
        var state = ProviderStreamNormalizationState()
        let first = ChatStreamResult(
            id: "1",
            object: "chat.completion.chunk",
            created: 1,
            model: "MiniMax-M2.7",
            choices: [
                .init(
                    index: 0,
                    delta: .init(
                        content: "hel",
                        reasoning: "thi",
                        toolCalls: [
                            .init(index: 0, id: "call_1", type: "function", function: .init(name: "calc", arguments: "{"))
                        ]
                    )
                )
            ]
        )
        let second = ChatStreamResult(
            id: "2",
            object: "chat.completion.chunk",
            created: 2,
            model: "MiniMax-M2.7",
            choices: [
                .init(
                    index: 0,
                    delta: .init(
                        content: "hello",
                        reasoning: "think",
                        toolCalls: [
                            .init(index: 0, id: "call_1", type: "function", function: .init(name: "calculator", arguments: "{\"a\":1}"))
                        ]
                    )
                )
            ]
        )

        let n1 = ProviderResponseNormalizer.normalize(streamChunk: first, family: .minimax, state: &state)
        XCTAssertEqual(n1.choices.first?.delta.content, "hel")
        XCTAssertEqual(n1.choices.first?.delta.toolCalls?.first?.function?.name, "calc")

        let n2 = ProviderResponseNormalizer.normalize(streamChunk: second, family: .minimax, state: &state)
        XCTAssertEqual(n2.choices.first?.delta.content, "lo")
        XCTAssertEqual(n2.choices.first?.delta.reasoning, "nk")
        XCTAssertNil(n2.choices.first?.delta.toolCalls?.first?.id)
        XCTAssertEqual(n2.choices.first?.delta.toolCalls?.first?.function?.name, "ulator")
        XCTAssertEqual(n2.choices.first?.delta.toolCalls?.first?.function?.arguments, "\"a\":1}")
    }
}
