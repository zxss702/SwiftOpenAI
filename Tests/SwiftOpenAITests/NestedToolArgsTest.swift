import XCTest
@testable import SwiftOpenAI

final class NestedToolArgsTest: XCTestCase {

    // 测试简单的数组类型处理
    @SYToolArgs
    nonisolated struct SimpleArrayArgs: Codable {
        let names: [String]
        let count: Int
    }

    // 测试嵌套对象类型处理
    @SYToolArgs
    nonisolated struct NestedObjectArgs: Codable {
        let config: Config
    }

    @SYToolArgs
    nonisolated struct Config: Codable {
        let enabled: Bool
        let value: String
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
        let configSchema = Config.parametersSchema

        print("\n=== Config Schema ===")
        print(configSchema)

        // 验证Config的schema结构
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
}
