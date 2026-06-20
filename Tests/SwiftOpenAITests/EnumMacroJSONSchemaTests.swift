import XCTest
import SwiftOpenAI

@SYToolArgs
public enum TestAgentRoleWithRawValue: String, Codable, Sendable {
    case critic = "批判家"
    case visionary = "梦想家"
    case doer = "实干家"
}

@SYToolArgs
public enum TestAgentRoleWithoutRawValue: String, Codable, Sendable {
    case observer
    case reporter
}

@SYToolArgs
nonisolated struct MotionToolArgs: Codable, Sendable {
    /// 这里的描述测试
    let content: String
    
    /// 发送给拥有 rawValue 的角色
    let targetWithRawValue: TestAgentRoleWithRawValue
    
    /// 发送给没有 rawValue 的角色
    let targetWithoutRawValue: TestAgentRoleWithoutRawValue
}

final class EnumMacroJSONSchemaTests: XCTestCase {
    
    func testEnumWithRawValueSchema() throws {
        // TestAgentRoleWithRawValue 应该包含 "批判家", "梦想家", "实干家"
        let schema = TestAgentRoleWithRawValue.parametersSchema
        
        guard case .array(let enumValues) = schema["enum"] else {
            XCTFail("Schema 应该包含 enum 数组")
            return
        }
        
        let stringValues = enumValues.compactMap { val -> String? in
            if case .string(let str) = val { return str }
            return nil
        }
        
        XCTAssertEqual(stringValues.count, 3)
        XCTAssertTrue(stringValues.contains("批判家"))
        XCTAssertTrue(stringValues.contains("梦想家"))
        XCTAssertTrue(stringValues.contains("实干家"))
        XCTAssertFalse(stringValues.contains("critic"))
    }
    
    func testEnumWithoutRawValueSchema() throws {
        // TestAgentRoleWithoutRawValue 应该包含 "observer", "reporter"
        let schema = TestAgentRoleWithoutRawValue.parametersSchema
        
        guard case .array(let enumValues) = schema["enum"] else {
            XCTFail("Schema 应该包含 enum 数组")
            return
        }
        
        let stringValues = enumValues.compactMap { val -> String? in
            if case .string(let str) = val { return str }
            return nil
        }
        
        XCTAssertEqual(stringValues.count, 2)
        XCTAssertTrue(stringValues.contains("observer"))
        XCTAssertTrue(stringValues.contains("reporter"))
    }
    
    func testNestedStructSchemaGeneration() throws {
        let schema = MotionToolArgs.parametersSchema
        
        XCTAssertEqual(schema["type"], .string("object"))
        
        guard case .object(let properties) = schema["properties"] else {
            XCTFail("Schema 应该包含 properties 对象")
            return
        }
        
        // 验证 content
        guard case .object(let contentProp) = properties["content"] else {
            XCTFail("缺少 content 属性")
            return
        }
        XCTAssertEqual(contentProp["type"], .string("string"))
        XCTAssertEqual(contentProp["description"], .string("这里的描述测试"))
        
        // 验证 targetWithRawValue 嵌套枚举
        guard case .object(let targetWithRawValueProp) = properties["targetWithRawValue"] else {
            XCTFail("缺少 targetWithRawValue 属性")
            return
        }
        guard case .array(let enumValues1) = targetWithRawValueProp["enum"] else {
            XCTFail("targetWithRawValue 缺少 enum 数组")
            return
        }
        
        let stringValues1 = enumValues1.compactMap { val -> String? in
            if case .string(let str) = val { return str }
            return nil
        }
        XCTAssertTrue(stringValues1.contains("批判家"))
        XCTAssertFalse(stringValues1.contains("critic"))
        
        // 验证 targetWithoutRawValue 嵌套枚举
        guard case .object(let targetWithoutRawValueProp) = properties["targetWithoutRawValue"] else {
            XCTFail("缺少 targetWithoutRawValue 属性")
            return
        }
        guard case .array(let enumValues2) = targetWithoutRawValueProp["enum"] else {
            XCTFail("targetWithoutRawValue 缺少 enum 数组")
            return
        }
        
        let stringValues2 = enumValues2.compactMap { val -> String? in
            if case .string(let str) = val { return str }
            return nil
        }
        XCTAssertTrue(stringValues2.contains("observer"))
    }
    func testDecodingFromJSON() throws {
        let jsonString = """
        {
            "content": "测试内容",
            "targetWithRawValue": "批判家",
            "targetWithoutRawValue": "observer"
        }
        """
        let jsonData = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        
        let args = try decoder.decode(MotionToolArgs.self, from: jsonData)
        
        XCTAssertEqual(args.content, "测试内容")
        XCTAssertEqual(args.targetWithRawValue, .critic)
        XCTAssertEqual(args.targetWithoutRawValue, .observer)
    }
}
