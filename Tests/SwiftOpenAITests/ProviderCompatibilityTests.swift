import XCTest
@testable import SwiftOpenAI
import Foundation

final class ProviderCompatibilityTests: XCTestCase {

    func testProviderFamilyResolverUsesHostOnly() {
        XCTAssertEqual(ProviderFamilyResolver.resolve(host: "api.openai.com"), .openai)
        XCTAssertEqual(ProviderFamilyResolver.resolve(host: "dashscope.aliyuncs.com"), .dashscope)
        XCTAssertEqual(ProviderFamilyResolver.resolve(host: "open.bigmodel.cn"), .zhipuGLM)
        XCTAssertEqual(ProviderFamilyResolver.resolve(host: "api.moonshot.cn"), .moonshot)
        XCTAssertEqual(ProviderFamilyResolver.resolve(host: "api.kimi.com"), .moonshot)
        XCTAssertEqual(ProviderFamilyResolver.resolve(host: "api.minimaxi.com"), .minimax)
        XCTAssertEqual(ProviderFamilyResolver.resolve(host: "api.minimax.io"), .minimax)
        XCTAssertEqual(ProviderFamilyResolver.resolve(host: "ark.cn-beijing.volces.com"), .volcengineArk)
        XCTAssertEqual(ProviderFamilyResolver.resolve(host: "api.siliconflow.cn"), .genericOpenAICompatible)
    }

    func testPathAssemblyAppendsChatCompletionsOnce() async throws {
        let query = ChatQuery(messages: [.user("hello")], model: "glm-4.5")
        let prepared = try await createChatRequest(
            query: query,
            configuration: OpenAIConfiguration(
                token: "test-token",
                host: "open.bigmodel.cn",
                basePath: "/api/coding/paas/v4"
            )
        )
        XCTAssertEqual(prepared.urlRequest.url?.host, "open.bigmodel.cn")
        XCTAssertEqual(prepared.urlRequest.url?.path, "/api/coding/paas/v4/chat/completions")

        let prebuiltPrepared = try await createChatRequest(
            query: query,
            configuration: OpenAIConfiguration(
                token: "test-token",
                host: "open.bigmodel.cn",
                basePath: "/api/coding/paas/v4/chat/completions"
            )
        )
        XCTAssertEqual(prebuiltPrepared.urlRequest.url?.path, "/api/coding/paas/v4/chat/completions")
    }

    func testRequestBodyUsesProviderSpecificWireKeys() async throws {
        let query = ChatQuery(
            messages: [
                .assistant("previous", reasoningContent: "think-first"),
                .user("hello")
            ],
            model: "MiniMax-M2.7",
            maxCompletionTokens: 128,
            parallelToolCalls: true,
            topP: 0.85,
            think: true
        )
        let prepared = try await createChatRequest(
            query: query,
            configuration: OpenAIConfiguration(
                token: "test-token",
                host: "api.minimaxi.com",
                basePath: "/v1"
            )
        )

        let body = try requestBody(from: prepared.urlRequest)
        XCTAssertEqual(body["model"] as? String, "MiniMax-M2.7")
        XCTAssertEqual(body["max_tokens"] as? Int, 128)
        XCTAssertNil(body["max_completion_tokens"])
        XCTAssertEqual(body["parallel_tool_calls"] as? Bool, true)
        XCTAssertEqual(body["top_p"] as? Double, 0.85)
        XCTAssertEqual(body["reasoning_split"] as? Bool, true)

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let assistantMessage = try XCTUnwrap(messages.first)
        XCTAssertNil(assistantMessage["reasoning_content"])
        let reasoningDetails = try XCTUnwrap(assistantMessage["reasoning_details"] as? [[String: Any]])
        XCTAssertEqual(reasoningDetails.first?["text"] as? String, "think-first")
    }

    func testOpenAIUsesMaxCompletionTokensKey() async throws {
        let query = ChatQuery(
            messages: [.user("hello")],
            model: "gpt-5",
            maxCompletionTokens: 256
        )
        let prepared = try await createChatRequest(
            query: query,
            configuration: OpenAIConfiguration(
                token: "test-token",
                host: "api.openai.com",
                basePath: "/v1"
            )
        )

        let body = try requestBody(from: prepared.urlRequest)
        XCTAssertEqual(body["max_completion_tokens"] as? Int, 256)
        XCTAssertNil(body["max_tokens"])
    }

    func testMoonshotOmitsAssistantReasoningHistory() async throws {
        let query = ChatQuery(
            messages: [
                .assistant("previous", reasoningContent: "should-not-be-sent"),
                .user("hello")
            ],
            model: "kimi-k2",
            think: true
        )
        let prepared = try await createChatRequest(
            query: query,
            configuration: OpenAIConfiguration(
                token: "test-token",
                host: "api.kimi.com",
                basePath: "/coding/v1"
            )
        )

        let body = try requestBody(from: prepared.urlRequest)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let assistantMessage = try XCTUnwrap(messages.first)
        XCTAssertNil(assistantMessage["reasoning_content"])
        XCTAssertNil(assistantMessage["reasoning_details"])
    }

