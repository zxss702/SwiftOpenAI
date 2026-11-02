import Foundation
import Crypto
import _CryptoExtras

/// Only validated ID-token identity is persisted by the Codex login manager.
public struct CodexIdentity: Sendable {
    public let subject: String
    public let email: String?

    public static func validate(
        token: String, clientID: String, nonce: String, jwks: Data, now: Date = .now
    ) throws -> Self {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw OpenAIError.streamingError("Invalid Codex ID token") }
        func decode(_ value: String) throws -> Data {
            var encoded = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
            guard let data = Data(base64Encoded: encoded) else {
                throw OpenAIError.streamingError("Invalid Codex JWT encoding")
            }
            return data
        }
        let header = try JSONSerialization.jsonObject(with: decode(String(parts[0]))) as? [String: Any]
        let payload = try JSONSerialization.jsonObject(with: decode(String(parts[1]))) as? [String: Any]
        let keySet = try JSONSerialization.jsonObject(with: jwks) as? [String: Any]
        guard header?["alg"] as? String == "RS256", let kid = header?["kid"] as? String,
              let keys = keySet?["keys"] as? [[String: Any]],
              let key = keys.first(where: { $0["kid"] as? String == kid && $0["kty"] as? String == "RSA" }),
              key["use"] == nil || key["use"] as? String == "sig",
              key["alg"] == nil || key["alg"] as? String == "RS256",
              let n = key["n"] as? String, let e = key["e"] as? String else {
            throw OpenAIError.streamingError("Invalid Codex signing key")
        }
        let publicKey = try _RSA.Signing.PublicKey(n: decode(n), e: decode(e))
        let signature = _RSA.Signing.RSASignature(rawRepresentation: try decode(String(parts[2])))
        guard publicKey.isValidSignature(signature, for: Data("\(parts[0]).\(parts[1])".utf8), padding: .insecurePKCS1v1_5),
              let payload, payload["iss"] as? String == "https://auth.openai.com",
              let expiration = payload["exp"] as? TimeInterval, expiration > now.timeIntervalSince1970,
              let subject = payload["sub"] as? String, !subject.isEmpty else {
            throw OpenAIError.streamingError("Invalid Codex ID token signature or claims")
        }
        let audiences = (payload["aud"] as? [String]) ?? (payload["aud"] as? String).map { [$0] } ?? []
        guard audiences.contains(clientID),
              (audiences.count == 1 || payload["azp"] as? String == clientID),
              (payload["nbf"] as? TimeInterval).map({ $0 <= now.timeIntervalSince1970 }) ?? true,
              payload["nonce"] as? String == nonce else {
            throw OpenAIError.streamingError("Invalid Codex ID token audience or nonce")
        }
        return Self(subject: subject, email: payload["email"] as? String)
    }
}
