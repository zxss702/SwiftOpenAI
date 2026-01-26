import XCTest
@testable import SwiftOpenAI

// 测试用的结构体定义（移到类外部以避免作用域问题）

// 测试简单的数组类型处理
@SYToolArgs
nonisolated struct SimpleArrayArgs: Codable {
    let names: [String]
    let count: Int
}

@SYToolArgs
nonisolated struct TestConfig: Codable {
    let enabled: Bool
    let value: String
}

@SYToolArgs
enum A: Codable {
    case asyn
    case dd
}

// 测试嵌套对象类型处理
@SYToolArgs
nonisolated struct NestedObjectArgs: Codable {
    /// 配置对象
    let config: A
}

final class NestedToolArgsTest: XCTestCase {

    func testOutPut() {
        print(NestedObjectArgs.toolProperties)
        print(NestedObjectArgs.parametersSchema)
    }
    
    func testArraySchema() {
        // 测试数组类型的schema生成
        let schema = SimpleArrayArgs.parametersSchema

        print("=== SimpleArrayArgs Schema ===")
        print(schema)

        XCTAssertEqual(schema["type"] as? String, "object")
        XCTAssertNotNil(schema["properties"])

        if let properties = schema["properties"] as? [String: Any] {
            // 检查names属性（应该是数组类型）
            XCTAssertNotNil(properties["names"])
            XCTAssertNotNil(properties["count"])

            if let namesProperty = properties["names"] as? [String: Any] {
                XCTAssertEqual(namesProperty["type"] as? String, "array")
                XCTAssertNotNil(namesProperty["items"])

                if let items = namesProperty["items"] as? [String: Any] {
                    XCTAssertEqual(items["type"] as? String, "string")
                }
            }

            if let countProperty = properties["count"] as? [String: Any] {
                XCTAssertEqual(countProperty["type"] as? String, "integer")
            }
        }
    }

    func testNestedObjectSchema() {
        // 测试嵌套对象的schema生成
        let schema = NestedObjectArgs.parametersSchema

        print("\n=== NestedObjectArgs Schema ===")
        print(schema)

        XCTAssertEqual(schema["type"] as? String, "object")
        XCTAssertNotNil(schema["properties"])

        if let properties = schema["properties"] as? [String: Any] {
            // 检查config属性（应该是对象类型）
            XCTAssertNotNil(properties["config"])

            if let configProperty = properties["config"] as? [String: Any] {
                XCTAssertEqual(configProperty["type"] as? String, "object")
                XCTAssertNotNil(configProperty["description"])
            }
        }
    }

    func testIndividualSchemas() {
        // 分别测试每个类型的schema
        let simpleSchema = SimpleArrayArgs.parametersSchema
        let nestedSchema = NestedObjectArgs.parametersSchema
        let configSchema = TestConfig.parametersSchema

        print("\n=== TestConfig Schema ===")
        print(configSchema)

        // 验证TestConfig的schema结构
        XCTAssertEqual(configSchema["type"] as? String, "object")
        XCTAssertNotNil(configSchema["properties"])

        if let properties = configSchema["properties"] as? [String: Any] {
            XCTAssertNotNil(properties["enabled"])
            XCTAssertNotNil(properties["value"])

            if let enabledProperty = properties["enabled"] as? [String: Any] {
                XCTAssertEqual(enabledProperty["type"] as? String, "boolean")
            }

            if let valueProperty = properties["value"] as? [String: Any] {
                XCTAssertEqual(valueProperty["type"] as? String, "string")
            }
        }
    }
    
    func testToolProperties() {
        // 测试新增的 toolProperties 功能
        print("\n=== TestConfig.toolProperties ===")
        print(TestConfig.toolProperties)
        
        print("\n=== SimpleArrayArgs.toolProperties ===")
        print(SimpleArrayArgs.toolProperties)
        
        print("\n=== NestedObjectArgs.toolProperties ===")
        print(NestedObjectArgs.toolProperties)
        
        // 验证 toolProperties 是有效的 JSON 片段
        let configProps = TestConfig.toolProperties
        XCTAssertFalse(configProps.isEmpty)
        XCTAssertTrue(configProps.contains("enabled"))
        XCTAssertTrue(configProps.contains("value"))
        
        // 验证嵌套结构正确引用了子类型的 toolProperties
        let nestedProps = NestedObjectArgs.toolProperties
        XCTAssertTrue(nestedProps.contains("config"))
    }
    
    func testNestedObjectPropertiesStructure() {
        // 深入测试嵌套对象的 properties 结构
        let schema = NestedObjectArgs.parametersSchema
        
        if let properties = schema["properties"] as? [String: Any],
           let configProperty = properties["config"] as? [String: Any] {
            
            // 验证 config 属性包含 properties 字段（嵌套属性）
            XCTAssertNotNil(configProperty["properties"], "嵌套对象应该包含 properties 字段")
            
            if let configProps = configProperty["properties"] as? [String: Any] {
                // 验证嵌套对象的内部属性
                XCTAssertNotNil(configProps["enabled"], "应该包含 enabled 属性")
                XCTAssertNotNil(configProps["value"], "应该包含 value 属性")
                
                if let enabledProp = configProps["enabled"] as? [String: Any] {
                    XCTAssertEqual(enabledProp["type"] as? String, "boolean")
                }
                
                if let valueProp = configProps["value"] as? [String: Any] {
                    XCTAssertEqual(valueProp["type"] as? String, "string")
                }
            }
        } else {
            XCTFail("未能正确解析嵌套对象的结构")
        }
    }
}
