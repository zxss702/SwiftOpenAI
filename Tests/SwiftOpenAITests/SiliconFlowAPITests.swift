import XCTest
@testable import SwiftOpenAI
import Foundation

// MARK: - 测试用宏定义结构体

/// 天气查询参数
@SYToolArgs 
public struct WeatherQueryArgs {
    /// 城市名称
    let city: String
    /// 国家代码（可选）
    let country: String?
}

/// 天气查询工具
@SYTool
public struct WeatherQueryTool {
    let name = "get_weather"
    let description = "获取指定城市的天气信息"
    let parameters = WeatherQueryArgs.self
}

/// API响应结构
@AIModelSchema
public struct APITestResponse {
    /// 响应状态码
    let status: Int
    /// 响应消息
    let message: String
    /// 响应数据
    let data: APIResponseData?
}

/// API响应数据
@AIModelSchema
public struct APIResponseData {
    /// 用户ID
    let userId: String
    /// 用户名
    let username: String
    /// 创建时间
    let createdAt: String
}

/// SiliconFlow API 实际测试
final class SiliconFlowAPITests: XCTestCase {
    
    // MARK: - API Configuration
    
    private let apiToken = "test-token"
    private let modelName = "Qwen/Qwen3-8B"
    private let apiHost = "api.siliconflow.cn"
    private let apiPath = "/v1"
    
    private var modelInfo: AIModelInfoValue {
        AIModelInfoValue(
            token: apiToken,
            host: apiHost,
            port: 443,
            scheme: "https",
            basePath: apiPath,
            modelID: modelName
        )
    }
    
    // MARK: - 基础API测试
    
    func testSiliconFlowConfiguration() {
        let config = modelInfo
        
        XCTAssertEqual(config.token, apiToken)
        XCTAssertEqual(config.host, apiHost)
        XCTAssertEqual(config.modelID, modelName)
        XCTAssertEqual(config.scheme, "https")
        XCTAssertEqual(config.basePath, apiPath)
        
        let baseURL = config.baseURL
        XCTAssertNotNil(baseURL)
        XCTAssertEqual(baseURL?.absoluteString, "https://api.siliconflow.cn:443/v1")
    }
    
    func testChatQueryCreationForSiliconFlow() throws {
        let messages: [OpenAIMessage] = [
            .system("你是一个有用的AI助手。"),
            .user("请简要介绍一下中国的首都。")
        ]
        
        let query = ChatQuery(
            messages: messages,
            model: modelName,
            maxCompletionTokens: 100,
            temperature: 0.7,
            stream: false
        )
        
        XCTAssertEqual(query.model, modelName)
        XCTAssertEqual(query.messages.count, 2)
        XCTAssertEqual(query.maxCompletionTokens, 100)
        XCTAssertEqual(query.temperature, 0.7)
        XCTAssertEqual(query.stream, false)
        
        // 验证消息内容
        XCTAssertEqual(query.messages[0].role, .system)
        XCTAssertEqual(query.messages[1].role, .user)
    }
    
