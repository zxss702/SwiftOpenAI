import XCTest
@testable import SwiftOpenAI

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
enum NestedChoice: Codable {
    /// choice a
    case asyn
    case dd
}

@SYToolArgs
nonisolated struct NestedObjectArgs: Codable {
    /// 配置对象
    let config: NestedChoice
}

@SYToolArgs
enum AgentRoleWithRawValue: String, Codable, Sendable {
    case critic = "批判家"
    case visionary = "梦想家"
}

@SYToolArgs
enum AgentRoleWithoutRawValue: String, Codable, Sendable {
    case observer
    case reporter
}

@SYToolArgs
nonisolated struct MotionToolArgs: Codable, Sendable {
    /// 内容描述
    let content: String
    /// 带 rawValue 的角色
    let targetWithRawValue: AgentRoleWithRawValue
    /// 不带自定义 rawValue 的角色
    let targetWithoutRawValue: AgentRoleWithoutRawValue
}

@SYToolArgs
struct ForewordArgs {
    let 内容: String
}

@SYTool
struct ForewordTool {
    let name: String = "前言"
    let description: String = "向用户说明你下一步的计划。"
    let parameters = ForewordArgs.self
}

@SYToolArgs
struct CalculatorArgs {
    let message: String
    let count: Int?
}

@SYTool
struct CalculatorTool {
    let name = "test_tool"
    let description = "测试工具"
    let parameters = CalculatorArgs.self
}

@AIModelSchema
struct WeatherInfo: Codable {
    /// 当前温度
    let temperature: Double
    /// 天气状况
    let condition: String
}

final class ToolAndSchemaMacroTests: XCTestCase {

    func testArrayAndNestedEnumSchemas() {
        let arraySchema = SimpleArrayArgs.parametersSchema.toAnyDictionary()
        XCTAssertEqual(arraySchema["type"] as? String, "object")
        let arrayProps = arraySchema["properties"] as? [String: Any]
        XCTAssertEqual((arrayProps?["names"] as? [String: Any])?["type"] as? String, "array")
        XCTAssertEqual((arrayProps?["count"] as? [String: Any])?["type"] as? String, "integer")

        let nestedSchema = NestedObjectArgs.parametersSchema.toAnyDictionary()
        let config = (nestedSchema["properties"] as? [String: Any])?["config"] as? [String: Any]
        XCTAssertEqual(config?["type"] as? String, "string")
        XCTAssertEqual(config?["enum"] as? [String], ["asyn", "dd"])
    }

    func testToolPropertiesContainsFields() {
        let props = TestConfig.toolProperties
        XCTAssertTrue(props.contains("enabled"))
        XCTAssertTrue(props.contains("value"))
        XCTAssertTrue(NestedObjectArgs.toolProperties.contains("config"))
    }

    func testEnumRawValuesPreferCustomStrings() {
        guard case .array(let values) = AgentRoleWithRawValue.parametersSchema["enum"] else {
            return XCTFail("missing enum")
        }
        let strings = values.compactMap { value -> String? in
            if case .string(let string) = value { return string }
            return nil
        }
        XCTAssertTrue(strings.contains("批判家"))
        XCTAssertFalse(strings.contains("critic"))

        guard case .array(let plain) = AgentRoleWithoutRawValue.parametersSchema["enum"] else {
            return XCTFail("missing enum")
        }
        let plainStrings = plain.compactMap { value -> String? in
            if case .string(let string) = value { return string }
            return nil
        }
        XCTAssertEqual(Set(plainStrings), Set(["observer", "reporter"]))
    }

    func testNestedEnumArgsDecodeFromJSON() throws {
        let json = """
        {
          "content": "测试内容",
          "targetWithRawValue": "批判家",
          "targetWithoutRawValue": "observer"
        }
        """.data(using: .utf8)!
        let args = try JSONDecoder().decode(MotionToolArgs.self, from: json)
        XCTAssertEqual(args.content, "测试内容")
        XCTAssertEqual(args.targetWithRawValue, .critic)
        XCTAssertEqual(args.targetWithoutRawValue, .observer)
    }

    func testSYToolProducesChatCompletionToolAndArray() {
        let tools: [any OpenAIToolConvertible] = [CalculatorTool(), ForewordTool()]
        let chatTools = tools.map(\.asChatCompletionTool)
        XCTAssertEqual(chatTools[0].function.name, "test_tool")
        XCTAssertEqual(chatTools[1].function.name, "前言")
        XCTAssertEqual(chatTools[1].type, "function")
    }

    func testAIModelSchemaGeneratesObjectSchema() throws {
        let schema = try XCTUnwrap(WeatherInfo.outputSchema.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: schema) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "object")
        let properties = try XCTUnwrap(json["properties"] as? [String: Any])
        XCTAssertNotNil(properties["temperature"])
        XCTAssertNotNil(properties["condition"])
    }

    func testResponseFormatHelpersAcceptMacroTypes() {
        let fromToolArgs = ChatQuery.ResponseFormat.jsonSchema(name: "foreword", type: ForewordArgs.self)
        XCTAssertEqual(fromToolArgs.type, "json_schema")
        XCTAssertEqual(fromToolArgs.jsonSchema?.name, "foreword")

        let fromModel = ChatQuery.ResponseFormat.jsonSchema(name: "weather", type: WeatherInfo.self)
        XCTAssertEqual(fromModel.type, "json_schema")
        XCTAssertEqual(fromModel.jsonSchema?.name, "weather")
    }
}
