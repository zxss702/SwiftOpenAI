import XCTest
@testable import SwiftOpenAI

// MARK: - 测试工具定义
@SYToolArgs
struct TestToolArgs {
    let message: String
    let count: Int?
    let tt: [String]
    let kt: DocumentedTestStruct2
    let kt2: DocumentedTestStruct2
}

@SYTool
struct BasicTestTool {
    let name: String = "basic_test_tool"
    let description: String = "基础测试工具"
    let parameters = TestToolArgs.self
}

@AIModelSchema
struct TestResponse {
    let success: Bool
    let message: String
}

/// Test enumeration for validation
@AIModelSchema
enum TestEnum: String, CaseIterable {
    /// First option
    case option1
    /// Second option  
    case option2
    /// Third option
    case option3
}

/// Test structure with documentation
@AIModelSchema
struct DocumentedTestStruct {
    /// The name field
    let name: String
    /// The age field
    let age: Int
    /// Optional description
    let description: String?
    /// List of tags
    let tags: [String]?
}

@SYToolArgs
struct DocumentedTestStruct2 {
    /// The name field
    let name: String
    /// The age field
    let age: Int
    /// Optional description
    let description: String?
    /// List of tags
    let tags: [String]?
}

final class SwiftOpenAITests: XCTestCase {
    
    func testChatQueryCreation() throws {
        // 使用新的便捷方法创建消息
        let messages: [OpenAIMessage] = [
            .user("Hello"),
            .system("You are a helpful assistant")
        ]
        
        let query = ChatQuery(
            messages: messages,
            model: "gpt-4",
            temperature: 0.7,
            stream: true
        )
        
        XCTAssertEqual(query.model, "gpt-4")
        XCTAssertEqual(query.temperature, 0.7)
        XCTAssertEqual(query.stream, true)
        XCTAssertEqual(query.messages.count, 2)
        XCTAssertEqual(query.messages.first?.role, .user)
        XCTAssertEqual(query.messages.last?.role, .system)
    }
    
    func testConvenientMessageCreation() throws {
        // 测试便捷的静态方法
        let userMessage = OpenAIMessage.user("Hello, world!")
        let systemMessage = OpenAIMessage.system("You are an AI assistant.")
        let assistantMessage = OpenAIMessage.assistant("Hi there!")
        let toolMessage = OpenAIMessage.tool(ToolMessageParam(content: .textContent("Tool result"), toolCallId: "call_123"))
        
        XCTAssertEqual(userMessage.role, .user)
        XCTAssertEqual(systemMessage.role, .system)
        XCTAssertEqual(assistantMessage.role, .assistant)
        XCTAssertEqual(toolMessage.role, .tool)
        
        // 测试文本内容访问
        XCTAssertEqual(userMessage.textContent, "Hello, world!")
        XCTAssertEqual(systemMessage.textContent, "You are an AI assistant.")
        XCTAssertEqual(assistantMessage.textContent, "Hi there!")
        XCTAssertEqual(toolMessage.textContent, "Tool result")
    }
    
    func testArrayConvenienceMethods() throws {
        var messages: [OpenAIMessage] = []
        
        // 测试数组便捷方法
        messages.addSystemMessage("System prompt")
        messages.addUserMessage("User message", name: "user1")
        messages.addAssistantMessage("Assistant response")
        messages.addToolMessage("Tool response", toolCallId: "call_456")
        
        XCTAssertEqual(messages.count, 4)
        XCTAssertEqual(messages[0].role, .system)
        XCTAssertEqual(messages[1].role, .user)
        XCTAssertEqual(messages[2].role, .assistant)
        XCTAssertEqual(messages[3].role, .tool)
        
        // 测试名称
        XCTAssertEqual(messages[1].name, "user1")
    }
    
