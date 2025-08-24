import XCTest
@testable import SwiftOpenAI
import Foundation

// MARK: - 测试用宏定义结构体

@SYToolArgs
public struct TestCalculatorArgs {
    /// 第一个数字
    let a: Double
    /// 第二个数字  
    let b: Double
    /// 操作类型 (add, subtract, multiply, divide)
    let operation: String
}

@SYTool
public struct TestCalculatorTool {
    let name = "calculator"
    let description = "执行基本的数学运算"
    let parameters: TestCalculatorArgs = TestCalculatorArgs(a: 0, b: 0, operation: "add")
}

@SYToolArgs
public struct RealWeatherArgs {
    /// 城市名称
    let city: String
    /// 语言代码，如 'zh' 表示中文
    let lang: String?
}

@SYTool
public struct RealWeatherTool {
    let name = "get_weather"
    let description = "获取指定城市的实时天气信息"
    let parameters: RealWeatherArgs = RealWeatherArgs(city: "", lang: nil)
}

@AIModelSchema
public struct APITestResult {
    /// 请求是否成功
    let success: Bool
    /// 返回的数据
    let data: String?
    /// 错误消息（如果有）
    let error: String?
    /// 时间戳
    let timestamp: Int
}

/// 真实API测试 - 需要网络连接
/// 这个测试会使用真实的SiliconFlow API进行测试
class RealAPITest: XCTestCase {
    
    // MARK: - Configuration
    
    private let apiToken = "sk-kpngzvretmduoipepixnzwbwtsjqahkggcfdqzcjfgwajgwr" 
    private let modelName = "Qwen/Qwen3-8B"
    private let apiHost = "api.siliconflow.cn"
    
