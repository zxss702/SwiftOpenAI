import XCTest
@testable import SwiftOpenAI
import Foundation

// MARK: - 测试工具定义

@SYToolArgs
struct 前言 {
    let 内容: String
}

@SYTool
struct forewordTool {
    let name: String = "前言"
    let description: String = "向用户说明你下一步的计划。不应该超过两句话。"
    let parameters = 前言.self
}

@SYToolArgs
struct TestArgs {
    let message: String
    let count: Int?
}

@SYTool
struct TestTool {
    let name = "test_tool"
    let description = "测试工具"
    let parameters = TestArgs.self
}

final class MainActorIsolationTest: XCTestCase {
    
    func testForewordToolNonisolatedAccess() throws {
        // 测试 forewordTool 可以在非隔离上下文中访问
        let foreword = forewordTool()
        
        // 这些调用应该不会产生 Main actor 隔离错误
        let forewordChatTool = foreword.asChatCompletionTool
        
        XCTAssertEqual(forewordChatTool.type, "function")
        XCTAssertEqual(forewordChatTool.function.name, "前言")
        XCTAssertEqual(forewordChatTool.function.description, "向用户说明你下一步的计划。不应该超过两句话。")
    }
    
    func testToolArrayCreation() throws {
        // 测试工具数组创建
        let tools: [any OpenAIToolConvertible] = [
            TestTool(),
            forewordTool()
        ]
        
        // 验证工具数组可以正常创建
        XCTAssertEqual(tools.count, 2)
        
        let chatTools = tools.map { $0.asChatCompletionTool }
        XCTAssertEqual(chatTools.count, 2)
        XCTAssertEqual(chatTools[0].function.name, "test_tool")
        XCTAssertEqual(chatTools[1].function.name, "前言")
    }
    
    func testToolParametersSchema() throws {
        // 测试参数 schema 生成
        let testSchema = TestArgs.parametersSchema
        let forewordSchema = 前言.parametersSchema
        
        XCTAssertNotNil(testSchema)
        XCTAssertNotNil(forewordSchema)
        
        // 验证 schema 结构
        if let testDict = testSchema as? [String: Any] {
            XCTAssertEqual(testDict["type"] as? String, "object")
        }
        
        if let forewordDict = forewordSchema as? [String: Any] {
            XCTAssertEqual(forewordDict["type"] as? String, "object")
        }
    }
    
    func testNonisolatedProtocolConformance() throws {
        // 测试协议一致性
        let tool = TestTool()
        let foreword = forewordTool()
        
        // 验证工具实现了 OpenAIToolConvertible 协议
        XCTAssertTrue(tool is OpenAIToolConvertible)
        XCTAssertTrue(foreword is OpenAIToolConvertible)
        
        // 验证参数结构体实现了 SYToolArgsConvertible 协议
        XCTAssertTrue(TestArgs.self is SYToolArgsConvertible.Type)
        XCTAssertTrue(前言.self is SYToolArgsConvertible.Type)
    }
    
    func testSendMessageWithTools() async throws {
        // 测试在 sendMessage 中使用工具（这应该不会产生 Main actor 隔离错误）
        let modelInfo = AIModelInfoValue(
            token: "test-token",
            modelID: "test-model"
        )
        
        let messages: [OpenAIMessage] = [
            .user("请使用前言工具")
        ]
        
        let tools: [any OpenAIToolConvertible] = [forewordTool()]
        
        // 这个调用应该不会产生 Main actor 隔离错误
        // 注意：这里我们只是测试编译，不实际发送请求
        let _ = tools.map { $0.asChatCompletionTool }
        
        // 验证工具可以正常转换
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools[0].asChatCompletionTool.function.name, "前言")
    }
}
