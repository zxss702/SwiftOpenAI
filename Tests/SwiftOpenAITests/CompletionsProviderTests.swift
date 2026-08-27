import XCTest
@testable import SwiftOpenAI

final class CompletionsProviderTests: XCTestCase {

    func testProviderFamilyResolverUsesHostOnly() {
        XCTAssertEqual(ProviderFamilyResolver.resolve(host: "api.openai.com"), .openai)
        XCTAssertEqual(ProviderFamilyResolver.resolve(host: "dashscope.aliyuncs.com"), .dashscope)
        XCTAssertEqual(ProviderFamilyResolver.resolve(host: "open.bigmodel.cn"), .zhipuGLM)
        XCTAssertEqual(ProviderFamilyResolver.resolve(host: "api.moonshot.cn"), .moonshot)
        XCTAssertEqual(ProviderFamilyResolver.resolve(host: "api.kimi.com"), .moonshot)
        XCTAssertEqual(ProviderFamilyResolver.resolve(host: "api.minimaxi.com"), .minimax)
        XCTAssertEqual(ProviderFamilyResolver.resolve(host: "api.minimax.io"), .minimax)
        XCTAssertEqual(ProviderFamilyResolver.resolve(host: "ark.cn-beijing.volces.com"), .volcengineArk)
        XCTAssertEqual(ProviderFamilyResolver.resolve(host: "api.deepseek.com"), .deepseek)
        XCTAssertEqual(ProviderFamilyResolver.resolve(host: "api.siliconflow.cn"), .genericOpenAICompatible)
    }

    func testOpenAIUsesMaxCompletionTokensAndReasoningEffort() async throws {
        let prepared = try await createChatRequest(
            query: ChatQuery(
                messages: [.user("hello")],
                model: "gpt-5",
                maxCompletionTokens: 256,
                thinkLevel: .high
            ),
            configuration: TestFixtures.configuration(host: "api.openai.com")
        )
        let body = try TestFixtures.requestBody(from: prepared.urlRequest)
        XCTAssertEqual(body["max_completion_tokens"] as? Int, 256)
        XCTAssertNil(body["max_tokens"])
        XCTAssertEqual(body["reasoning_effort"] as? String, "high")
        XCTAssertNil(body["thinking"])
    }

    func testMiniMaxUsesMaxTokensReasoningSplitAndDetailsEncoding() async throws {
        let prepared = try await createChatRequest(
            query: ChatQuery(
                messages: [
                    .assistant("previous", reasoningContent: "think-first"),
                    .user("hello")
                ],
                model: "MiniMax-M2.7",
                maxCompletionTokens: 128,
                thinkLevel: .high
            ),
            configuration: TestFixtures.configuration(host: "api.minimaxi.com")
        )
        let body = try TestFixtures.requestBody(from: prepared.urlRequest)
        XCTAssertEqual(body["max_tokens"] as? Int, 128)
        XCTAssertNil(body["max_completion_tokens"])
        XCTAssertEqual(body["reasoning_split"] as? Bool, true)
        let thinking = try XCTUnwrap(body["thinking"] as? [String: Any])
        XCTAssertEqual(thinking["type"] as? String, "adaptive")

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let assistant = try XCTUnwrap(messages.first)
        XCTAssertNil(assistant["reasoning_content"])
        let details = try XCTUnwrap(assistant["reasoning_details"] as? [[String: Any]])
        XCTAssertEqual(details.first?["text"] as? String, "think-first")
    }

    func testMiniMaxThinkLevelNoneDisablesThinkingButKeepsSplit() async throws {
        let prepared = try await createChatRequest(
            query: ChatQuery(messages: [.user("hello")], model: "MiniMax-M2.7", thinkLevel: ThinkLevel.none),
            configuration: TestFixtures.configuration(host: "api.minimax.io")
        )
        let body = try TestFixtures.requestBody(from: prepared.urlRequest)
        XCTAssertEqual(body["reasoning_split"] as? Bool, true)
        let thinking = try XCTUnwrap(body["thinking"] as? [String: Any])
        XCTAssertEqual(thinking["type"] as? String, "disabled")
    }

