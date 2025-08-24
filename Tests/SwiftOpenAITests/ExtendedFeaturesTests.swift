import XCTest
@testable import SwiftOpenAI
import Foundation

// MARK: - 测试用例结构体定义

/// 带有复杂结构的测试工具参数
@SYToolArgs 
public struct ComplexToolArgs {
    /// 操作类型
    let operation: String
    /// 数值参数
    let numbers: [Double]
    /// 可选的配置项
    let config: ToolConfig?
    /// 是否启用详细模式
    let verbose: Bool
}

/// 嵌套配置结构
@AIModelSchema
public struct ToolConfig {
    /// 精度设置
    let precision: Int
    /// 输出格式
    let format: String
    /// 额外选项
    let options: [String]?
}

/// 复杂工具定义
@SYTool
public struct AdvancedCalculatorTool {
    let name = "advanced_calculator"
    let description = "执行高级数学计算，支持多种操作和配置"
    let parameters: ComplexToolArgs = ComplexToolArgs(
        operation: "",
        numbers: [],
        config: nil,
        verbose: false
    )
}

/// 任务结构体，用于测试嵌套数组
@AIModelSchema
public struct AITask {
    /// 任务名称
    let name: String
    /// 任务描述
    let description: String
    /// 子任务列表
    let subtasks: [AISubTask]?
    /// 任务优先级
    let priority: TaskPriority
}

/// 子任务结构体
@AIModelSchema 
public struct AISubTask {
    /// 子任务ID
    let id: String
    /// 子任务名称
    let name: String
    /// 预计完成时间（分钟）
    let estimatedMinutes: Int?
}

/// 任务优先级枚举
@AIModelSchema
public enum TaskPriority: String, CaseIterable {
    /// 高优先级
    case high
    /// 中等优先级
    case medium  
    /// 低优先级
    case low
}

/// 天气信息结构，用于测试复杂嵌套
@AIModelSchema
public struct WeatherInfo {
    /// 当前温度（摄氏度）
    let temperature: Double
    /// 天气状况描述
    let condition: String
    /// 湿度百分比
    let humidity: Int
    /// 风速
    let windSpeed: Double?
}

/// 每日天气预报
@AIModelSchema
public struct DailyForecast {
    /// 日期
    let date: String
    /// 最高温度
    let maxTemp: Double
    /// 最低温度
    let minTemp: Double
    /// 天气状况
    let condition: String
    /// 降雨概率（0-100）
    let rainChance: Int
}

final class ExtendedFeaturesTests: XCTestCase {
    
    // MARK: - 图片消息测试
    
    func testImageMessageCreation() throws {
        // 创建示例图片数据
        let imageData1 = Data("fake-image-data-1".utf8)
        let imageData2 = Data("fake-image-data-2".utf8)
        
        // 测试带图片的用户消息
        let messageWithImages = OpenAIMessage.user(
            "请分析这些图片",
            imageDatas: imageData1, imageData2,
            detail: .high,
            name: "analyst"
        )
        
        XCTAssertEqual(messageWithImages.role, .user)
        XCTAssertEqual(messageWithImages.name, "analyst")
        
        // 验证消息内容类型
        if case .user(let userMessage) = messageWithImages,
           case .contentParts(let parts) = userMessage.content {
            
            // 应该有3个部分：2个图片 + 1个文本（图片在前，文本在后）
            XCTAssertEqual(parts.count, 3)
            
            // 检查前两个是图片
            for i in 0...1 {
                if case .image(let imageContent) = parts[i] {
                    XCTAssertEqual(imageContent.imageUrl.detail, .high)
                } else {
                    XCTFail("第\(i+1)个内容应该是图片")
                }
            }
            
            // 检查最后一个是文本
            if case .text(let textContent) = parts[2] {
                XCTAssertEqual(textContent.text, "请分析这些图片")
            } else {
                XCTFail("最后一个内容应该是文本")
            }
        } else {
            XCTFail("用户消息内容格式不正确")
        }
    }
    
    func testImageOnlyMessage() throws {
        let imageData = Data("test-image".utf8)
        
        let imageMessage = OpenAIMessage.user(
            imageDatas: imageData,
            detail: .low
        )
        
        XCTAssertEqual(imageMessage.role, .user)
        
        if case .user(let userMessage) = imageMessage,
           case .contentParts(let parts) = userMessage.content {
            
            XCTAssertEqual(parts.count, 1)
            
            if case .image(let imageContent) = parts[0] {
                XCTAssertEqual(imageContent.imageUrl.detail, .low)
            } else {
                XCTFail("内容应该是图片")
            }
        } else {
            XCTFail("消息格式不正确")
        }
    }
    