    func testAIModelInfoConfiguration() throws {
        let modelInfo = AIModelInfoValue(
            token: "test-token",
            host: "api.example.com",
            port: 443,
            scheme: "https",
            basePath: "/v1",
            modelID: "test-model"
        )
        
        XCTAssertEqual(modelInfo.token, "test-token")
        XCTAssertEqual(modelInfo.host, "api.example.com")
        XCTAssertEqual(modelInfo.port, 443)
        XCTAssertEqual(modelInfo.scheme, "https")
        XCTAssertEqual(modelInfo.basePath, "/v1")
        XCTAssertEqual(modelInfo.modelID, "test-model")
        
        let url = modelInfo.baseURL
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.scheme, "https")
        XCTAssertEqual(url?.host, "api.example.com")
        XCTAssertEqual(url?.port, 443)
        XCTAssertEqual(url?.path, "/v1")
    }
    
    func testToolDefinition() {
        let tool = BasicTestTool()
        print(tool.asChatCompletionTool)
        XCTAssertEqual(tool.name, "basic_test_tool")
        XCTAssertEqual(tool.description, "基础测试工具")
        
        // 测试工具转换为ChatCompletionToolParam
        let chatTool = tool.asChatCompletionTool
        XCTAssertEqual(chatTool.type, "function")
        XCTAssertEqual(chatTool.function.name, "basic_test_tool")
        XCTAssertEqual(chatTool.function.description, "基础测试工具")
        XCTAssertNotNil(chatTool.function.parameters)
    }
    
    func testOpenAIConfiguration() {
        let config = OpenAIConfiguration(
            token: "test-token",
            host: "custom.api.com",
            organizationID: "org-123"
        )
        
        XCTAssertEqual(config.token, "test-token")
        XCTAssertEqual(config.host, "custom.api.com")
        XCTAssertEqual(config.organizationID, "org-123")
        
        let url = config.baseURL
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.host, "custom.api.com")
        XCTAssertEqual(url?.scheme, "https")
    }
    
    func testChatStreamResultDecoding() throws {
        let jsonString = """
        {
            "id": "chatcmpl-123",
            "object": "chat.completion.chunk",
            "created": 1677652288,
            "model": "gpt-4",
            "choices": [{
                "index": 0,
                "delta": {
                    "role": "assistant",
                    "content": "Hello"
                }
            }]
        }
        """
        
        let data = jsonString.data(using: .utf8)!
        let result = try JSONDecoder().decode(ChatStreamResult.self, from: data)
        
        XCTAssertEqual(result.id, "chatcmpl-123")
        XCTAssertEqual(result.model, "gpt-4")
        XCTAssertEqual(result.choices.count, 1)
        XCTAssertEqual(result.choices.first?.delta.content, "Hello")
        XCTAssertEqual(result.choices.first?.delta.role, "assistant")
    }
    
    func testOpenAISendMessageValueHelper() async {
        let helper = OpenAISendMessageValueHelper()
        
        let initialText = await helper.fullText
        let initialThinkingText = await helper.fullThinkingText
        let initialCount = await helper.allToolCalls.count
        let initialPendingDelta = await helper.hasPendingDelta()
        
        XCTAssertEqual(initialText, "")
        XCTAssertEqual(initialThinkingText, "")
        XCTAssertEqual(initialCount, 0)
        XCTAssertFalse(initialPendingDelta)
        
        await helper.setText(thinkingText: "Thinking...", text: "Hello")
        let fullText1 = await helper.fullText
        let fullThinkingText1 = await helper.fullThinkingText
        let pendingDelta1 = await helper.hasPendingDelta()
        XCTAssertEqual(fullText1, "Hello")
        XCTAssertEqual(fullThinkingText1, "Thinking...")
        XCTAssertTrue(pendingDelta1)
        
        let toolCall = ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall(
            index: 0,
            id: "call_123",
            type: "function"
        )
        await helper.appendAllToolCalls(toolCall)
        let toolCallsCount1 = await helper.allToolCalls.count
        XCTAssertEqual(toolCallsCount1, 1)
        
        await helper.reset()
        let fullText2 = await helper.fullText
        let fullThinkingText2 = await helper.fullThinkingText
        let toolCallsCount2 = await helper.allToolCalls.count
        let pendingDelta2 = await helper.hasPendingDelta()
        XCTAssertEqual(fullText2, "")
        XCTAssertEqual(fullThinkingText2, "")
        XCTAssertEqual(toolCallsCount2, 0)
        XCTAssertFalse(pendingDelta2)
    }

    func testOpenAISendMessageValueHelperParsesThinkTagsFromContent() async {
        let helper = OpenAISendMessageValueHelper()

        await helper.setText(thinkingText: "", text: "<think>先思考</think>再回答")
        await helper.finalizePendingTaggedText()
        let result = await helper.getResult()

        XCTAssertEqual(result.subThinkingText, "先思考")
        XCTAssertEqual(result.subText, "再回答")
        XCTAssertEqual(result.fullThinkingText, "先思考")
        XCTAssertEqual(result.fullText, "再回答")
    }

    func testOpenAISendMessageValueHelperParsesSplitThinkTagsAcrossChunks() async {
        let helper = OpenAISendMessageValueHelper()

        await helper.setText(thinkingText: "", text: "<thi")
        await helper.setText(thinkingText: "", text: "nk>推理")
        var result = await helper.getResult()
        XCTAssertEqual(result.subThinkingText, "推理")
        XCTAssertEqual(result.subText, "")

        await helper.setText(thinkingText: "", text: "中</th")
        result = await helper.getResult()
        XCTAssertEqual(result.subThinkingText, "中")
        XCTAssertEqual(result.subText, "")

        await helper.setText(thinkingText: "", text: "ink>答案")
        await helper.finalizePendingTaggedText()
        result = await helper.getResult()
        XCTAssertEqual(result.subThinkingText, "")
        XCTAssertEqual(result.subText, "答案")
        XCTAssertEqual(result.fullThinkingText, "推理中")
        XCTAssertEqual(result.fullText, "答案")
    }
    
    func testErrorTypes() {
        let errors: [OpenAIError] = [
            .missingModelID,
            .invalidURL,
            .missingToken,
            .networkError(URLError(.badURL)),
            .decodingError(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "test"))),
            .streamingError("test error"),
            .invalidResponse("测试错误响应")
        ]
        
        XCTAssertEqual(errors.count, 7)
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
        }
    }
    
    func testResponseFormatCreation() {
        let schemaString = """
        {
            "type": "object",
            "properties": {
                "name": {"type": "string"},
                "age": {"type": "integer"}
            },
            "required": ["name"]
        }
        """
        
        let jsonSchema = ChatQuery.ResponseFormat.JSONSchema(
            name: "person",
            description: "Person object",
            schema: schemaString
        )
        
        let responseFormat = ChatQuery.ResponseFormat(
            type: "json_object",
            jsonSchema: jsonSchema
        )
        
        XCTAssertEqual(responseFormat.type, "json_object")
        XCTAssertEqual(responseFormat.jsonSchema?.name, "person")
        XCTAssertEqual(responseFormat.jsonSchema?.description, "Person object")
        XCTAssertEqual(responseFormat.jsonSchema?.schema, schemaString)
    }
    
    func testStopParameterEncodingDecoding() throws {
        // 测试字符串类型的stop
        let stringStop = ChatQuery.Stop.string("stop")
        let stringData = try JSONEncoder().encode(stringStop)
        let decodedStringStop = try JSONDecoder().decode(ChatQuery.Stop.self, from: stringData)
        
        if case let .string(value) = decodedStringStop {
            XCTAssertEqual(value, "stop")
        } else {
            XCTFail("应该解码为字符串类型")
        }
        
        // 测试数组类型的stop
        let arrayStop = ChatQuery.Stop.array(["stop1", "stop2"])
        let arrayData = try JSONEncoder().encode(arrayStop)
        let decodedArrayStop = try JSONDecoder().decode(ChatQuery.Stop.self, from: arrayData)
        
        if case let .array(values) = decodedArrayStop {
            XCTAssertEqual(values, ["stop1", "stop2"])
        } else {
            XCTFail("应该解码为数组类型")
        }
    }
    
    func testDocumentedSchemaGeneration() throws {
        // 测试带文档注释的结构体schema生成
        let schema = DocumentedTestStruct.outputSchema
        
        XCTAssertFalse(schema.isEmpty)
        XCTAssertTrue(schema.contains("Test structure with documentation"))
        XCTAssertTrue(schema.contains("The name field"))
        XCTAssertTrue(schema.contains("The age field"))
        XCTAssertTrue(schema.contains("Optional description"))
        XCTAssertTrue(schema.contains("List of tags"))
        
        // 验证JSON格式
        let jsonData = Data(schema.utf8)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: jsonData))
    }
    
    func testEnumWithDocumentationSchema() throws {
        // 测试带文档注释的枚举schema生成
        let schema = TestEnum.outputSchema
        
        XCTAssertFalse(schema.isEmpty)
        XCTAssertTrue(schema.contains("Test enumeration for validation"))
        XCTAssertTrue(schema.contains("option1"))
        XCTAssertTrue(schema.contains("option2"))
        XCTAssertTrue(schema.contains("option3"))
        
        // 验证JSON格式
        let jsonData = Data(schema.utf8)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: jsonData))
    }
    
    func testMacroGeneratedSchema() throws {
        // 测试宏生成的schema是否包含必要的字段
        let schema = TestResponse.outputSchema
        
        XCTAssertFalse(schema.isEmpty)
        XCTAssertTrue(schema.contains("\"type\":\"object\""))
        XCTAssertTrue(schema.contains("success"))
        XCTAssertTrue(schema.contains("message"))
        XCTAssertTrue(schema.contains("\"required\""))
        
        // 验证JSON格式
        let jsonData = Data(schema.utf8)
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        
        XCTAssertNotNil(jsonObject)
        XCTAssertEqual(jsonObject?["type"] as? String, "object")
        
        let properties = jsonObject?["properties"] as? [String: Any]
        XCTAssertNotNil(properties)
        XCTAssertNotNil(properties?["success"])
        XCTAssertNotNil(properties?["message"])
    }
}
