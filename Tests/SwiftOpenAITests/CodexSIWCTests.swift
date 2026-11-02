import XCTest
import _CryptoExtras
@testable import SwiftOpenAI

final class CodexSIWCTests: XCTestCase {
    func testSIWCConstraintsDoNotChangeAPIKeyResponses() throws {
        for wire in [AIModelWireAPI.codexResponses, .responses] {
            let body = try makeResponsesRequestBody(
                modelID: "gpt-5.6-luna", messages: [.system("rules"), .user("hello")],
                frequencyPenalty: nil, maxCompletionTokens: 100, parallelToolCalls: nil,
                presencePenalty: nil, responseFormat: nil, stop: nil, temperature: 0.5,
                toolChoice: nil, tools: nil, topP: 0.9, thinkLevel: nil,
                extraBody: ["stream": .bool(false), "store": .bool(true),
                    "previous_response_id": .string("resp_old"), "metadata": .object([:])],
                baseURL: "https://api.openai.com/v1", wireAPI: wire)
            if wire == .codexResponses {
                XCTAssertEqual(body["stream"] as? Bool, true)
                XCTAssertEqual(body["store"] as? Bool, false)
                for key in ["temperature", "top_p", "max_output_tokens", "previous_response_id", "metadata"] {
                    XCTAssertNil(body[key])
                }
            } else {
                XCTAssertEqual(body["temperature"] as? Double, 0.5)
                XCTAssertEqual(body["max_output_tokens"] as? Int, 100)
                XCTAssertEqual(body["previous_response_id"] as? String, "resp_old")
                XCTAssertEqual(body["store"] as? Bool, true)
                XCTAssertEqual(body["stream"] as? Bool, false)
            }
        }
    }

    func testLocalToolsAreAddedToInputWithoutChangingTheirNames() throws {
        let body = try makeResponsesRequestBody(
            modelID: "gpt-5.6-luna", messages: [.user("hello")], frequencyPenalty: nil,
            maxCompletionTokens: nil, parallelToolCalls: nil, presencePenalty: nil,
            responseFormat: nil, stop: nil, temperature: nil, toolChoice: nil,
            tools: nil, topP: nil, thinkLevel: nil,
            extraBody: ["tools": .array([.object(["type": .string("function"), "name": .string("read_file"),
                "parameters": .object(["type": .string("object")])])])], wireAPI: .codexResponses)
        XCTAssertNil(body["tools"])
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        XCTAssertEqual(input.first?["type"] as? String, "additional_tools")
        XCTAssertEqual(input.first?["role"] as? String, "developer")
        XCTAssertEqual((input.first?["tools"] as? [[String: Any]])?.first?["name"] as? String, "read_file")
    }

    func testStreamFailurePreservesCodeParamAndRequestID() async throws {
        let helper = OpenAISendMessageValueHelper()
        var state = ResponsesStreamState()
        var metadata = ChatResponseMetadata(providerName: "openai-codex", requestID: "req_test",
            resolvedModel: "test", resolvedBasePath: "/v1")
        let sse = try TestFixtures.makeSSELine(["type": "response.failed", "response": ["error": [
            "code": "subscription_sharing_usage_unavailable", "param": "usage", "message": "try later"
        ]]]) + "\n"
        do {
            try await processResponsesSSEBytes(Data(sse.utf8), actorHelper: helper, state: &state, metadata: &metadata)
            XCTFail("Expected a structured SIWC error")
        } catch let error as CodexResponseError {
            XCTAssertEqual(error.code, "subscription_sharing_usage_unavailable")
            XCTAssertEqual(error.param, "usage")
            XCTAssertEqual(error.requestID, "req_test")
        }
    }

    func testIdentityRequiresSignatureAudienceNonceAndUnexpiredClaims() throws {
        let key = try _RSA.Signing.PrivateKey(keySize: .bits2048)
        let primitives = try key.publicKey.getKeyPrimitives()
        func base64(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let jwks = try JSONSerialization.data(withJSONObject: ["keys": [["kid": "test", "kty": "RSA",
            "n": base64(primitives.modulus), "e": base64(primitives.publicExponent)]]])
        let header = base64(try JSONSerialization.data(withJSONObject: ["kid": "test", "alg": "RS256"]))
        let payload = base64(try JSONSerialization.data(withJSONObject: ["iss": "https://auth.openai.com",
            "aud": "oaiapp_test", "sub": "subject", "nonce": "nonce", "exp": 2000]))
        let signed = "\(header).\(payload)"
        let signature = try key.signature(for: Data(signed.utf8), padding: .insecurePKCS1v1_5)
        let token = "\(signed).\(base64(signature.rawRepresentation))"
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(try CodexIdentity.validate(token: token, clientID: "oaiapp_test", nonce: "nonce", jwks: jwks, now: now).subject, "subject")
        XCTAssertThrowsError(try CodexIdentity.validate(token: token, clientID: "wrong", nonce: "nonce", jwks: jwks, now: now))
        XCTAssertThrowsError(try CodexIdentity.validate(token: token, clientID: "oaiapp_test", nonce: "wrong", jwks: jwks, now: now))
        XCTAssertThrowsError(try CodexIdentity.validate(token: token, clientID: "oaiapp_test", nonce: "nonce", jwks: jwks, now: Date(timeIntervalSince1970: 2001)))
        let badToken = "\(signed).\(base64(Data(repeating: 0, count: signature.rawRepresentation.count)))"
        XCTAssertThrowsError(try CodexIdentity.validate(token: badToken, clientID: "oaiapp_test", nonce: "nonce", jwks: jwks, now: now))
    }
}