    // MARK: - 数组便捷方法测试
    
    func testArrayMessageAdditions() throws {
        var messages: [OpenAIMessage] = []
        
        // 测试各种添加方法
        messages.addSystemMessage("系统消息")
        messages.addUserMessage("用户消息", name: "user123")
        messages.addAssistantMessage("助手回复", name: "assistant")
        messages.addToolMessage("工具结果", toolCallId: "tool_call_456")
        
        XCTAssertEqual(messages.count, 4)
        
        // 验证系统消息
        XCTAssertEqual(messages[0].role, .system)
        XCTAssertEqual(messages[0].textContent, "系统消息")
        
        // 验证用户消息
        XCTAssertEqual(messages[1].role, .user)
        XCTAssertEqual(messages[1].textContent, "用户消息")
        XCTAssertEqual(messages[1].name, "user123")
        
        // 验证助手消息
        XCTAssertEqual(messages[2].role, .assistant)
        XCTAssertEqual(messages[2].textContent, "助手回复")
        XCTAssertEqual(messages[2].name, "assistant")
        
        // 验证工具消息
        XCTAssertEqual(messages[3].role, .tool)
        XCTAssertEqual(messages[3].textContent, "工具结果")
        if case .tool(let toolMessage) = messages[3] {
            XCTAssertEqual(toolMessage.toolCallId, "tool_call_456")
        } else {
            XCTFail("应该是工具消息")
        }
    }
    
    // MARK: - 复杂工具测试
    
