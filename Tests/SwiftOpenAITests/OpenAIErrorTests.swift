import XCTest
@testable import SwiftOpenAI

final class OpenAIErrorTests: XCTestCase {

    func testLocalizedDescriptions() {
        XCTAssertEqual(OpenAIError.missingModelID.errorDescription, "缺少模型ID")
        XCTAssertEqual(OpenAIError.invalidURL.errorDescription, "无效的URL")
        XCTAssertEqual(OpenAIError.missingToken.errorDescription, "缺少API密钥")
        XCTAssertEqual(
            OpenAIError.invalidResponse("oops", code: 400).errorDescription,
            "无效的响应: oops"
        )
        XCTAssertEqual(
            OpenAIError.providerUnsupported("nope").errorDescription,
            "厂商能力不支持: nope"
        )
        XCTAssertEqual(
            OpenAIError.unsupportedParameterCombination("bad").errorDescription,
            "参数组合不支持: bad"
        )
        XCTAssertEqual(
            OpenAIError.streamingError("cut").errorDescription,
            "流式传输错误: cut"
        )
        XCTAssertEqual(
            OpenAIError.requestBodyTooLarge("big").errorDescription,
            "请求体过大: big"
        )
    }
}
