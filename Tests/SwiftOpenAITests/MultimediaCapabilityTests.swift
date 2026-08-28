import XCTest
@testable import SwiftOpenAI

final class MultimediaCapabilityTests: XCTestCase {

    func testUnknownModelDefaultsToNone() {
        let cap = MultimediaCapabilityResolver.resolve(
            family: .genericOpenAICompatible,
            wireAPI: .completions,
            model: "foo-bar-text"
        )
        XCTAssertEqual(cap, .none)
    }

    func testGlobalImageDiscovery() {
        let cases: [(String, Bool, Bool)] = [
            ("gpt-4o", true, false),
            ("gpt-4o-mini", true, false),
            ("gpt-5.4", true, false),
            ("claude-sonnet-4-20250514", true, false),
            ("claude-3-5-sonnet-latest", true, false),
            ("gemini-2.0-flash", true, true),
            ("gemini-3.5-flash", true, true),
            ("pixtral-12b", true, false),
            ("llava-1.5-7b", true, false),
            ("qwen3-vl-plus", true, true),
            ("zai-org/GLM-4.5V", true, true),
            ("kimi-k3", true, true),
            ("deepseek-v4-flash-vision-exp", true, false),
            ("qwen-plus", false, false),
            ("deepseek-chat", false, false),
            ("gpt-image-1", false, false),
            ("grok-3", false, false),
            ("grok-2-vision", true, false),
            ("grok-4.6", true, false),
            ("qwen3.8-max", true, true),
            ("qwen-3-8-max", true, true),
            ("qwen3.7-plus", true, true),
            ("qwen3.7-max", false, false),
            ("qwen3.6-plus", true, true),
            ("glm-5.3-flash", true, true),
            ("glm-5-3-flash", true, true),
            ("glm-5.3", false, false),
            ("glm-5.2", false, false),
            ("muse-spark-1.2-contributor", true, true),
            ("mimo-v2.5", true, true),
            ("mimo-v2-5", true, true),
            ("mimo-v2.5-pro", false, false),
            ("longcat-2.0", false, false),
            ("hy3", false, false),
            ("llama-4-maverick", true, false),
            ("gemma-4-31b-it", true, true),
            ("o3", true, false),
            ("o3-mini", false, false),
            ("o4-mini", true, false),
            ("us.anthropic.claude-sonnet-5", true, false),
            ("opencode-go/kimi-k3", true, true),
            ("kimi-k2-6", true, true),
            ("deepseek-v4-pro", false, false),
            ("minimax-m2.7", false, false),
            ("ox-alpha-free", true, true),
            ("sonar-pro", true, false),
            ("seed-1.6", true, true),
            ("step-3.7-flash", true, true),
            ("minicpm-v-4.5", true, false),
            ("claude-fable-5", true, false),
            ("gpt-5.3-codex-spark", false, false),
        ]

        for (model, expectImage, expectVideo) in cases {
            let cap = MultimediaCapabilityResolver.resolve(
                family: .genericOpenAICompatible,
                wireAPI: .completions,
                model: model
            )
            XCTAssertEqual(
                cap.supportsImage,
                expectImage,
                "image mismatch for \(model)"
            )
            XCTAssertEqual(
                cap.supportsVideo,
                expectVideo,
                "video mismatch for \(model)"
            )
        }
    }

    func testMiniMaxCompletionsHardGateEvenForM3() {
        let cap = MultimediaCapabilityResolver.resolve(
            family: .minimax,
            wireAPI: .completions,
            model: "MiniMax-M3"
        )
        XCTAssertEqual(cap, .none)

        let onAggregator = MultimediaCapabilityResolver.resolve(
            family: .genericOpenAICompatible,
            wireAPI: .completions,
            model: "minimax-m3"
        )
        XCTAssertEqual(onAggregator, .none)
    }

    func testOpenCodeGoCatalog() {
        let go: [(String, Bool, Bool)] = [
            ("grok-4.6", true, false),
            ("gpt-5.6-luna", true, false),
            ("glm-5.3-flash", true, true),
            ("glm-5.3", false, false),
            ("glm-5.2", false, false),
            ("glm-5.1", false, false),
            ("kimi-k3", true, true),
            ("kimi-k2.7-code", true, true),
            ("kimi-k2.6", true, true),
            ("longcat-2.0", false, false),
            ("mimo-v2.5", true, true),
            ("mimo-v2.5-pro", false, false),
            ("mimo-v2-omni", true, true),
            ("muse-spark-1.2-contributor", true, true),
            ("qwen3.8-max", true, true),
            ("qwen3.8-flash", true, true),
            ("qwen3.7-max", false, false),
            ("qwen3.7-plus", true, true),
            ("qwen3.6-plus", true, true),
            ("deepseek-v4-pro", false, false),
            ("deepseek-v4-flash", false, false),
            ("deepseek-v4-flash-vision-exp", true, false),
            ("hy3", false, false),
            ("ox-alpha-free", true, true),
        ]
        for (model, expectImage, expectVideo) in go {
            let cap = MultimediaCapabilityResolver.resolve(
                family: .genericOpenAICompatible,
                wireAPI: .completions,
                model: model
            )
            XCTAssertEqual(cap.supportsImage, expectImage, "image \(model)")
            XCTAssertEqual(cap.supportsVideo, expectVideo, "video \(model)")
        }

        let m3Anthropic = MultimediaCapabilityResolver.resolve(
            family: .genericOpenAICompatible,
            wireAPI: .anthropic,
            model: "minimax-m3"
        )
        XCTAssertTrue(m3Anthropic.supportsImage)
        XCTAssertTrue(m3Anthropic.supportsVideo)
    }