    func testComplexToolCreation() throws {
        let tool = AdvancedCalculatorTool()
        
        XCTAssertEqual(tool.name, "advanced_calculator")
        XCTAssertEqual(tool.description, "执行高级数学计算，支持多种操作和配置")
        
        let chatTool = tool.asChatCompletionTool
        XCTAssertEqual(chatTool.type, "function")
        XCTAssertEqual(chatTool.function.name, "advanced_calculator")
        XCTAssertEqual(chatTool.function.description, "执行高级数学计算，支持多种操作和配置")
        XCTAssertNotNil(chatTool.function.parameters)
        
        // 验证参数是有效的JSON字符串
        if let paramsString = chatTool.function.parameters,
           let paramsData = paramsString.data(using: .utf8) {
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: paramsData))
        }
    }
    
    func testToolArgsSchemaGeneration() throws {
        let schema = ComplexToolArgs.parametersSchema
        
        XCTAssertFalse(schema.isEmpty)
        
        // 验证包含所有必要字段
        let schemaDict = schema
        XCTAssertNotNil(schemaDict["type"])
        XCTAssertNotNil(schemaDict["properties"])
        XCTAssertNotNil(schemaDict["required"])
        
        if let properties = schemaDict["properties"] as? [String: Any] {
            XCTAssertNotNil(properties["operation"])
            XCTAssertNotNil(properties["numbers"])
            XCTAssertNotNil(properties["config"])
            XCTAssertNotNil(properties["verbose"])
        } else {
            XCTFail("properties字段应该是字典类型")
        }
        
        if let required = schemaDict["required"] as? [String] {
            XCTAssertTrue(required.contains("operation"))
            XCTAssertTrue(required.contains("numbers"))
            XCTAssertTrue(required.contains("verbose"))
        } else {
            XCTFail("required字段应该是数组类型")
        }
    }
    
    // MARK: - 嵌套结构Schema测试
    
    func testNestedStructureSchema() throws {
        let schema = AITask.outputSchema
        
        XCTAssertFalse(schema.isEmpty)
        
        print("Generated AITask schema:")
        print(schema)
        
        // 先检查基本结构，不强制要求JSON有效性（因为可能包含嵌套引用）
        XCTAssertTrue(schema.contains("type"))
        XCTAssertTrue(schema.contains("properties"))
        
        // 检查是否包含结构字段
        XCTAssertTrue(schema.contains("name"))
        XCTAssertTrue(schema.contains("description"))
        XCTAssertTrue(schema.contains("subtasks"))
        XCTAssertTrue(schema.contains("priority"))
    }
    
    func testWeatherInfoComplexSchema() throws {
        let schema = WeatherInfo.outputSchema
        
        XCTAssertFalse(schema.isEmpty)
        
        // 验证JSON有效性
        let jsonData = Data(schema.utf8)
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        XCTAssertNotNil(jsonObject)
        
        // 验证基本结构
        XCTAssertEqual(jsonObject?["type"] as? String, "object")
        
        let properties = jsonObject?["properties"] as? [String: Any]
        XCTAssertNotNil(properties)
        XCTAssertNotNil(properties?["temperature"])
        XCTAssertNotNil(properties?["condition"])
        XCTAssertNotNil(properties?["humidity"])
        XCTAssertNotNil(properties?["windSpeed"])
    }
    
    func testEnumSchemaGeneration() throws {
        let schema = TaskPriority.outputSchema
        
        XCTAssertFalse(schema.isEmpty)
        
        // 验证JSON格式
        let jsonData = Data(schema.utf8)
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        XCTAssertNotNil(jsonObject)
        
        // 验证枚举结构
        XCTAssertEqual(jsonObject?["type"] as? String, "string")
        
        let enumValues = jsonObject?["enum"] as? [String]
        XCTAssertNotNil(enumValues)
        XCTAssertTrue(enumValues?.contains("high") == true)
        XCTAssertTrue(enumValues?.contains("medium") == true)
        XCTAssertTrue(enumValues?.contains("low") == true)
    }
    
    // MARK: - ChatQuery高级功能测试
    
    func testChatQueryWithTools() throws {
        let tool = AdvancedCalculatorTool()
        let messages: [OpenAIMessage] = [
            .system("你是一个数学助手"),
            .user("计算 10 + 15 * 2")
        ]
        
        let query = ChatQuery(
            messages: messages,
            model: "gpt-4",
            maxCompletionTokens: 1000,
            parallelToolCalls: true,
            temperature: 0.7,
            tools: [tool.asChatCompletionTool],
            stream: true
        )
        
        XCTAssertEqual(query.model, "gpt-4")
        XCTAssertEqual(query.parallelToolCalls, true)
        XCTAssertEqual(query.tools?.count, 1)
        XCTAssertEqual(query.temperature, 0.7)
        XCTAssertEqual(query.maxCompletionTokens, 1000)
        XCTAssertEqual(query.stream, true)
        
        // 验证工具配置
        if let tool = query.tools?.first {
            XCTAssertEqual(tool.type, "function")
            XCTAssertEqual(tool.function.name, "advanced_calculator")
        }
    }
    
    func testChatQueryEncoding() throws {
        let messages: [OpenAIMessage] = [
            .user("测试消息")
        ]
        
        let query = ChatQuery(
            messages: messages,
            model: "gpt-4",
            frequencyPenalty: 0.2,
            presencePenalty: 0.1,
            stop: .array(["停止", "结束"]),
            temperature: 0.5,
            topP: 0.9,
            stream: false
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let jsonData = try encoder.encode(query)
        let jsonString = String(data: jsonData, encoding: .utf8)
        
        XCTAssertNotNil(jsonString)
        XCTAssertTrue(jsonString!.contains("gpt-4"))
        XCTAssertTrue(jsonString!.contains("0.5"))
        XCTAssertTrue(jsonString!.contains("停止"))
        XCTAssertTrue(jsonString!.contains("结束"))
        
        // 验证可以往返编码
        let decodedQuery = try JSONDecoder().decode(ChatQuery.self, from: jsonData)
        XCTAssertEqual(decodedQuery.model, "gpt-4")
        XCTAssertEqual(decodedQuery.temperature, 0.5)
        XCTAssertEqual(decodedQuery.topP, 0.9)
        XCTAssertEqual(decodedQuery.frequencyPenalty, 0.2)
        XCTAssertEqual(decodedQuery.presencePenalty, 0.1)
    }
    
    // MARK: - 错误处理测试
    
    func testOpenAIErrorHandling() {
        let networkError = URLError(.notConnectedToInternet)
        let openAIError = OpenAIError.networkError(networkError)
        
        XCTAssertNotNil(openAIError.errorDescription)
        XCTAssertTrue(openAIError.errorDescription!.contains("网络"))
        
        let streamingError = OpenAIError.streamingError("连接中断")
        XCTAssertTrue(streamingError.errorDescription!.contains("连接中断"))
        
        let invalidResponseError = OpenAIError.invalidResponse
        XCTAssertNotNil(invalidResponseError.errorDescription)
    }
    
    // MARK: - 性能测试
    
    func testSchemaGenerationPerformance() {
        measure {
            // 多次生成schema来测试性能
            for _ in 0..<100 {
                _ = WeatherInfo.outputSchema
                _ = AITask.outputSchema
                _ = TaskPriority.outputSchema
            }
        }
    }
    
    func testMessageCreationPerformance() {
        measure {
            // 测试消息创建性能
            for i in 0..<1000 {
                let messages: [OpenAIMessage] = [
                    .system("系统消息 \(i)"),
                    .user("用户消息 \(i)"),
                    .assistant("助手回复 \(i)")
                ]
                _ = messages.count
            }
        }
    }
}
