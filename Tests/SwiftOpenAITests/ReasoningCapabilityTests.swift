import XCTest
@testable import SwiftOpenAI

final class ReasoningCapabilityTests: XCTestCase {
    private func body(_ model: String, _ ratio: Double?, _ wire: AIModelWireAPI = .completions,
                      family: ProviderFamily = .genericOpenAICompatible) -> [String: Any] {
        var body: [String: Any] = [:]
        ReasoningCapability.resolve(model: model, family: family, wireAPI: wire)
            .apply(to: &body, ratio: ratio, wireAPI: wire)
        return body
    }

    func testDeepSeekFlashAndProBoundaries() {
        let id = "deepseek/deepseek-v4.1-flash"
        XCTAssertEqual((body(id, 0)["thinking"] as? [String: String])?["type"], "disabled")
        XCTAssertNil(body(id, 0)["reasoning_effort"])
        for (ratio, effort) in [(Double.leastNonzeroMagnitude, "low"), ((1.0/3).nextDown, "low"),
                                (1.0/3, "high"), ((2.0/3).nextDown, "high"), (2.0/3, "max"), (1, "max")] {
            XCTAssertEqual(body(id, ratio)["reasoning_effort"] as? String, effort)
        }
        XCTAssertEqual(body("deepseek-v4-pro-0813", 0.2)["reasoning_effort"] as? String, "low")
    }

    func testUnknownFallbackAndInvalidInputs() {
        let id = "unknown"
        XCTAssertTrue(body(id, nil).isEmpty)
        XCTAssertTrue(body(id, .nan).isEmpty)
        XCTAssertTrue(body(id, .infinity).isEmpty)
        XCTAssertEqual(body(id, -1)["reasoning_effort"] as? String, "none")
        XCTAssertEqual(body(id, 2)["reasoning_effort"] as? String, "max")
        for (index, effort) in ReasoningCapability.standard.enumerated() {
            let ratio = (Double(index) + 0.5) / 6
            XCTAssertEqual(body(id, ratio)["reasoning_effort"] as? String, effort)
        }
    }

    func testTransportControlsAndNonReasoningModels() {
        XCTAssertTrue(body("gpt-4o", 1, .responses, family: .openai).isEmpty)
        XCTAssertEqual((body("gpt-5", 0, .responses)["reasoning"] as? [String: String])?["effort"], "minimal")
        XCTAssertEqual((body("gpt-5.4", 0, .codexResponses)["reasoning"] as? [String: String])?["effort"], "none")
        let claude = body("claude-opus-4-6", 1, .anthropic)
        XCTAssertEqual((claude["thinking"] as? [String: String])?["type"], "adaptive")
        XCTAssertEqual((claude["output_config"] as? [String: String])?["effort"], "max")
        XCTAssertNil(body("qwen3-vl-thinking", 0)["enable_thinking"])
        XCTAssertNotNil(body("qwen3-vl-thinking", 0)["thinking_budget"])
    }

    func testDeepSeekMessagesAndResponsesUseTheirOwnFields() {
        let id = "deepseek-v4.1-flash"
        let messages = body(id, 0, .anthropic)
        XCTAssertEqual((messages["output_config"] as? [String: String])?["effort"], "none")
        XCTAssertNil(messages["reasoning"])
        XCTAssertNil(messages["thinking"])
        let responses = body(id, 0.5, .responses)
        XCTAssertEqual((responses["reasoning"] as? [String: String])?["effort"], "high")
        XCTAssertNil(responses["thinking"])
    }

    func testExplicitZeroReplacesOldSettingsWithoutDroppingOtherFields() {
        var request: [String: Any] = [
            "thinking": ["type": "enabled", "budget_tokens": 10000],
            "output_config": ["effort": "high", "format": ["type": "json_schema"]]
        ]
        ReasoningCapability.resolve(model: "deepseek-v4.1-flash", family: .deepseek, wireAPI: .anthropic)
            .apply(to: &request, ratio: 0, wireAPI: .anthropic)
        XCTAssertNil(request["thinking"])
        let output = request["output_config"] as? [String: Any]
        XCTAssertEqual(output?["effort"] as? String, "none")
        XCTAssertNotNil(output?["format"])
    }

    func testMandatoryReasoningUsesLowestTierAtZero() {
        XCTAssertEqual(body("grok-4.7", 0, family: .xai)["reasoning_effort"] as? String, "low")
        XCTAssertEqual(body("kimi-k3.1-pro", 0, family: .tokenDance)["reasoning_effort"] as? String, "low")
        XCTAssertEqual(body("glm-5.3-flashx", 0, family: .tokenDance)["reasoning_effort"] as? String, "low")
        XCTAssertEqual(body("minimax-m3.1-flash", 0, family: .tokenDance)["reasoning_effort"] as? String, "low")
    }

}