    func testStreamingDefaultsIncludeUsage() async throws {
        let prepared = try await createChatRequest(
            query: ChatQuery(messages: [.user("hello")], model: "gpt-4", stream: true),
            configuration: TestFixtures.configuration(host: "api.openai.com")
        )
        let body = try TestFixtures.requestBody(from: prepared.urlRequest)
        let streamOptions = try XCTUnwrap(body["stream_options"] as? [String: Any])
        XCTAssertEqual(streamOptions["include_usage"] as? Bool, true)
    }

    func testMoonshotEncodesReasoningContent() async throws {
        let prepared = try await createChatRequest(
            query: ChatQuery(
                messages: [
                    .assistant("previous", reasoningContent: "keep-me"),
                    .user("hello")
                ],
                model: "kimi-k2"
            ),
            configuration: TestFixtures.configuration(host: "api.kimi.com", basePath: "/coding/v1")
        )
        let body = try TestFixtures.requestBody(from: prepared.urlRequest)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let assistant = try XCTUnwrap(messages.first)
        XCTAssertEqual(assistant["reasoning_content"] as? String, "keep-me")
        XCTAssertNil(assistant["reasoning_details"])
    }

    func testThinkLevelMappingsForGLMDashScopeDeepSeekAndGeneric() async throws {
        let glm = try await createChatRequest(
            query: ChatQuery(messages: [.user("hello")], model: "glm-4.5", thinkLevel: .high),
            configuration: TestFixtures.configuration(host: "open.bigmodel.cn", basePath: "/api/paas/v4")
        )
        let glmBody = try TestFixtures.requestBody(from: glm.urlRequest)
        XCTAssertEqual((glmBody["thinking"] as? [String: Any])?["type"] as? String, "enabled")
        XCTAssertEqual(glmBody["reasoning_effort"] as? String, "high")

        let dash = try await createChatRequest(
            query: ChatQuery(messages: [.user("hello")], model: "qwen-plus", thinkLevel: .medium),
            configuration: TestFixtures.configuration(host: "dashscope.aliyuncs.com", basePath: "/compatible-mode/v1")
        )
        let dashBody = try TestFixtures.requestBody(from: dash.urlRequest)
        XCTAssertEqual(dashBody["enable_thinking"] as? Bool, true)

        let deepseek = try await createChatRequest(
            query: ChatQuery(messages: [.user("hello")], model: "deepseek-v4-pro", thinkLevel: .xhigh),
            configuration: TestFixtures.configuration(host: "api.deepseek.com")
        )
        let deepseekBody = try TestFixtures.requestBody(from: deepseek.urlRequest)
        XCTAssertEqual((deepseekBody["thinking"] as? [String: Any])?["type"] as? String, "enabled")
        XCTAssertEqual(deepseekBody["reasoning_effort"] as? String, "xhigh")

        let generic = try await createChatRequest(
            query: ChatQuery(messages: [.user("hello")], model: "custom", thinkLevel: .max),
            configuration: TestFixtures.configuration(host: "api.siliconflow.cn")
        )
        let genericBody = try TestFixtures.requestBody(from: generic.urlRequest)
        XCTAssertEqual(genericBody["reasoning_effort"] as? String, "max")
    }

    func testToolStrictPassthroughAndStripping() async throws {
        let openai = try await createChatRequest(
            query: ChatQuery(messages: [.user("hello")], model: "gpt-5", tools: [TestFixtures.weatherTool(strict: nil)]),
            configuration: TestFixtures.configuration(host: "api.openai.com")
        )
        let openaiTools = try XCTUnwrap(
            (try TestFixtures.requestBody(from: openai.urlRequest)["tools"] as? [[String: Any]])
        )
        XCTAssertNil((openaiTools[0]["function"] as? [String: Any])?["strict"])

        let moonshot = try await createChatRequest(
            query: ChatQuery(messages: [.user("hello")], model: "kimi-k2", tools: [TestFixtures.weatherTool(strict: false)]),
            configuration: TestFixtures.configuration(host: "api.moonshot.cn")
        )
        let moonshotTools = try XCTUnwrap(
            (try TestFixtures.requestBody(from: moonshot.urlRequest)["tools"] as? [[String: Any]])
        )
        XCTAssertEqual((moonshotTools[0]["function"] as? [String: Any])?["strict"] as? Bool, false)

        for host in ["open.bigmodel.cn", "api.minimaxi.com", "api.siliconflow.cn"] {
            let prepared = try await createChatRequest(
                query: ChatQuery(messages: [.user("hello")], model: "m", tools: [TestFixtures.weatherTool(strict: true)]),
                configuration: TestFixtures.configuration(host: host)
            )
            let tools = try XCTUnwrap(
                (try TestFixtures.requestBody(from: prepared.urlRequest)["tools"] as? [[String: Any]])
            )
            XCTAssertNil((tools[0]["function"] as? [String: Any])?["strict"], host)
        }

        let deepseek = try await createChatRequest(
            query: ChatQuery(
                messages: [.user("hello")],
                model: "deepseek-v4-pro",
                tools: [TestFixtures.weatherTool(strict: true)]
            ),
            configuration: TestFixtures.configuration(host: "api.deepseek.com")
        )
        let deepseekTools = try XCTUnwrap(
            (try TestFixtures.requestBody(from: deepseek.urlRequest)["tools"] as? [[String: Any]])
        )
        XCTAssertEqual((deepseekTools[0]["function"] as? [String: Any])?["strict"] as? Bool, true)
    }