    func testOpenCodeZenCatalog() {
        let zen: [(String, Bool, Bool)] = [
            ("opencode/gpt-5.5", true, false),
            ("opencode/claude-sonnet-5", true, false),
            ("opencode/gemini-3.7-flash", true, true),
            ("opencode/grok-build-0.1", true, false),
            ("opencode/big-pickle", false, false),
            ("opencode/nemotron-3-ultra-free", false, false),
            ("opencode/mimo-v2.5-free", true, true),
            ("gemini-3.5-flash@eu", true, true),
        ]
        for (model, expectImage, expectVideo) in zen {
            let cap = MultimediaCapabilityResolver.resolve(
                family: .genericOpenAICompatible,
                wireAPI: .completions,
                model: model
            )
            XCTAssertEqual(cap.supportsImage, expectImage, "image \(model)")
            XCTAssertEqual(cap.supportsVideo, expectVideo, "video \(model)")
        }
    }

    func testMiniMaxAnthropicM3AllowsImageAndVideo() {
        let cap = MultimediaCapabilityResolver.resolve(
            family: .minimax,
            wireAPI: .anthropic,
            model: "MiniMax-M3"
        )
        XCTAssertTrue(cap.supportsImage)
        XCTAssertTrue(cap.supportsVideo)

        let m2 = MultimediaCapabilityResolver.resolve(
            family: .minimax,
            wireAPI: .anthropic,
            model: "MiniMax-M2.7"
        )
        XCTAssertEqual(m2, .none)
    }

    func testSameModelAcrossHosts() {
        let openai = MultimediaCapabilityResolver.resolve(
            family: .openai,
            wireAPI: .completions,
            model: "qwen3-vl-plus"
        )
        let silicon = MultimediaCapabilityResolver.resolve(
            family: .genericOpenAICompatible,
            wireAPI: .completions,
            model: "qwen3-vl-plus"
        )
        XCTAssertEqual(openai.supportsImage, silicon.supportsImage)
        XCTAssertTrue(openai.supportsImage)
    }

    func testOpenAICompletionsForcesVideoOff() {
        let cap = MultimediaCapabilityResolver.resolve(
            family: .openai,
            wireAPI: .completions,
            model: "kimi-k3"
        )
        XCTAssertTrue(cap.supportsImage)
        XCTAssertFalse(cap.supportsVideo)
    }

    func testCompletionsStripsUnknownOnGenericHost() async throws {
        let prepared = try await createChatRequest(
            query: ChatQuery(
                messages: [.user("img", imageDatas: TestFixtures.tinyPNG, detail: .high)],
                model: "qwen-plus"
            ),
            configuration: TestFixtures.configuration(baseURL: "https://api.siliconflow.cn/v1")
        )
        let content = try XCTUnwrap(
            ((try TestFixtures.requestBody(from: prepared.urlRequest)["messages"] as? [[String: Any]])?.first?["content"] as? String)
        )
        XCTAssertTrue(content.contains("image 不支持"))
    }

    func testCompletionsKeepsDiscoveredVLOnGenericHost() async throws {
        let prepared = try await createChatRequest(
            query: ChatQuery(
                messages: [.user("img", imageDatas: TestFixtures.tinyPNG, detail: .high)],
                model: "qwen3-vl-plus"
            ),
            configuration: TestFixtures.configuration(baseURL: "https://api.siliconflow.cn/v1")
        )
        let parts = try XCTUnwrap(
            ((try TestFixtures.requestBody(from: prepared.urlRequest)["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]])
        )
        XCTAssertTrue(parts.contains { ($0["type"] as? String) == "image_url" })
    }

    func testMiniMaxCompletionsStripsM3Images() async throws {
        let prepared = try await createChatRequest(
            query: ChatQuery(
                messages: [.user("img", imageDatas: TestFixtures.tinyPNG, detail: .high)],
                model: "MiniMax-M3"
            ),
            configuration: TestFixtures.configuration(baseURL: "https://api.minimaxi.com/v1")
        )
        let content = try XCTUnwrap(
            ((try TestFixtures.requestBody(from: prepared.urlRequest)["messages"] as? [[String: Any]])?.first?["content"] as? String)
        )
        XCTAssertTrue(content.contains("image 不支持"))
    }

    func testAnthropicWireKeepsMiniMaxM3Images() throws {
        let body = try makeAnthropicRequestBody(
            modelID: "MiniMax-M3",
            messages: [.user("img", images: [TestFixtures.tinyPNG], detail: .high)],
            maxCompletionTokens: 256,
            parallelToolCalls: nil,
            stop: nil,
            temperature: nil,
            toolChoice: nil,
            tools: nil,
            topP: nil,
            thinkLevel: nil,
            extraBody: nil,
            baseURL: "https://api.minimaxi.com/anthropic"
        )
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
        XCTAssertTrue(content.contains { ($0["type"] as? String) == "image" })
    }

    func testResponsesDoesNotMapUnsupportedVideoToInputImage() throws {
        let body = try makeResponsesRequestBody(
            modelID: "gpt-4o",
            messages: [.user("vid", videoDatas: TestFixtures.tinyVideo)],
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
            baseURL: "https://api.openai.com/v1",
            wireAPI: .responses
        )
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        let content = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
        XCTAssertFalse(content.contains { ($0["type"] as? String) == "input_image" })
        XCTAssertTrue(
            content.contains {
                ($0["type"] as? String) == "input_text"
                    && (($0["text"] as? String)?.contains("video 不支持") == true)
            }
        )
    }
}
