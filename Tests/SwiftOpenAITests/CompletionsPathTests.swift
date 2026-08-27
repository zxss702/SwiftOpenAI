import XCTest
@testable import SwiftOpenAI

final class CompletionsPathTests: XCTestCase {

    func testAppendsChatCompletionsOnce() async throws {
        let query = ChatQuery(messages: [.user("hello")], model: "glm-4.5")
        let prepared = try await createChatRequest(
            query: query,
            configuration: TestFixtures.configuration(
                baseURL: "https://open.bigmodel.cn/api/coding/paas/v4"
            )
        )
        XCTAssertEqual(prepared.urlRequest.url?.path, "/api/coding/paas/v4/chat/completions")

        let prebuilt = try await createChatRequest(
            query: query,
            configuration: TestFixtures.configuration(
                baseURL: "https://open.bigmodel.cn/api/coding/paas/v4/chat/completions"
            )
        )
        XCTAssertEqual(prebuilt.urlRequest.url?.path, "/api/coding/paas/v4/chat/completions")
    }

    func testDeepSeekStrictToolSwitchesToBeta() async throws {
        let query = ChatQuery(
            messages: [.user("hello")],
            model: "deepseek-v4-pro",
            tools: [TestFixtures.weatherTool(strict: true)]
        )

        let defaultPrepared = try await createChatRequest(
            query: query,
            configuration: OpenAIConfiguration(
                token: "test-token",
                baseURL: "https://api.deepseek.com"
            )
        )
        XCTAssertEqual(defaultPrepared.urlRequest.url?.path, "/beta/chat/completions")

        let v1Prepared = try await createChatRequest(
            query: query,
            configuration: TestFixtures.configuration(baseURL: "https://api.deepseek.com/v1")
        )
        XCTAssertEqual(v1Prepared.urlRequest.url?.path, "/beta/chat/completions")

        let customPrepared = try await createChatRequest(
            query: query,
            configuration: TestFixtures.configuration(baseURL: "https://api.deepseek.com/custom")
        )
        XCTAssertEqual(customPrepared.urlRequest.url?.path, "/custom/chat/completions")
    }

    func testDeepSeekWithoutStrictKeepsV1() async throws {
        let prepared = try await createChatRequest(
            query: ChatQuery(
                messages: [.user("hello")],
                model: "deepseek-v4-pro",
                tools: [TestFixtures.weatherTool(strict: false)]
            ),
            configuration: TestFixtures.configuration(baseURL: "https://api.deepseek.com/v1")
        )
        XCTAssertEqual(prepared.urlRequest.url?.path, "/v1/chat/completions")
    }

    func testEmptyPathInjectsV1ChatCompletions() throws {
        let url = try APIBaseURL.appendChatCompletions(to: "https://api.deepseek.com")
        XCTAssertEqual(url.absoluteString, "https://api.deepseek.com/v1/chat/completions")
    }
}