    func testUnsupportedMultimediaDowngradesToPlaintext() async throws {
        let prepared = try await createChatRequest(
            query: ChatQuery(
                messages: [
                    .user("请分析这张图片", imageDatas: TestFixtures.tinyPNG, detail: .high),
                    .assistant("", toolCalls: [
                        .init(id: "call_1", function: .init(name: "analyze_image", arguments: "{}"))
                    ]),
                    .tool("工具结果", images: [TestFixtures.tinyPNG], detail: .high, toolCallId: "call_1")
                ],
                model: "MiniMax-M2.7"
            ),
            configuration: TestFixtures.configuration(host: "api.minimaxi.com")
        )
        let messages = try XCTUnwrap(
            (try TestFixtures.requestBody(from: prepared.urlRequest)["messages"] as? [[String: Any]])
        )
        let userContent = try XCTUnwrap(messages[0]["content"] as? String)
        XCTAssertTrue(userContent.contains("image 不支持"))
        let toolContent = try XCTUnwrap(messages[2]["content"] as? String)
        XCTAssertTrue(toolContent.contains("image 不支持"))
    }

    func testSupportedMultimediaKeepsImageParts() async throws {
        let prepared = try await createChatRequest(
            query: ChatQuery(
                messages: [.user("请分析这张图片", imageDatas: TestFixtures.tinyPNG, detail: .high)],
                model: "gpt-4o"
            ),
            configuration: TestFixtures.configuration(host: "api.openai.com")
        )
        let messages = try XCTUnwrap(
            (try TestFixtures.requestBody(from: prepared.urlRequest)["messages"] as? [[String: Any]])
        )
        let parts = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
        XCTAssertTrue(parts.contains { ($0["type"] as? String) == "image_url" })
    }

