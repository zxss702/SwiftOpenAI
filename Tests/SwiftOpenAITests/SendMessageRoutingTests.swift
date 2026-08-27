import XCTest
@testable import SwiftOpenAI

final class SendMessageRoutingTests: XCTestCase {

    func testResponsesBranchRejectsPredictionBeforeNetwork() async {
        do {
            _ = try await sendMessage(
                modelInfo: .responses(.init(token: "api-key", modelID: "gpt-5")),
                messages: [.user("hello")],
                prediction: .init(type: "content", content: "prefill")
            ) { _ in }
            XCTFail("Expected Responses branch to reject prediction")
        } catch let error as OpenAIError {
            switch error {
            case .providerUnsupported(let message):
                XCTAssertTrue(message.contains("prediction"))
            default:
                XCTFail("Unexpected OpenAIError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCodexBranchRejectsPredictionBeforeNetwork() async {
        do {
            _ = try await sendMessage(
                modelInfo: .codex(.init(accessToken: "access-token", accountID: "account-id")),
                messages: [.user("hello")],
                prediction: .init(type: "content", content: "prefill")
            ) { _ in }
            XCTFail("Expected Codex branch to reject prediction")
        } catch let error as OpenAIError {
            switch error {
            case .providerUnsupported(let message):
                XCTAssertTrue(message.contains("prediction"))
            default:
                XCTFail("Unexpected OpenAIError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testResponsesBranchRejectsUserAndNonOneN() async {
        do {
            _ = try await sendMessage(
                modelInfo: .responses(.init(token: "api-key", modelID: "gpt-5")),
                messages: [.user("hello")],
                n: 2
            ) { _ in }
            XCTFail("Expected rejection for n != 1")
        } catch let error as OpenAIError {
            switch error {
            case .providerUnsupported(let message):
                XCTAssertTrue(message.contains("n != 1"))
            default:
                XCTFail("Unexpected OpenAIError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            _ = try await sendMessage(
                modelInfo: .responses(.init(token: "api-key", modelID: "gpt-5")),
                messages: [.user("hello")],
                user: "uid"
            ) { _ in }
            XCTFail("Expected rejection for user")
        } catch let error as OpenAIError {
            switch error {
            case .providerUnsupported(let message):
                XCTAssertTrue(message.contains("user"))
            default:
                XCTFail("Unexpected OpenAIError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
