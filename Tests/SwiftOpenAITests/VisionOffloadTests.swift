import XCTest
@testable import SwiftOpenAI

final class VisionOffloadTests: XCTestCase {

    private let dashScopeBaseURL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
    private let dashScopeModel = "qwen4-max-preview"

    func testDashScopeImageReusesPriorBindingWithoutUpload() async throws {
        let key = MessageContentBlocks.fileBindingKey(
            imageData: TestFixtures.tinyPNG,
            baseURL: dashScopeBaseURL,
            modelID: dashScopeModel
        )
        let prior: [String: FileBinding] = [
            key: FileBinding(
                fileId: "oss://uploads/img/upload.png",
                expiresAt: Date().addingTimeInterval(3600)
            )
        ]
        let messages: [ChatQuery.ChatCompletionMessageParam] = [
            .user("look", images: [TestFixtures.tinyPNG], detail: .high)
        ]
        let offload = try await offloadVisionMediaIfNeeded(
            messages: messages,
            baseURL: dashScopeBaseURL,
            modelID: dashScopeModel,
            bearerToken: "sk-test",
            priorBindings: prior
        )
        guard case .user(let user) = offload.messages.first,
              case .contentParts(let parts) = user.content,
              case .image(let image) = parts.first(where: {
                  if case .image = $0 { return true }
                  return false
              })
        else {
            return XCTFail("expected image part")
        }
        XCTAssertEqual(image.imageUrl.url, "oss://uploads/img/upload.png")
        XCTAssertEqual(image.imageUrl.detail, .high)
        XCTAssertEqual(offload.fileBindings[key]?.fileId, "oss://uploads/img/upload.png")
    }

    func testDashScopeVideoBindingKeyIncludesModelAndKeepsFPS() async throws {
        let sha = ContentBlocksCrypto.sha256Hex(of: TestFixtures.tinyVideo)
        let key = MessageContentBlocks.fileBindingKey(
            sha256Hex: sha,
            baseURL: dashScopeBaseURL,
            modelID: dashScopeModel
        )
        // 文件与模型绑定：不含 modelID 的 key 不得命中。
        XCTAssertNotEqual(
            key,
            MessageContentBlocks.fileBindingKey(sha256Hex: sha, baseURL: dashScopeBaseURL)
        )
        let prior: [String: FileBinding] = [
            key: FileBinding(
                fileId: "oss://uploads/vid/upload.mp4",
                expiresAt: Date().addingTimeInterval(3600)
            )
        ]
        let dataURL = "data:video/mp4;base64,\(TestFixtures.tinyVideo.base64EncodedString())"
        let messages: [ChatQuery.ChatCompletionMessageParam] = [
            .user(
                UserMessageParam(
                    content: .contentParts([
                        .text(.init(text: "watch")),
                        .video(.init(videoUrl: .init(url: dataURL, fps: 2.0)))
                    ])
                )
            )
        ]
        let offload = try await offloadVisionMediaIfNeeded(
            messages: messages,
            baseURL: dashScopeBaseURL,
            modelID: dashScopeModel,
            bearerToken: "sk-test",
            priorBindings: prior
        )
        guard case .user(let user) = offload.messages.first,
              case .contentParts(let parts) = user.content,
              case .video(let video) = parts.first(where: {
                  if case .video = $0 { return true }
                  return false
              })
        else {
            return XCTFail("expected video part")
        }
        XCTAssertEqual(video.videoUrl.url, "oss://uploads/vid/upload.mp4")
        XCTAssertEqual(video.videoUrl.fps, 2.0)
    }

    func testMoonshotVideoRewritesToMsURLAndImagesStayInline() async throws {
        let baseURL = "https://api.moonshot.ai/v1"
        let sha = ContentBlocksCrypto.sha256Hex(of: TestFixtures.tinyVideo)
        let key = MessageContentBlocks.fileBindingKey(sha256Hex: sha, baseURL: baseURL)
        let prior: [String: FileBinding] = [key: FileBinding(fileId: "file-kimi-1")]
        let dataURL = "data:video/mp4;base64,\(TestFixtures.tinyVideo.base64EncodedString())"
        let messages: [ChatQuery.ChatCompletionMessageParam] = [
            .user(
                UserMessageParam(
                    content: .contentParts([
                        .image(.init(imageUrl: .init(imageData: TestFixtures.tinyPNG))),
                        .video(.init(videoUrl: .init(url: dataURL, fps: 2.0)))
                    ])
                )
            )
        ]
        let offload = try await offloadVisionMediaIfNeeded(
            messages: messages,
            baseURL: baseURL,
            modelID: "kimi-k3",
            bearerToken: "sk-test",
            priorBindings: prior
        )
        guard case .user(let user) = offload.messages.first,
              case .contentParts(let parts) = user.content
        else {
            return XCTFail("expected content parts")
        }
        guard case .video(let video) = parts.first(where: {
            if case .video = $0 { return true }
            return false
        }) else {
            return XCTFail("expected video part")
        }
        XCTAssertEqual(video.videoUrl.url, "ms://file-kimi-1")
        // Kimi 图像保留 base64 内联（原生支持 data URI）。
        guard case .image(let image) = parts.first(where: {
            if case .image = $0 { return true }
            return false
        }) else {
            return XCTFail("expected image part")
        }
        XCTAssertTrue(image.imageUrl.url.hasPrefix("data:image/"))
        XCTAssertEqual(offload.fileBindings[key]?.expiresAt, nil)
    }

    func testDashScopeRequestCarriesOssResolveHeader() async throws {
        let dashScope = try await createChatRequest(
            query: ChatQuery(messages: [.user("hi")], model: dashScopeModel),
            configuration: TestFixtures.configuration(baseURL: dashScopeBaseURL)
        )
        XCTAssertEqual(
            dashScope.urlRequest.value(forHTTPHeaderField: "X-DashScope-OssResourceResolve"),
            "enable"
        )

        let tokenPlan = try await createChatRequest(
            query: ChatQuery(messages: [.user("hi")], model: dashScopeModel),
            configuration: TestFixtures.configuration(
                baseURL: "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1"
            )
        )
        XCTAssertEqual(
            tokenPlan.urlRequest.value(forHTTPHeaderField: "X-DashScope-OssResourceResolve"),
            "enable"
        )

        let openai = try await createChatRequest(
            query: ChatQuery(messages: [.user("hi")], model: "gpt-5"),
            configuration: TestFixtures.configuration()
        )
        XCTAssertNil(openai.urlRequest.value(forHTTPHeaderField: "X-DashScope-OssResourceResolve"))
    }
}
