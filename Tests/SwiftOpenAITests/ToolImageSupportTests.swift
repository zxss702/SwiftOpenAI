import XCTest
@testable import SwiftOpenAI

final class ToolImageSupportTests: XCTestCase {
    
    /// 测试创建纯文本tool消息
    func testToolMessageWithTextOnly() throws {
        let message = ChatQuery.ChatCompletionMessageParam.tool(
            "这是处理结果",
            toolCallId: "call_123"
        )
        
        // 验证消息类型
        XCTAssertEqual(message.role, .tool)
        
        // 验证文本内容
        XCTAssertEqual(message.textContent, "这是处理结果")
    }
    
    /// 测试创建带单张图片的tool消息
    func testToolMessageWithSingleImage() throws {
        // 创建一个简单的测试图像数据（1x1 PNG）
        let imageData = Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
            0xDE
        ])
        
        let message = ChatQuery.ChatCompletionMessageParam.tool(
            "这是图像分析结果",
            images: [imageData],
            detail: .high,
            toolCallId: "call_123"
        )
        
        // 验证消息类型
        XCTAssertEqual(message.role, .tool)
        
        // 验证文本内容
        XCTAssertEqual(message.textContent, "这是图像分析结果")
        
        // 验证消息可以编码
        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        XCTAssertFalse(data.isEmpty)
    }
    
    /// 测试创建带多张图片的tool消息
    func testToolMessageWithMultipleImages() throws {
        let image1 = Data([0x89, 0x50, 0x4E, 0x47]) // PNG header
        let image2 = Data([0xFF, 0xD8, 0xFF]) // JPEG header
        
        let message = ChatQuery.ChatCompletionMessageParam.tool(
            "这是多图像分析结果",
            images: [image1, image2],
            toolCallId: "call_456"
        )
        
        // 验证消息类型
        XCTAssertEqual(message.role, .tool)
        
        // 验证文本内容
        XCTAssertEqual(message.textContent, "这是多图像分析结果")
        
        // 验证消息可以编码和解码
        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        
        let decoder = JSONDecoder()
        let decodedMessage = try decoder.decode(ChatQuery.ChatCompletionMessageParam.self, from: data)
        XCTAssertEqual(decodedMessage.role, .tool)
        XCTAssertEqual(decodedMessage.textContent, "这是多图像分析结果")
    }
    
    /// 测试创建仅包含图片的tool消息
    func testToolMessageWithImageOnly() throws {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47]) // PNG header
        
        let message = ChatQuery.ChatCompletionMessageParam.tool(
            images: [imageData],
            toolCallId: "call_789"
        )
        
        // 验证消息类型
        XCTAssertEqual(message.role, .tool)
        
        // 验证消息可以编码
        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        XCTAssertFalse(data.isEmpty)
    }
    
    /// 测试数组扩展方法添加带图片的tool消息
    func testArrayExtensionWithImages() throws {
        var messages: [ChatQuery.ChatCompletionMessageParam] = []
        
        messages.addSystemMessage("你是一个有用的助手")
        messages.addUserMessage("请处理这个任务")
        
        let imageData = Data([0x89, 0x50, 0x4E, 0x47]) // PNG header
        
        messages.addToolMessageWithImages(
            "任务完成，这是结果图像",
            imageDatas: [imageData],
            detail: .auto,
            toolCallId: "call_123"
        )
        
        XCTAssertEqual(messages.count, 3)
        XCTAssertEqual(messages[0].role, .system)
        XCTAssertEqual(messages[1].role, .user)
        XCTAssertEqual(messages[2].role, .tool)
        XCTAssertEqual(messages[2].textContent, "任务完成，这是结果图像")
    }
    
    /// 测试tool消息的JSON编码格式
    func testToolMessageJSONEncoding() throws {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47]) // PNG header
        
        let message = ChatQuery.ChatCompletionMessageParam.tool(
            "分析结果",
            images: [imageData],
            toolCallId: "call_123"
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(message)
        let json = String(data: data, encoding: .utf8)!
        
        // 验证JSON包含必要的字段
        XCTAssertTrue(json.contains("\"role\" : \"tool\""))
        XCTAssertTrue(json.contains("\"tool_call_id\" : \"call_123\""))
        XCTAssertTrue(json.contains("\"type\" : \"text\""))
        XCTAssertTrue(json.contains("\"type\" : \"image_url\""))
        
        print("Tool message with image JSON:")
        print(json)
    }
    
    /// 测试完整的对话流程（包括tool消息中的图片）
    func testCompleteConversationFlow() throws {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47]) // PNG header
        
        let messages: [ChatQuery.ChatCompletionMessageParam] = [
            .system("你是一个有用的助手，可以处理图像。"),
            .user("请分析这张图片"),
            .assistant("", toolCalls: [
                AssistantMessageParam.ToolCallParam(
                    id: "call_123",
                    function: AssistantMessageParam.ToolCallParam.FunctionCall(
                        name: "analyze_image",
                        arguments: "{\"image_url\": \"example.jpg\"}"
                    )
                )
            ]),
            .tool(
                "这是图像分析的结果，附带了处理后的图像。",
                images: [imageData],
                detail: .high,
                toolCallId: "call_123"
            )
        ]
        
        XCTAssertEqual(messages.count, 4)
        XCTAssertEqual(messages[3].role, .tool)
        
        // 验证整个对话可以被编码
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(messages)
        XCTAssertFalse(data.isEmpty)
        
        // 打印JSON以供验证
        if let json = String(data: data, encoding: .utf8) {
            print("Complete conversation with tool image:")
            print(json)
        }
    }
}

