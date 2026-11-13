import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 百炼临时文件（`oss://` URL）上传结果。
struct DashScopeTemporaryFile: Sendable {
    var ossURL: String
    var expiresAt: Date
}

private struct DashScopeUploadPolicyResponse: Decodable {
    struct Policy: Decodable {
        let policy: String
        let signature: String
        let uploadDir: String
        let uploadHost: String
        let ossAccessKeyID: String
        let xOssObjectAcl: String
        let xOssForbidOverwrite: String

        enum CodingKeys: String, CodingKey {
            case policy, signature
            case uploadDir = "upload_dir"
            case uploadHost = "upload_host"
            case ossAccessKeyID = "oss_access_key_id"
            case xOssObjectAcl = "x_oss_object_acl"
            case xOssForbidOverwrite = "x_oss_forbid_overwrite"
        }
    }

    let data: Policy
}

/// 上传文件到阿里百炼临时存储，返回约 48 小时有效的 `oss://` URL。
///
/// 流程：GET `{scheme+host}/api/v1/uploads?action=getPolicy&model=…`（Bearer）取 OSS 上传凭证
/// （凭证约 300s 有效，现取现传）→ multipart POST `upload_host`（`file` 域必须放最后）→ URL = `oss://` + key。
/// 后续推理请求须携带 `X-DashScope-OssResourceResolve: enable` 请求头（``ProviderRequestEncoder`` 已注入）。
///
/// - Note: 官方标注该接口不适合大规模生产使用；文件与 `modelID` 绑定，getPolicy 的 model
///   必须与后续调用模型完全一致；API Key 须与调用同一主账号；仅北京/新加坡地域。
///   Token Plan（`token-plan*.maas.aliyuncs.com`，`sk-sp-` Key）网关未路由该端点（实测 404 空 body），
///   ``offloadVisionMediaIfNeeded`` 对其跳过上传、保持内联 base64；
///   其条款要求仅限编程/智能体工具交互式使用，禁止自动化脚本、应用后端与批量调用，输入输出数据用于模型优化。
nonisolated func uploadDashScopeTemporaryFile(
    baseURL: String,
    bearerToken: String,
    modelID: String,
    fileData: Data,
    filename: String,
    extraHeaders: [String: String]? = nil,
    session: URLSession = openAIURLSession
) async throws -> DashScopeTemporaryFile {
    guard var components = URLComponents(url: try APIBaseURL.parse(baseURL), resolvingAgainstBaseURL: false) else {
        throw OpenAIError.invalidURL
    }
    components.path = "/api/v1/uploads"
    components.queryItems = [
        URLQueryItem(name: "action", value: "getPolicy"),
        URLQueryItem(name: "model", value: modelID)
    ]
    guard let policyURL = components.url else {
        throw OpenAIError.invalidURL
    }

    var policyRequest = URLRequest(url: policyURL)
    policyRequest.timeoutInterval = openAIURLRequestTimeout
    policyRequest.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
    policyRequest.setValue(OpenAIConfiguration.defaultUserAgent, forHTTPHeaderField: "User-Agent")
    for (key, value) in extraHeaders ?? [:] {
        policyRequest.setValue(value, forHTTPHeaderField: key)
    }

    let policyData: Data
    let policyResponse: URLResponse
    do {
        (policyData, policyResponse) = try await session.data(for: policyRequest)
    } catch {
        throw mapURLSessionTransportError(error)
    }
    let policyStatus = (policyResponse as? HTTPURLResponse)?.statusCode ?? 0
    guard (200...299).contains(policyStatus) else {
        let text = String(data: policyData, encoding: .utf8) ?? ""
        throw OpenAIError.invalidResponse(text, code: policyStatus)
    }
    let policy: DashScopeUploadPolicyResponse.Policy
    do {
        policy = try JSONDecoder().decode(DashScopeUploadPolicyResponse.self, from: policyData).data
    } catch {
        throw OpenAIError.decodingError(error)
    }

    guard let uploadHost = URL(string: policy.uploadHost) else {
        throw OpenAIError.invalidURL
    }
    let key = "\(policy.uploadDir)/\(filename)"
    let boundary = "Boundary-\(UUID().uuidString)"
    var body = Data()

    func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            body.append(data)
        }
    }
    func appendField(name: String, value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    appendField(name: "OSSAccessKeyId", value: policy.ossAccessKeyID)
    appendField(name: "policy", value: policy.policy)
    appendField(name: "Signature", value: policy.signature)
    appendField(name: "key", value: key)
    appendField(name: "x-oss-object-acl", value: policy.xOssObjectAcl)
    appendField(name: "x-oss-forbid-overwrite", value: policy.xOssForbidOverwrite)
    appendField(name: "success_action_status", value: "200")
    append("--\(boundary)\r\n")
    append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
    append("Content-Type: application/octet-stream\r\n\r\n")
    body.append(fileData)
    append("\r\n")
    append("--\(boundary)--\r\n")

    var uploadRequest = URLRequest(url: uploadHost)
    uploadRequest.httpMethod = "POST"
    uploadRequest.timeoutInterval = openAIURLRequestTimeout
    uploadRequest.httpBody = body
    uploadRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    let uploadData: Data
    let uploadResponse: URLResponse
    do {
        (uploadData, uploadResponse) = try await session.data(for: uploadRequest)
    } catch {
        throw mapURLSessionTransportError(error)
    }
    let uploadStatus = (uploadResponse as? HTTPURLResponse)?.statusCode ?? 0
    guard (200...299).contains(uploadStatus) else {
        let text = String(data: uploadData, encoding: .utf8) ?? ""
        throw OpenAIError.invalidResponse(text, code: uploadStatus)
    }

    return DashScopeTemporaryFile(
        ossURL: "oss://\(key)",
        expiresAt: Date().addingTimeInterval(48 * 3600)
    )
}
