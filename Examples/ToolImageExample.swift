import Foundation
import SwiftOpenAI

/// 这个示例展示了如何在Tool消息中使用图像，就像在User消息中一样
/// 
/// 使用方法：
/// 
/// 1. 纯文本Tool消息（现有功能）：
/// ```swift
/// let message = ChatCompletionMessageParam.tool(
///     "这是处理结果",
///     toolCallId: "call_123"
/// )
/// ```
/// 
/// 2. 带图像的Tool消息（新功能）：
/// ```swift
/// let imageData = try! Data(contentsOf: URL(fileURLWithPath: "path/to/image.jpg"))
/// let message = ChatCompletionMessageParam.tool(
///     "这是图像分析结果",
///     images: [imageData],
///     detail: .high,
///     toolCallId: "call_123"
/// )
/// ```
/// 
/// 3. 多图像Tool消息：
/// ```swift
/// let image1 = try! Data(contentsOf: URL(fileURLWithPath: "path/to/image1.jpg"))
/// let image2 = try! Data(contentsOf: URL(fileURLWithPath: "path/to/image2.jpg"))
/// let message = ChatCompletionMessageParam.tool(
///     "这是多图像分析结果",
///     images: [image1, image2],
///     toolCallId: "call_123"
/// )
/// ```
/// 
/// 4. 仅包含图像的Tool消息：
/// ```swift
/// let imageData = try! Data(contentsOf: URL(fileURLWithPath: "path/to/image.jpg"))
/// let message = ChatCompletionMessageParam.tool(
///     images: [imageData],
///     toolCallId: "call_123"
/// )
/// ```

func exampleToolImageUsage() async throws {
    let openAI = OpenAI(configuration: OpenAIConfiguration(
        token: "your-api-key",
        host: "api.openai.com"
    ))
    
    // 假设有一个工具调用需要返回图像
    let toolCallId = "call_abc123"
    
    // 示例：从文件加载图像
    // let imageData = try Data(contentsOf: URL(fileURLWithPath: "result.jpg"))
    
    // 示例：创建一个简单的测试图像数据（1x1 PNG）
    let imageData = Data([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
        0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
        0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
        0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D,
        0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
        0x44, 0xAE, 0x42, 0x60, 0x82
    ])
    
    let messages: [ChatCompletionMessageParam] = [
        .system("你是一个有用的助手，可以处理图像。"),
        .user("请分析这张图片"),
        .assistant("", toolCalls: [
            AssistantMessageParam.ToolCallParam(
                id: toolCallId,
                function: AssistantMessageParam.ToolCallParam.FunctionCall(
                    name: "analyze_image",
                    arguments: "{\"image_url\": \"example.jpg\"}"
                )
            )
        ]),
        // 这里是新功能：Tool消息可以包含图像
        .tool(
            "这是图像分析的结果，附带了处理后的图像。",
            images: [imageData],
            detail: .high,
            toolCallId: toolCallId
        )
    ]
    
    let query = ChatQuery(
        messages: messages,
        model: "gpt-4o"
    )
    
    let result = try await openAI.chats(query: query)
    print("结果: \(result.choices.first?.message.content ?? "无内容")")
}

// 使用数组扩展方法的示例
func exampleWithArrayExtension() {
    var messages: [ChatCompletionMessageParam] = []
    
    messages.addSystemMessage("你是一个有用的助手")
    messages.addUserMessage("请处理这个任务")
    
    // 创建测试图像数据
    let imageData = Data([0x89, 0x50, 0x4E, 0x47]) // PNG header
    
    // 使用新的数组扩展方法添加带图像的tool消息
    messages.addToolMessageWithImages(
        "任务完成，这是结果图像",
        imageDatas: [imageData],
        detail: .auto,
        toolCallId: "call_123"
    )
    
    print("消息数量: \(messages.count)")
}