    func testGLMAndDashScopeThinkMappings() async throws {
        let glmPrepared = try await createChatRequest(
            query: ChatQuery(messages: [.user("hello")], model: "glm-4.5", think: false),
            configuration: OpenAIConfiguration(
                token: "test-token",
                host: "open.bigmodel.cn",
                basePath: "/api/paas/v4"
            )
        )
        let glmBody = try requestBody(from: glmPrepared.urlRequest)
        let glmThinking = try XCTUnwrap(glmBody["thinking"] as? [String: Any])
        XCTAssertEqual(glmThinking["type"] as? String, "disabled")

        let dashscopePrepared = try await createChatRequest(
            query: ChatQuery(messages: [.user("hello")], model: "qwen-plus", think: true),
            configuration: OpenAIConfiguration(
                token: "test-token",
                host: "dashscope.aliyuncs.com",
                basePath: "/compatible-mode/v1"
            )
        )
        let dashscopeBody = try requestBody(from: dashscopePrepared.urlRequest)
        XCTAssertEqual(dashscopeBody["enable_thinking"] as? Bool, true)
    }

    func testMiniMaxCompletionDecodesReasoningDetailsAndUsage() throws {
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
            "prompt_tokens_details": {
              "cached_tokens": 3
            },
            "completion_tokens_details": {
              "reasoning_tokens": 2
            }
          }
        }
        """

        let result = try JSONDecoder().decode(ChatCompletionResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.choices.first?.message.reasoning, "thinking-output")
        XCTAssertEqual(result.usage?.promptTokens, 10)
        XCTAssertEqual(result.usage?.completionTokens, 5)
        XCTAssertEqual(result.usage?.totalTokens, 15)
        XCTAssertEqual(result.usage?.cachedTokens, 3)
        XCTAssertEqual(result.usage?.reasoningTokens, 2)
    }

    func testMiniMaxStreamDecodesTopLevelUsageAndReasoningDetails() throws {
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
                "reasoning_details": [
                  { "text": "step-one" }
                ]
              }
            }
          ],
          "usage": {
            "prompt_tokens": 12,
            "completion_tokens": 4,
            "total_tokens": 16,
            "prompt_tokens_details": {
              "cached_tokens": 1
            },
            "completion_tokens_details": {
              "reasoning_tokens": 6
            }
          }
        }
        """

        let result = try JSONDecoder().decode(ChatStreamResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.choices.first?.delta.reasoning, "step-one")
        XCTAssertEqual(result.usage?.promptTokens, 12)
        XCTAssertEqual(result.usage?.cachedTokens, 1)
        XCTAssertEqual(result.usage?.reasoningTokens, 6)
    }

    func testMiniMaxStreamNormalizerConvertsCumulativeDeltas() {
        var state = ProviderStreamNormalizationState()

        let firstChunk = ChatStreamResult(
            id: "chunk-1",
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
                            .init(
                                index: 0,
                                id: "call_1",
                                type: "function",
                                function: .init(name: "calc", arguments: "{")
                            )
                        ]
                    )
                )
            ]
        )

        let secondChunk = ChatStreamResult(
            id: "chunk-2",
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
                            .init(
                                index: 0,
                                id: "call_1",
                                type: "function",
                                function: .init(name: "calculator", arguments: "{\"a\":1}")
                            )
                        ]
                    )
                )
            ]
        )

        let normalizedFirst = ProviderResponseNormalizer.normalize(
            streamChunk: firstChunk,
            family: .minimax,
            state: &state
        )
        XCTAssertEqual(normalizedFirst.choices.first?.delta.content, "hel")
        XCTAssertEqual(normalizedFirst.choices.first?.delta.reasoning, "thi")
        XCTAssertEqual(normalizedFirst.choices.first?.delta.toolCalls?.first?.function?.name, "calc")

        let normalizedSecond = ProviderResponseNormalizer.normalize(
            streamChunk: secondChunk,
            family: .minimax,
            state: &state
        )
        XCTAssertEqual(normalizedSecond.choices.first?.delta.content, "lo")
        XCTAssertEqual(normalizedSecond.choices.first?.delta.reasoning, "nk")
        XCTAssertEqual(normalizedSecond.choices.first?.delta.toolCalls?.first?.id, nil)
        XCTAssertEqual(normalizedSecond.choices.first?.delta.toolCalls?.first?.function?.name, "ulator")
        XCTAssertEqual(normalizedSecond.choices.first?.delta.toolCalls?.first?.function?.arguments, "\"a\":1}")
    }

    private func requestBody(from request: URLRequest) throws -> [String: Any] {
        let body = try XCTUnwrap(request.httpBody)
        let jsonObject = try JSONSerialization.jsonObject(with: body, options: [])
        return try XCTUnwrap(jsonObject as? [String: Any])
    }
}