    func testDeepSeekVisionCapabilityMatrix() async throws {
        let nonVision = try await createChatRequest(
            query: ChatQuery(
                messages: [.user("img", imageDatas: TestFixtures.tinyPNG, detail: .high)],
                model: "deepseek-v4-pro"
            ),
            configuration: TestFixtures.configuration(host: "api.deepseek.com")
        )
        let nonVisionContent = try XCTUnwrap(
            ((try TestFixtures.requestBody(from: nonVision.urlRequest)["messages"] as? [[String: Any]])?.first?["content"] as? String)
        )
        XCTAssertTrue(nonVisionContent.contains("image 不支持"))

        let vision = try await createChatRequest(
            query: ChatQuery(
                messages: [.user("img", imageDatas: TestFixtures.tinyPNG, detail: .high)],
                model: "deepseek-v4-flash-vision-exp"
            ),
            configuration: TestFixtures.configuration(host: "api.deepseek.com")
        )
        let visionParts = try XCTUnwrap(
            ((try TestFixtures.requestBody(from: vision.urlRequest)["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]])
        )
        XCTAssertTrue(visionParts.contains { ($0["type"] as? String) == "image_url" })

        let videoOnly = try await createChatRequest(
            query: ChatQuery(
                messages: [.user("vid", videoDatas: TestFixtures.tinyVideo)],
                model: "deepseek-v4-flash-vision-exp"
            ),
            configuration: TestFixtures.configuration(host: "api.deepseek.com")
        )
        let videoContent = try XCTUnwrap(
            ((try TestFixtures.requestBody(from: videoOnly.urlRequest)["messages"] as? [[String: Any]])?.first?["content"] as? String)
        )
        XCTAssertTrue(videoContent.contains("video 不支持"))
    }

    func testReminderWireRoles() async throws {
        let deepseek = try await createChatRequest(
            query: ChatQuery(
                messages: [.user("hi"), .reminder("Today is 2026-08-05.")],
                model: "deepseek-v4-flash"
            ),
            configuration: TestFixtures.configuration(host: "api.deepseek.com")
        )
        let deepseekMessages = try XCTUnwrap(
            (try TestFixtures.requestBody(from: deepseek.urlRequest)["messages"] as? [[String: Any]])
        )
        XCTAssertEqual(deepseekMessages.last?["role"] as? String, "latest_reminder")

        let openai = try await createChatRequest(
            query: ChatQuery(messages: [.user("hi"), .reminder("Today is 2026-08-05.")], model: "gpt-4o"),
            configuration: TestFixtures.configuration(host: "api.openai.com")
        )
        XCTAssertEqual(
            ((try TestFixtures.requestBody(from: openai.urlRequest)["messages"] as? [[String: Any]])?.last?["role"] as? String),
            "system"
        )

        for host in ["dashscope.aliyuncs.com", "open.bigmodel.cn", "api.minimaxi.com", "api.siliconflow.cn"] {
            let prepared = try await createChatRequest(
                query: ChatQuery(messages: [.user("hi"), .reminder("Today is 2026-08-05.")], model: "m"),
                configuration: TestFixtures.configuration(host: host)
            )
            XCTAssertEqual(
                ((try TestFixtures.requestBody(from: prepared.urlRequest)["messages"] as? [[String: Any]])?.last?["role"] as? String),
                "user",
                host
            )
        }
    }

    func testReminderCodableRoundTrip() throws {
        let message = ChatQuery.ChatCompletionMessageParam.reminder("Locale: en-US")
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ChatQuery.ChatCompletionMessageParam.self, from: data)
        XCTAssertEqual(decoded.role, .latestReminder)
        XCTAssertEqual(decoded.textContent, "Locale: en-US")
    }

    func testResponseFormatCapabilityAndDowngrade() async throws {
        XCTAssertEqual(ProviderFamily.openai.responseFormatCapability, .jsonSchema)
        XCTAssertEqual(ProviderFamily.deepseek.responseFormatCapability, .jsonObject)
        XCTAssertEqual(ProviderFamily.minimax.responseFormatCapability, .none)

        let deepseek = try await createChatRequest(
            query: ChatQuery(
                messages: [.user("hello")],
                model: "deepseek-chat",
                responseFormat: TestFixtures.sampleJsonSchemaFormat()
            ),
            configuration: TestFixtures.configuration(host: "api.deepseek.com")
        )
        let deepseekFormat = try XCTUnwrap(
            (try TestFixtures.requestBody(from: deepseek.urlRequest)["response_format"] as? [String: Any])
        )
        XCTAssertEqual(deepseekFormat["type"] as? String, "json_object")

        let minimax = try await createChatRequest(
            query: ChatQuery(
                messages: [.user("hello")],
                model: "MiniMax-M2.7",
                responseFormat: TestFixtures.sampleJsonSchemaFormat()
            ),
            configuration: TestFixtures.configuration(host: "api.minimaxi.com")
        )
        XCTAssertNil(try TestFixtures.requestBody(from: minimax.urlRequest)["response_format"])

        let openai = try await createChatRequest(
            query: ChatQuery(
                messages: [.user("hello")],
                model: "gpt-4o",
                responseFormat: TestFixtures.sampleJsonSchemaFormat()
            ),
            configuration: TestFixtures.configuration(host: "api.openai.com")
        )
        let openaiFormat = try XCTUnwrap(
            (try TestFixtures.requestBody(from: openai.urlRequest)["response_format"] as? [String: Any])
        )
        XCTAssertEqual(openaiFormat["type"] as? String, "json_schema")

        let moonshotThinking = try await createChatRequest(
            query: ChatQuery(
                messages: [.user("hello")],
                model: "kimi-k2-thinking",
                responseFormat: .jsonObject
            ),
            configuration: TestFixtures.configuration(host: "api.moonshot.cn")
        )
        XCTAssertNil(try TestFixtures.requestBody(from: moonshotThinking.urlRequest)["response_format"])
    }
}