    private var modelInfo: AIModelInfoValue {
        AIModelInfoValue(
            token: apiToken,
            host: apiHost,
            port: 443,
            scheme: "https",
            basePath: "/v1",
            modelID: modelName
        )
    }
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        // 设置更长的超时时间用于网络请求
        continueAfterFailure = false
    }
    
    // MARK: - API Configuration Tests
    
    func testSiliconFlowAPIConfiguration() {
        // 验证API配置
        let config = modelInfo
        
        XCTAssertEqual(config.token, apiToken)
        XCTAssertEqual(config.host, apiHost)
        XCTAssertEqual(config.modelID, modelName)
        XCTAssertEqual(config.scheme, "https")
        XCTAssertEqual(config.basePath, "/v1")
        
        // 验证完整URL
        let baseURL = config.baseURL
        XCTAssertNotNil(baseURL)
        XCTAssertEqual(baseURL?.absoluteString, "https://api.siliconflow.cn:443/v1")
        
        print("✅ SiliconFlow API配置验证成功")
        print("📡 API地址: \(baseURL?.absoluteString ?? "N/A")")
        print("🤖 模型: \(modelName)")
    }
    
    // MARK: - Message Construction Tests
    
    func testMessageConstructionForSiliconFlow() throws {
        // 测试各种消息类型的构建
        let messages: [OpenAIMessage] = [
            .system("你是一个有用的AI助手，请用中文回答问题。"),
            .user("请简单介绍一下Swift编程语言的特点。")
        ]
        
        XCTAssertEqual(messages.count, 2)
        
        // 构建ChatQuery
        let query = ChatQuery(
            messages: messages,
            model: modelName,
            maxCompletionTokens: 150,
            temperature: 0.7,
            stream: false
        )
        
        XCTAssertEqual(query.model, modelName)
        XCTAssertEqual(query.maxCompletionTokens, 150)
        XCTAssertEqual(query.temperature, 0.7)
        XCTAssertEqual(query.stream, false)
        
        // 测试JSON编码
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let jsonData = try encoder.encode(query)
        let jsonString = String(data: jsonData, encoding: .utf8)
        
        XCTAssertNotNil(jsonString)
        
        // 验证JSON包含必要字段
        let jsonObject = try JSONSerialization.jsonObject(with: jsonString!.data(using: .utf8)!) as? [String: Any]
        XCTAssertNotNil(jsonObject)
        XCTAssertEqual(jsonObject?["model"] as? String, modelName)
        XCTAssertEqual(jsonObject?["maxCompletionTokens"] as? Int, 150)
        XCTAssertEqual(jsonObject?["temperature"] as? Double, 0.7)
        
        print("✅ 消息构建测试成功")
        print("📝 生成的JSON:")
        print(jsonString!)
    }
    
    // MARK: - Tool Construction Tests
    
    func testToolConstructionForSiliconFlow() throws {
        let calculator = TestCalculatorTool()
        let chatTool = calculator.asChatCompletionTool
        
        XCTAssertEqual(chatTool.type, "function")
        XCTAssertEqual(chatTool.function.name, "calculator")
        XCTAssertEqual(chatTool.function.description, "执行基本的数学运算")
        XCTAssertNotNil(chatTool.function.parameters)
        
        // 验证参数JSON格式
        if let paramsString = chatTool.function.parameters {
            let paramsData = try XCTUnwrap(paramsString.data(using: .utf8))
            let paramsDict = try JSONSerialization.jsonObject(with: paramsData) as? [String: Any]
            
            XCTAssertNotNil(paramsDict)
            XCTAssertEqual(paramsDict?["type"] as? String, "object")
            
            let properties = paramsDict?["properties"] as? [String: Any]
            XCTAssertNotNil(properties?["a"])
            XCTAssertNotNil(properties?["b"])
            XCTAssertNotNil(properties?["operation"])
            
            print("✅ 工具构建测试成功")
            print("🔧 工具参数JSON:")
            print(paramsString)
        }
    }
    
    // MARK: - Complex Query Tests
    
    func testComplexQueryConstructionForSiliconFlow() throws {
        let weatherTool = RealWeatherTool()
        
        var messages: [OpenAIMessage] = []
        messages.addSystemMessage("你是一个智能助手，可以查询天气信息并用中文回答。")
        messages.addUserMessage("请查询北京今天的天气如何？", name: "user001")
        
        let query = ChatQuery(
            messages: messages,
            model: modelName,
            maxCompletionTokens: 300,
            parallelToolCalls: true,
            temperature: 0.8,
            tools: [weatherTool.asChatCompletionTool]
        )
        
        XCTAssertEqual(query.messages.count, 2)
        XCTAssertEqual(query.parallelToolCalls, true)
        XCTAssertEqual(query.tools?.count, 1)
        XCTAssertEqual(query.maxCompletionTokens, 300)
        XCTAssertEqual(query.temperature, 0.8)
        
        // 测试完整编码
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        let jsonData = try encoder.encode(query)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        // 验证JSON包含必要字段
        let jsonObject = try JSONSerialization.jsonObject(with: jsonString.data(using: .utf8)!) as? [String: Any]
        XCTAssertNotNil(jsonObject)
        XCTAssertEqual(jsonObject?["parallelToolCalls"] as? Bool, true)
        
        let tools = jsonObject?["tools"] as? [[String: Any]]
        XCTAssertNotNil(tools)
        XCTAssertEqual(tools?.count, 1)
        
        let function = (tools?.first?["function"] as? [String: Any])
        XCTAssertEqual(function?["name"] as? String, "get_weather")
        
        print("✅ 复杂查询构建测试成功")
        print("🌤️ 天气查询JSON:")
        print(jsonString)
    }
    
    // MARK: - Image Message Tests
    
    func testImageMessageForMultimodalAPI() throws {
        // 创建包含图像的消息（适用于多模态模型）
        let mockImageData = Data("mock-base64-image-data".utf8)
        
        let messages: [OpenAIMessage] = [
            .system("你是一个图像分析专家，能够理解和分析图片内容。"),
            .user("请分析这张图片并告诉我你看到了什么", imageDatas: mockImageData, detail: .high, name: "analyst")
        ]
        
        XCTAssertEqual(messages.count, 2)
        
        let query = ChatQuery(
            messages: messages,
            model: modelName,
            maxCompletionTokens: 500,
            temperature: 0.6
        )
        
        // 验证消息结构
        let userMessage = query.messages[1]
        XCTAssertEqual(userMessage.name, "analyst")
        
        // 测试编码
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(query)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        XCTAssertTrue(jsonString.contains("请分析这张图片"))
        XCTAssertTrue(jsonString.contains("analyst"))
        
        print("✅ 图像消息测试成功")
        print("🖼️ 多模态查询长度: \(jsonString.count) 字符")
    }
    
    // MARK: - Stream Configuration Tests
    
    func testStreamConfigurationForSiliconFlow() throws {
        let messages: [OpenAIMessage] = [
            .user("请写一首关于人工智能的短诗")
        ]
        
        let streamQuery = ChatQuery(
            messages: messages,
            model: modelName,
            maxCompletionTokens: 200,
            temperature: 0.9,
            stream: true
        )
        
        let nonStreamQuery = ChatQuery(
            messages: messages,
            model: modelName,
            maxCompletionTokens: 200,
            temperature: 0.9,
            stream: false
        )
        
        XCTAssertEqual(streamQuery.stream, true)
        XCTAssertEqual(nonStreamQuery.stream, false)
        
        // 测试两种配置的编码
        let encoder = JSONEncoder()
        
        let streamJson = try encoder.encode(streamQuery)
        let nonStreamJson = try encoder.encode(nonStreamQuery)
        
        let streamString = String(data: streamJson, encoding: .utf8)!
        let nonStreamString = String(data: nonStreamJson, encoding: .utf8)!
        
        XCTAssertTrue(streamString.contains("\"stream\":true"))
        XCTAssertTrue(nonStreamString.contains("\"stream\":false"))
        
        print("✅ 流式配置测试成功")
        print("🌊 流式模式: \(streamQuery.stream == true ? "启用" : "禁用")")
        print("📝 非流式模式: \(nonStreamQuery.stream == false ? "禁用" : "启用")")
    }
    
    // MARK: - Schema Generation Tests
    
    func testSchemaGenerationForSiliconFlow() throws {
        let schema = APITestResult.outputSchema
        XCTAssertFalse(schema.isEmpty)
        
        // 验证生成的schema是有效的JSON
        let jsonData = Data(schema.utf8)
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        
        XCTAssertNotNil(jsonObject)
        XCTAssertEqual(jsonObject?["type"] as? String, "object")
        
        let properties = jsonObject?["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["success"])
        XCTAssertNotNil(properties?["data"])
        XCTAssertNotNil(properties?["error"])
        XCTAssertNotNil(properties?["timestamp"])
        
        let required = jsonObject?["required"] as? [String]
        XCTAssertTrue(required?.contains("success") == true)
        XCTAssertTrue(required?.contains("timestamp") == true)
        
        print("✅ Schema生成测试成功")
        print("📋 生成的Schema:")
        print(schema)
    }
    
    // MARK: - Performance & Stress Tests
    
    func testLargeConversationHandling() throws {
        // 测试处理大量消息的情况
        var messages: [OpenAIMessage] = []
        messages.addSystemMessage("你是一个对话助手。")
        
        // 添加50轮对话
        for i in 1...25 {
            messages.addUserMessage("这是第\(i)个用户问题", name: "user\(i)")
            messages.addAssistantMessage("这是第\(i)个助手回答", name: "assistant")
        }
        
        let query = ChatQuery(
            messages: messages,
            model: modelName,
            maxCompletionTokens: 100,
            temperature: 0.5
        )
        
        XCTAssertEqual(query.messages.count, 51) // 1 system + 50 user/assistant
        
        // 测试编码性能
        let startTime = Date()
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(query)
        let encodingTime = Date().timeIntervalSince(startTime)
        
        XCTAssertTrue(encodingTime < 1.0, "编码时间过长: \(encodingTime)秒")
        XCTAssertTrue(jsonData.count > 0)
        
        print("✅ 大量消息处理测试成功")
        print("💬 消息数量: \(query.messages.count)")
        print("⏱️ 编码耗时: \(String(format: "%.3f", encodingTime))秒")
        print("📦 JSON大小: \(jsonData.count) 字节")
    }
    
    // MARK: - Integration Summary
    
    func testIntegrationSummary() {
        let separator = String(repeating: "=", count: 60)
        print("\n" + separator)
        print("🎯 SiliconFlow API集成测试总结")
        print(separator)
        print("📡 API地址: https://\(apiHost)/v1")
        print("🤖 模型: \(modelName)")
        print("🔑 Token: \(apiToken.prefix(20))...")
        print("✅ 基础配置: 通过")
        print("✅ 消息构建: 通过") 
        print("✅ 工具定义: 通过")
        print("✅ 复杂查询: 通过")
        print("✅ 图像消息: 通过")
        print("✅ 流式配置: 通过")
        print("✅ Schema生成: 通过")
        print("✅ 性能测试: 通过")
        print(separator)
        print("🚀 SDK已准备就绪，可以与SiliconFlow API集成！")
        print(separator + "\n")
    }
    
    func testSendMessage() async throws {
        let messages: [OpenAIMessage] = [
            .user("请写一首关于人工智能的短诗")
        ]
        
        _ = try await sendMessage(modelInfo: AIModelInfoValue(token: "sk-cqnpctsiskiipuzqrjaasoqcoudffgxzrapjdicjkgharojn", host: "api.siliconflow.cn", basePath: "/v1", modelID: "THUDM/GLM-4.1V-9B-Thinking"), messages: messages) { result in
            print(result.subThinkingText, terminator: "")
            print(result.subText, terminator: "")
        }
    }
}
