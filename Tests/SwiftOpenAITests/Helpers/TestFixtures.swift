import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import SwiftOpenAI

enum TestFixtures {
    static let tinyPNG = Data([0x89, 0x50, 0x4E, 0x47])
    static let tinyVideo = Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70])

    static func requestBody(from request: URLRequest) throws -> [String: Any] {
        let body = try XCTUnwrap(request.httpBody)
        let jsonObject = try JSONSerialization.jsonObject(with: body, options: [])
        return try XCTUnwrap(jsonObject as? [String: Any])
    }

    static func makeSSELine(_ payload: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        return "data: " + String(decoding: data, as: UTF8.self)
    }

    static func weatherTool(strict: Bool? = true) -> ChatQuery.ChatCompletionToolParam {
        ChatQuery.ChatCompletionToolParam(
            type: "function",
            function: ChatQuery.ChatCompletionToolParam.Function(
                name: "get_weather",
                description: "查询天气",
                strict: strict,
                parameters: [
                    "type": .string("object"),
                    "properties": .object([
                        "city": .object([
                            "type": .string("string")
                        ])
                    ]),
                    "required": .array([.string("city")]),
                    "additionalProperties": .bool(false)
                ]
            )
        )
    }

    static func sampleJsonSchemaFormat() -> ChatQuery.ResponseFormat {
        ChatQuery.ResponseFormat(
            type: "json_schema",
            jsonSchema: .init(
                name: "person",
                description: "A person",
                strict: true,
                schema: [
                    "type": .string("object"),
                    "properties": .object([
                        "name": .object(["type": .string("string")])
                    ]),
                    "required": .array([.string("name")]),
                    "additionalProperties": .bool(false)
                ]
            )
        )
    }

    static func configuration(
        baseURL: String = "https://api.openai.com/v1",
        token: String = "test-token"
    ) -> OpenAIConfiguration {
        OpenAIConfiguration(token: token, baseURL: baseURL)
    }
}
