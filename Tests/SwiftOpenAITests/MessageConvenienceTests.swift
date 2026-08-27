import XCTest
@testable import SwiftOpenAI

final class MessageConvenienceTests: XCTestCase {

    func testBasicMessageFactories() {
        XCTAssertEqual(OpenAIMessage.system("sys").role, .system)
        XCTAssertEqual(OpenAIMessage.system("sys").textContent, "sys")
        XCTAssertEqual(OpenAIMessage.user("hi").textContent, "hi")
        XCTAssertEqual(OpenAIMessage.assistant("ok").textContent, "ok")
        XCTAssertEqual(OpenAIMessage.tool("result", toolCallId: "call_1").role, .tool)
        XCTAssertEqual(OpenAIMessage.tool("result", toolCallId: "call_1").textContent, "result")
        XCTAssertEqual(OpenAIMessage.reminder("note").role, .latestReminder)
    }

    func testUserMessageWithImages() throws {
        let message = OpenAIMessage.user("分析图片", images: [TestFixtures.tinyPNG], detail: .high)
        XCTAssertEqual(message.role, .user)
        XCTAssertEqual(message.textContent, "分析图片")
        let data = try JSONEncoder().encode(message)
        XCTAssertFalse(data.isEmpty)
    }

    func testToolMessageWithImagesRoundTrip() throws {
        let message = OpenAIMessage.tool(
            "图像结果",
            images: [TestFixtures.tinyPNG, Data([0xFF, 0xD8, 0xFF])],
            detail: .low,
            toolCallId: "call_456"
        )
        XCTAssertEqual(message.role, .tool)
        XCTAssertEqual(message.textContent, "图像结果")

        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(OpenAIMessage.self, from: encoded)
        XCTAssertEqual(decoded.role, .tool)
        XCTAssertEqual(decoded.textContent, "图像结果")
    }

    func testToolMessageImageOnlyEncodes() throws {
        let message = OpenAIMessage.tool(images: [TestFixtures.tinyPNG], toolCallId: "call_789")
        XCTAssertEqual(message.role, .tool)
        let data = try JSONEncoder().encode(message)
        XCTAssertFalse(data.isEmpty)
    }

    func testArrayMessageHelpers() {
        var messages: [OpenAIMessage] = []
        messages.addSystemMessage("系统")
        messages.addUserMessage("用户")
        messages.addAssistantMessage("助手")
        messages.addToolMessageWithImages(
            "工具结果",
            imageDatas: [TestFixtures.tinyPNG],
            detail: .auto,
            toolCallId: "call_123"
        )

        XCTAssertEqual(messages.count, 4)
        XCTAssertEqual(messages[0].role, .system)
        XCTAssertEqual(messages[1].role, .user)
        XCTAssertEqual(messages[2].role, .assistant)
        XCTAssertEqual(messages[3].role, .tool)
        XCTAssertEqual(messages[3].textContent, "工具结果")
    }

    func testAssistantWithToolCalls() {
        let message = OpenAIMessage.assistant(
            "calling",
            toolCalls: [
                .init(id: "call_1", function: .init(name: "fn", arguments: "{}"))
            ]
        )
        XCTAssertEqual(message.toolCalls?.count, 1)
        XCTAssertEqual(message.toolCalls?.first?.function.name, "fn")
    }
}
