import XCTest
@testable import SwiftOpenAI

final class DeepSeekContentBlocksTests: XCTestCase {

    func testMessageContentBlocksRoundTripUsesContentBlocksKey() throws {
        let blocks = MessageContentBlocks(
            anthropic: [["type": .string("thinking"), "thinking": .string("hmm")]],
            fileBindings: [
                "abc123": FileBinding(
                    fileId: "file-api-1",
                    expiresAt: Date(timeIntervalSince1970: 1_700_000_000),
                    filename: "a.png",
                    byteCount: 12
                )
            ]
        )
        let data = try JSONEncoder().encode(blocks)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["anthropic"])
        XCTAssertNotNil(json["file_bindings"])
        XCTAssertNil(json["fileBindings"])

        let decoded = try JSONDecoder().decode(MessageContentBlocks.self, from: data)
        XCTAssertEqual(decoded.fileBindings?["abc123"]?.fileId, "file-api-1")
        XCTAssertEqual(decoded.anthropic?.first?["type"], .string("thinking"))
    }

    func testAssistantMessageEncodesContentBlocksNotLegacyKey() throws {
        let assistant = AssistantMessageParam(
            content: "hi",
            contentBlocks: MessageContentBlocks(
                fileBindings: ["deadbeef": FileBinding(fileId: "file-api-x")]
            )
        )
        let data = try JSONEncoder().encode(assistant)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["content_blocks"])
        XCTAssertNil(json["anthropic_content_blocks"])
    }

    func testSha256StableAndFileBindingExpiry() {
        let data = TestFixtures.tinyPNG
        let a = ContentBlocksCrypto.sha256Hex(of: data)
        let b = ContentBlocksCrypto.sha256Hex(of: data)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 64)

        let usable = FileBinding(fileId: "f1", expiresAt: Date().addingTimeInterval(3600))
        XCTAssertTrue(usable.isUsable())
        let expired = FileBinding(fileId: "f2", expiresAt: Date().addingTimeInterval(-120))
        XCTAssertFalse(expired.isUsable())
    }

    func testFileBindingKeyAppendsVendorBasePath() {
        let sha = ContentBlocksCrypto.sha256Hex(of: TestFixtures.tinyPNG)
        let deepseek = MessageContentBlocks.fileBindingKey(
            sha256Hex: sha,
            baseURL: "https://api.deepseek.com/v1"
        )
        let openai = MessageContentBlocks.fileBindingKey(
            sha256Hex: sha,
            baseURL: "https://api.openai.com/v1"
        )
        XCTAssertEqual(deepseek, sha + "api.deepseek.com/v1")
        XCTAssertEqual(openai, sha + "api.openai.com/v1")
        XCTAssertNotEqual(deepseek, openai)
        XCTAssertEqual(
            MessageContentBlocks.fileBindingBasePath(from: "https://api.deepseek.com"),
            "api.deepseek.com"
        )
    }

    func testAggregatedFileBindingsFromAssistantHistory() {
        let messages: [ChatQuery.ChatCompletionMessageParam] = [
            .user("u"),
            .assistant(
                "a1",
                contentBlocks: MessageContentBlocks(
                    fileBindings: ["h1": FileBinding(fileId: "file-1")]
                )
            ),
            .assistant(
                "a2",
                contentBlocks: MessageContentBlocks(
                    fileBindings: [
                        "h1": FileBinding(fileId: "file-1-updated"),
                        "h2": FileBinding(fileId: "file-2")
                    ]
                )
            )
        ]
        let merged = MessageContentBlocks.aggregatedFileBindings(from: messages)
        XCTAssertEqual(merged["h1"]?.fileId, "file-1-updated")
        XCTAssertEqual(merged["h2"]?.fileId, "file-2")
    }

    func testOffloadRewritesDataURLToFileIdUsingPriorBindingsWithoutUpload() async throws {
        let baseURL = "https://api.deepseek.com/v1"
        let key = MessageContentBlocks.fileBindingKey(
            imageData: TestFixtures.tinyPNG,
            baseURL: baseURL
        )
        let prior: [String: FileBinding] = [
            key: FileBinding(fileId: "file-api-reuse", expiresAt: Date().addingTimeInterval(3600))
        ]
        let messages: [ChatQuery.ChatCompletionMessageParam] = [
            .user("look", images: [TestFixtures.tinyPNG], detail: .auto)
        ]
        let offload = try await offloadDeepSeekVisionImagesIfNeeded(
            messages: messages,
            baseURL: baseURL,
            modelID: "deepseek-v4-flash-vision-exp",
            bearerToken: "token",
            priorBindings: prior,
            extraHeaders: nil
        )
        guard case .user(let user) = offload.messages.first,
              case .contentParts(let parts) = user.content,
              case .file(let file) = parts.first(where: {
                  if case .file = $0 { return true }
                  return false
              })
        else {
            return XCTFail("expected file part")
        }
        XCTAssertEqual(file.fileId, "file-api-reuse")
        XCTAssertEqual(offload.fileBindings[key]?.fileId, "file-api-reuse")
    }

    func testOffloadSkippedForNonDeepSeekOrNonVision() async throws {
        let messages: [ChatQuery.ChatCompletionMessageParam] = [
            .user("look", images: [TestFixtures.tinyPNG], detail: .auto)
        ]
        let openai = try await offloadDeepSeekVisionImagesIfNeeded(
            messages: messages,
            baseURL: "https://api.openai.com/v1",
            modelID: "deepseek-v4-flash-vision-exp",
            bearerToken: "token",
            priorBindings: [:],
            extraHeaders: nil
        )
        guard case .user(let user) = openai.messages.first,
              case .contentParts(let parts) = user.content,
              case .image = parts.first
        else {
            return XCTFail("expected image part unchanged")
        }

        let nonVision = try await offloadDeepSeekVisionImagesIfNeeded(
            messages: messages,
            baseURL: "https://api.deepseek.com/v1",
            modelID: "deepseek-chat",
            bearerToken: "token",
            priorBindings: [:],
            extraHeaders: nil
        )
        guard case .user(let user2) = nonVision.messages.first,
              case .contentParts(let parts2) = user2.content,
              case .image = parts2.first
        else {
            return XCTFail("expected image part unchanged for non-vision")
        }
    }

    func testCompletionsEncodeFileIdPart() async throws {
        let prepared = try await createChatRequest(
            query: ChatQuery(
                messages: [
                    .user(
                        UserMessageParam(
                            content: .contentParts([
                                .text(.init(text: "see")),
                                .file(.init(fileId: "file-api-xyz"))
                            ])
                        )
                    )
                ],
                model: "deepseek-v4-flash-vision-exp"
            ),
            configuration: TestFixtures.configuration(baseURL: "https://api.deepseek.com/v1")
        )
        let body = try TestFixtures.requestBody(from: prepared.urlRequest)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
        let filePart = try XCTUnwrap(content.first { ($0["type"] as? String) == "file" })
        XCTAssertEqual(filePart["file_id"] as? String, "file-api-xyz")
        XCTAssertFalse(
            content.contains { ($0["image_url"] as? [String: Any])?["url"] as? String != nil
                && (($0["image_url"] as? [String: Any])?["url"] as? String)?.hasPrefix("data:") == true }
        )
    }

    func testResponsesEncodeInputImageFileId() throws {
        let body = try makeResponsesRequestBody(
            modelID: "deepseek-v4-flash-vision-exp",
            messages: [
                .user(
                    UserMessageParam(
                        content: .contentParts([
                            .file(.init(fileId: "file-api-resp"))
                        ])
                    )
                )
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
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        let message = try XCTUnwrap(input.first)
        let content = try XCTUnwrap(message["content"] as? [[String: Any]])
        let image = try XCTUnwrap(content.first)
        XCTAssertEqual(image["type"] as? String, "input_image")
        XCTAssertEqual(image["file_id"] as? String, "file-api-resp")
        XCTAssertNil(image["image_url"])
    }

    func testBodyPreflightThrowsForDeepSeekOverLimit() {
        let huge = Data(repeating: 0x41, count: deepSeekRequestBodyLimitBytes)
        XCTAssertThrowsError(
            try assertRequestBodyWithinDeepSeekLimitIfNeeded(
                body: huge,
                baseURL: "https://api.deepseek.com/v1"
            )
        ) { error in
            guard case OpenAIError.requestBodyTooLarge = error else {
                return XCTFail("expected requestBodyTooLarge, got \(error)")
            }
        }

        XCTAssertNoThrow(
            try assertRequestBodyWithinDeepSeekLimitIfNeeded(
                body: huge,
                baseURL: "https://api.openai.com/v1"
            )
        )
    }

    func testMapDeepSeekBodyLimitError() {
        let mapped = mapDeepSeekBodyLimitError(
            message: "Failed to buffer the request body: length limit exceeded",
            code: 413
        )
        guard case OpenAIError.requestBodyTooLarge = mapped else {
            return XCTFail("expected requestBodyTooLarge")
        }
        let other = mapDeepSeekBodyLimitError(message: "not found", code: 404)
        guard case OpenAIError.invalidResponse(_, let code) = other else {
            return XCTFail("expected invalidResponse")
        }
        XCTAssertEqual(code, 404)
    }

    func testAppendFilesPath() throws {
        XCTAssertEqual(
            try APIBaseURL.appendFiles(to: "https://api.deepseek.com").absoluteString,
            "https://api.deepseek.com/v1/files"
        )
        XCTAssertEqual(
            try APIBaseURL.appendFiles(to: "https://api.deepseek.com/v1").absoluteString,
            "https://api.deepseek.com/v1/files"
        )
        XCTAssertEqual(
            try APIBaseURL.appendFiles(to: "https://api.deepseek.com/v1/files").absoluteString,
            "https://api.deepseek.com/v1/files"
        )
    }
}