    func testJSONEncodingForSiliconFlowAPI() throws {
        let messages: [OpenAIMessage] = [
            .user("你好，请问今天天气如何？")
        ]
        
        let query = ChatQuery(
            messages: messages,
            model: modelName,
            temperature: 0.8,
            stream: false
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let jsonData = try encoder.encode(query)
        let jsonString = String(data: jsonData, encoding: .utf8)
        
        XCTAssertNotNil(jsonString)
        
        // 验证JSON包含必要字段
        let jsonObject = try JSONSerialization.jsonObject(with: jsonString!.data(using: .utf8)!) as? [String: Any]
        XCTAssertNotNil(jsonObject)
        XCTAssertEqual(jsonObject?["model"] as? String, "Qwen/Qwen3-8B")
        XCTAssertEqual(jsonObject?["temperature"] as? Double, 0.8)
        
        let messagesArray = jsonObject?["messages"] as? [[String: Any]]
        XCTAssertNotNil(messagesArray)
        XCTAssertTrue(messagesArray?.count ?? 0 > 0)
        
        print("Generated JSON for SiliconFlow API:")
        print(jsonString!)
    }
    
    // MARK: - 工具调用测试
    
    func testToolCallWithSiliconFlow() throws {
        let weatherTool = WeatherQueryTool()
        let messages: [OpenAIMessage] = [
            .system("你是一个天气助手，可以查询天气信息。"),
            .user("请查询北京的天气")
        ]
        
        let query = ChatQuery(
            messages: messages,
            model: modelName,
            parallelToolCalls: true,
            temperature: 0.7,
            tools: [weatherTool.asChatCompletionTool]
        )
        
        XCTAssertEqual(query.parallelToolCalls, true)
        XCTAssertEqual(query.tools?.count, 1)
        
        let tool = query.tools?.first
        XCTAssertEqual(tool?.type, "function")
        XCTAssertEqual(tool?.function.name, "get_weather")
        XCTAssertEqual(tool?.function.description, "获取指定城市的天气信息")
        XCTAssertNotNil(tool?.function.parameters)
        
        // 验证工具参数是有效的字典
        if let paramsContainer = tool?.function.parameters {
            let paramsDict = paramsContainer.toDictionary()
            XCTAssertNotNil(paramsDict)
            
            let properties = paramsDict["properties"] as? [String: Any]
            XCTAssertNotNil(properties?["city"])
            XCTAssertNotNil(properties?["country"])
            
            print("Tool parameters JSON:")
            print(paramsContainer.toJSONString() ?? "无法转换为JSON")
        }
    }
    
    // MARK: - 流式传输配置测试
    
    func testStreamingConfigurationForSiliconFlow() throws {
        let messages: [OpenAIMessage] = [
            .user("请写一个关于春天的短诗")
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
        XCTAssertEqual(streamQuery.maxCompletionTokens, 200)
        XCTAssertEqual(streamQuery.temperature, 0.9)
        XCTAssertEqual(nonStreamQuery.stream, false)
        
        // 测试两种配置的编码
        let encoder = JSONEncoder()
        
        let streamJson = try encoder.encode(streamQuery)
        let nonStreamJson = try encoder.encode(nonStreamQuery)
        
        let streamDict = try JSONSerialization.jsonObject(with: streamJson) as? [String: Any]
        let nonStreamDict = try JSONSerialization.jsonObject(with: nonStreamJson) as? [String: Any]
        
        XCTAssertEqual(streamDict?["stream"] as? Bool, true)
        XCTAssertEqual(nonStreamDict?["stream"] as? Bool, false)
        XCTAssertEqual(streamDict?["maxCompletionTokens"] as? Int, 200)
        XCTAssertEqual(nonStreamDict?["maxCompletionTokens"] as? Int, 200)
    }
    
    // MARK: - 图片消息测试（适用于多模态模型）
    
    func testImageMessageForSiliconFlow() throws {
        // 创建模拟图片数据
        let imageData = Data("mock-image-data".utf8)
        
        let messages: [OpenAIMessage] = [
            .system("你是一个图像分析助手。"),
            .user("请分析这张图片", imageDatas: imageData, detail: .high)
        ]
        
        let query = ChatQuery(
            messages: messages,
            model: modelName,
            maxCompletionTokens: 300
        )
        
        XCTAssertEqual(query.messages.count, 2)
        
        // 验证图片消息结构
        if case .user(let userMessage) = query.messages[1],
           case .contentParts(let parts) = userMessage.content {
            
            XCTAssertEqual(parts.count, 2) // 1 image + 1 text（图片在前，文本在后）
            
            // 验证图片部分
            if case .image(let imageContent) = parts[0] {
                XCTAssertEqual(imageContent.imageUrl.detail, .high)
            } else {
                XCTFail("第一部分应该是图片")
            }
            
            // 验证文本部分
            if case .text(let textContent) = parts[1] {
                XCTAssertEqual(textContent.text, "请分析这张图片")
            } else {
                XCTFail("第二部分应该是文本")
            }
        } else {
            XCTFail("用户消息格式不正确")
        }
    }
    
    // MARK: - 复杂对话测试
    
    func testComplexConversationForSiliconFlow() throws {
        var messages: [OpenAIMessage] = []
        
        // 构建一个复杂的对话历史
        messages.addSystemMessage("你是一个专业的编程助手，擅长Swift开发。")
        messages.addUserMessage("我想学习Swift中的闭包", name: "developer")
        messages.addAssistantMessage("闭包是Swift中的一个重要概念...")
        messages.addUserMessage("能给个具体例子吗？")
        
        let query = ChatQuery(
            messages: messages,
            model: modelName,
            maxCompletionTokens: 500,
            temperature: 0.6
        )
        
        XCTAssertEqual(query.messages.count, 4)
        // 验证消息数量和基本属性
        XCTAssertEqual(query.model, modelName)
        XCTAssertEqual(query.maxCompletionTokens, 500)
        XCTAssertEqual(query.temperature, 0.6)
        
        // 验证用户名设置
        XCTAssertEqual(query.messages[1].name, "developer")
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(query)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        print("Complex conversation JSON:")
        print(jsonString)
    }
    
    // MARK: - 错误处理测试
    
    func testAPIErrorHandling() {
        // 测试无效的模型信息
        let invalidModelInfo = AIModelInfoValue(
            token: "",  // 空token
            host: apiHost,
            modelID: modelName
        )
        
        XCTAssertEqual(invalidModelInfo.token, "")
        XCTAssertEqual(invalidModelInfo.host, apiHost)
        
        // 测试URL构建
        let baseURL = invalidModelInfo.baseURL
        XCTAssertNotNil(baseURL)
        XCTAssertEqual(baseURL?.host, apiHost)
    }
    
    // MARK: - 性能和编码测试
    
    func testLargeMessageEncoding() throws {
        // 创建一个包含大量消息的查询
        var messages: [OpenAIMessage] = []
        
        messages.addSystemMessage("你是一个有用的助手。")
        
        for i in 1...50 {
            messages.addUserMessage("这是第\(i)条用户消息")
            messages.addAssistantMessage("这是第\(i)条助手回复")
        }
        
        let query = ChatQuery(
            messages: messages,
            model: modelName,
            maxCompletionTokens: 1000
        )
        
        XCTAssertEqual(query.messages.count, 101) // 1 system + 50*2 user+assistant
        
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(query)
        
        // 验证编码成功
        XCTAssertTrue(jsonData.count > 0)
        
        // 验证可以解码
        let decodedQuery = try JSONDecoder().decode(ChatQuery.self, from: jsonData)
        XCTAssertEqual(decodedQuery.messages.count, query.messages.count)
        XCTAssertEqual(decodedQuery.model, modelName)
    }
    
    // MARK: - Schema生成验证
    
    func testSchemaGenerationForAPI() throws {
        let schema = APITestResponse.outputSchema
        XCTAssertFalse(schema.isEmpty)
        
        // 验证JSON格式
        let jsonData = Data(schema.utf8)
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        XCTAssertNotNil(jsonObject)
        
        let properties = jsonObject?["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["status"])
        XCTAssertNotNil(properties?["message"])
        XCTAssertNotNil(properties?["data"])
        
        print("Generated schema for API response:")
        print(schema)
    }
}
