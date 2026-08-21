import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if !os(Windows)
import AsyncHTTPClient
import NIOHTTP1
#endif

enum ProviderFamily: String, Sendable {
    case openai
    case moonshot
    case minimax
    case zhipuGLM
    case volcengineArk
    case dashscope
    case genericOpenAICompatible
    case deepseek

    var providerName: String {
        switch self {
        case .openai:
            return "openai"
        case .moonshot:
            return "moonshot"
        case .minimax:
            return "minimax"
        case .zhipuGLM:
            return "zhipu-glm"
        case .volcengineArk:
            return "volcengine-ark"
        case .dashscope:
            return "dashscope"
        case .genericOpenAICompatible:
            return "generic-openai-compatible"
        case .deepseek:
            return "deepseek"
        }
    }

    var assistantReasoningEncoding: AssistantReasoningEncoding {
        switch self {
        case .minimax:
            return .reasoningDetails
        case .openai, .zhipuGLM, .volcengineArk, .dashscope, .genericOpenAICompatible, .moonshot, .deepseek:
            return .reasoningContent
        }
    }

    /// 按模型返回图像/视频多模态能力（DeepSeek 视觉模型可单独放开图片）
    func multimediaCapability(for model: String) -> MultimediaCapability {
        switch self {
        case .minimax:
            return MultimediaCapability(supportsImage: false, supportsVideo: false)
        case .deepseek:
            if model.lowercased() == "deepseek-v4-flash-vision-exp" {
                return MultimediaCapability(supportsImage: true, supportsVideo: false)
            }
            return MultimediaCapability(supportsImage: false, supportsVideo: false)
        case .openai, .moonshot, .zhipuGLM, .volcengineArk, .dashscope, .genericOpenAICompatible:
            return MultimediaCapability(supportsImage: true, supportsVideo: true)
        }
    }

    /// 该 Provider 是否支持 function 级 strict（工具参数严格遵循 JSON Schema）
    ///
    /// 不支持的 Provider 即使工具声明了 strict 也会在发送时剥除该字段。
    var supportsToolStrict: Bool {
        switch self {
        case .openai, .moonshot, .deepseek:
            return true
        case .zhipuGLM, .minimax, .volcengineArk, .dashscope, .genericOpenAICompatible:
            return false
        }
    }

    /// `.reminder` 出站时映射到的 wire role
    var reminderWireRole: ReminderWireRole {
        switch self {
        case .deepseek:
            return .latestReminder
        case .moonshot, .openai:
            return .system
        case .dashscope, .volcengineArk, .zhipuGLM, .minimax, .genericOpenAICompatible:
            return .user
        }
    }

    /// 该 Provider 对 `response_format` 的最高支持级别
    ///
    /// 发送前会把请求的格式自动降级到不超过该级别：
    /// `json_schema` → `json_object` → 去掉 `response_format`。
    var responseFormatCapability: ResponseFormatCapability {
        switch self {
        case .openai, .moonshot, .volcengineArk, .dashscope:
            return .jsonSchema
        case .deepseek, .zhipuGLM, .genericOpenAICompatible:
            return .jsonObject
        case .minimax:
            return .none
        }
    }
}

/// 出站消息对图像 / 视频的支持能力
struct MultimediaCapability: Sendable {
    var supportsImage: Bool
    var supportsVideo: Bool
}

/// Chat Completions `response_format` 能力层级（声明顺序即 Comparable 顺序）
enum ResponseFormatCapability: Comparable, Sendable {
    case none
    case jsonObject
    case jsonSchema
}

enum ReminderWireRole: Sendable {
    case latestReminder
    case system
    case user
}

enum AssistantReasoningEncoding: Sendable {
    case reasoningContent
    case reasoningDetails
    case omit
}

struct ChatResponseMetadata: Sendable {
    let providerName: String
    let requestID: String?
    let resolvedModel: String
    let resolvedBasePath: String

    func withRequestID(_ requestID: String?) -> ChatResponseMetadata {
        ChatResponseMetadata(
            providerName: providerName,
            requestID: requestID ?? self.requestID,
            resolvedModel: resolvedModel,
            resolvedBasePath: resolvedBasePath
        )
    }
}

struct PreparedChatRequest: Sendable {
    let urlRequest: URLRequest
    let family: ProviderFamily
    let metadata: ChatResponseMetadata
}

struct ChatStreamEnvelope: Sendable {
    let result: ChatStreamResult
    let metadata: ChatResponseMetadata
}

struct ChatCompletionEnvelope: Sendable {
    let result: ChatCompletionResult
    let metadata: ChatResponseMetadata
}

struct ReasoningDetailPayload: Codable, Sendable {
    let text: String?
}

struct CanonicalChatRequest: Sendable {
    let messages: [ChatQuery.ChatCompletionMessageParam]
    let model: String
    let frequencyPenalty: Double?
    let maxCompletionTokens: Int?
    let n: Int?
    let parallelToolCalls: Bool?
    let prediction: ChatQuery.PredictedOutputConfig?
    let presencePenalty: Double?
    let responseFormat: ChatQuery.ResponseFormat?
    let stop: ChatQuery.Stop?
    let temperature: Double?
    let toolChoice: ChatQuery.ChatCompletionFunctionCallOptionParam?
    let tools: [ChatQuery.ChatCompletionToolParam]?
    let topP: Double?
    let user: String?
    let stream: Bool?
    let thinkLevel: ThinkLevel?
    let mergedExtraBody: [String: AnyCodableValue]
}

enum ProviderFamilyResolver {
    static func resolve(host: String) -> ProviderFamily {
        let normalizedHost = normalize(host: host)

        if normalizedHost == "api.openai.com" {
            return .openai
        }
        if normalizedHost == "api.moonshot.cn"
            || normalizedHost == "api.kimi.com"
            || normalizedHost.hasSuffix(".moonshot.cn")
            || normalizedHost.hasSuffix(".kimi.com") {
            return .moonshot
        }
        if normalizedHost == "api.minimax.io"
            || normalizedHost == "api.minimaxi.com"
            || normalizedHost.hasSuffix(".minimax.io")
            || normalizedHost.hasSuffix(".minimaxi.com") {
            return .minimax
        }
        if normalizedHost == "open.bigmodel.cn" || normalizedHost.hasSuffix(".bigmodel.cn") {
            return .zhipuGLM
        }
        if normalizedHost == "dashscope.aliyuncs.com"
            || normalizedHost == "dashscope-intl.aliyuncs.com"
            || normalizedHost == "dashscope-us.aliyuncs.com"
            || normalizedHost.hasSuffix(".aliyuncs.com") && normalizedHost.contains("dashscope") {
            return .dashscope
        }
        if normalizedHost.hasSuffix(".volces.com") {
            return .volcengineArk
        }
        if normalizedHost.contains("deepseek.com") {
            return .deepseek
        }
        return .genericOpenAICompatible
    }

    static func normalize(host: String) -> String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let separatorIndex = trimmed.firstIndex(of: ":") {
            return String(trimmed[..<separatorIndex])
        }
        return trimmed
    }
}

enum ProviderCompatibilityValidator {
    static func validate(_ request: CanonicalChatRequest, family: ProviderFamily) throws {
        switch family {
        case .minimax:
            if let n = request.n, n != 1 {
                throw OpenAIError.providerUnsupported("MiniMax 兼容接口只支持 n = 1")
            }
        case .moonshot:
            let isThinkingModel = request.model.lowercased().contains("thinking")
            if isThinkingModel, let tools = request.tools, !tools.isEmpty {
                throw OpenAIError.unsupportedParameterCombination("Moonshot 思考模型暂不支持 tools")
            }
            // Moonshot thinking 模型的 response_format 由 normalizeResponseFormat 剥离，不再硬抛错
        case .openai, .zhipuGLM, .volcengineArk, .dashscope, .genericOpenAICompatible, .deepseek:
            break
        }
    }

}

enum ProviderRequestEncoder {
    static func makeRequest(query: ChatQuery, configuration: OpenAIConfiguration) throws -> PreparedChatRequest {
        let family = ProviderFamilyResolver.resolve(host: configuration.host)
        let canonicalRequest = CanonicalChatRequest(
            messages: query.messages,
            model: query.model,
            frequencyPenalty: query.frequencyPenalty,
            maxCompletionTokens: query.maxCompletionTokens,
            n: query.n,
            parallelToolCalls: query.parallelToolCalls,
            prediction: query.prediction,
            presencePenalty: query.presencePenalty,
            responseFormat: normalizeResponseFormat(
                query.responseFormat,
                family: family,
                model: query.model
            ),
            stop: query.stop,
            temperature: query.temperature,
            toolChoice: query.toolChoice,
            tools: query.tools,
            topP: query.topP,
            user: query.user,
            stream: query.stream,
            thinkLevel: query.thinkLevel,
            mergedExtraBody: mergeExtraBody(configuration.extraBody, query.extraBody)
        )

        try ProviderCompatibilityValidator.validate(canonicalRequest, family: family)
        var normalizedBasePath = normalizedBasePath(from: configuration.basePath)
        // DeepSeek strict 工具需要 base_url 为 /beta；仅在用户未显式配置非 /v1 路径时自动切换
        if family == .deepseek,
           normalizedBasePath == "/v1/chat/completions",
           canonicalRequest.tools?.contains(where: { $0.function.strict == true }) == true {
            normalizedBasePath = "/beta/chat/completions"
        }
        let requestURL = try makeRequestURL(configuration: configuration, normalizedBasePath: normalizedBasePath)

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")

        if let organizationID = configuration.organizationID {
            request.setValue(organizationID, forHTTPHeaderField: "OpenAI-Organization")
        }

        var headers = configuration.extraHeaders ?? [:]
        if headers["User-Agent"] == nil {
            headers["User-Agent"] = OpenAIConfiguration.defaultUserAgent
        }
        if headers["X-Title"] == nil {
            headers["X-Title"] = OpenAIConfiguration.defaultXTitle
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let body = try buildRequestBody(from: canonicalRequest, family: family)
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])

        return PreparedChatRequest(
            urlRequest: request,
            family: family,
            metadata: ChatResponseMetadata(
                providerName: family.providerName,
                requestID: nil,
                resolvedModel: canonicalRequest.model,
                resolvedBasePath: normalizedBasePath
            )
        )
    }

    private static func buildRequestBody(from request: CanonicalChatRequest, family: ProviderFamily) throws -> [String: Any] {
        var body: [String: Any] = [
            "messages": try encodeMessages(request.messages, family: family, model: request.model),
            "model": request.model
        ]

        if let frequencyPenalty = request.frequencyPenalty {
            body["frequency_penalty"] = frequencyPenalty
        }
        if let maxCompletionTokens = request.maxCompletionTokens {
            switch family {
            case .openai:
                body["max_completion_tokens"] = maxCompletionTokens
            case .moonshot, .minimax, .zhipuGLM, .volcengineArk, .dashscope, .genericOpenAICompatible, .deepseek:
                body["max_tokens"] = maxCompletionTokens
            }
        }
        if let n = request.n {
            body["n"] = n
        }
        if let parallelToolCalls = request.parallelToolCalls {
            body["parallel_tool_calls"] = parallelToolCalls
        }
        if let prediction = request.prediction {
            body["prediction"] = try jsonValue(prediction)
        }
        if let presencePenalty = request.presencePenalty {
            body["presence_penalty"] = presencePenalty
        }
        if let responseFormat = request.responseFormat {
            body["response_format"] = try encodeResponseFormat(responseFormat)
        }
        if let stop = request.stop {
            body["stop"] = try jsonValue(stop)
        }
        if let temperature = request.temperature {
            body["temperature"] = temperature
        }
        if let toolChoice = request.toolChoice {
            body["tool_choice"] = try encodeToolChoice(toolChoice)
        }
        if let tools = request.tools {
            body["tools"] = try encodeTools(tools, family: family)
        }
        if let topP = request.topP {
            body["top_p"] = topP
        }
        if let user = request.user {
            body["user"] = user
        }
        if let stream = request.stream {
            body["stream"] = stream
        }

        for (key, value) in request.mergedExtraBody {
            body[key] = value.anyValue
        }
        applyProviderDefaults(into: &body, request: request, family: family)
        applyThinking(
            into: &body,
            thinkLevel: request.thinkLevel,
            family: family
        )

        return body
    }

    private static func encodeMessages(
        _ messages: [ChatQuery.ChatCompletionMessageParam],
        family: ProviderFamily,
        model: String
    ) throws -> [[String: Any]] {
        let capability = family.multimediaCapability(for: model)
        return try messages.map { try encodeMessage($0, family: family, capability: capability) }
    }

    /// 不支持多媒体时：保留文本并追加提示，避免整条删除导致 tool_call 不配对
    private static func plaintextReplacingUnsupportedMultimedia(
        texts: [String],
        hasImage: Bool,
        hasVideo: Bool
    ) -> String {
        var segments = texts.filter { !$0.isEmpty }
        if hasImage {
            segments.append("image 不支持")
        }
        if hasVideo {
            segments.append("video 不支持")
        }
        return segments.joined(separator: "\n")
    }

    private static func encodeImageURLPart(url: String, detail: String) -> [String: Any] {
        [
            "type": "image_url",
            "image_url": [
                "url": url,
                "detail": detail
            ] as [String: Any]
        ]
    }

    private static func encodeVideoURLPart(url: String, fps: Double?) -> [String: Any] {
        var videoDict: [String: Any] = ["url": url]
        if let fps {
            videoDict["fps"] = fps
        }
        return [
            "type": "video_url",
            "video_url": videoDict
        ]
    }

    /// 按能力过滤图/视频：全不支持则降为纯文本；部分支持则保留可用 parts 并追加提示
    private static func finalizeMultimediaContent(
        encodedParts: [[String: Any]],
        texts: [String],
        hasUnsupportedImage: Bool,
        hasUnsupportedVideo: Bool,
        keptSupportedMedia: Bool
    ) -> Any {
        let hasUnsupported = hasUnsupportedImage || hasUnsupportedVideo
        if !hasUnsupported {
            return encodedParts
        }
        if !keptSupportedMedia {
            return plaintextReplacingUnsupportedMultimedia(
                texts: texts,
                hasImage: hasUnsupportedImage,
                hasVideo: hasUnsupportedVideo
            )
        }
        var parts = encodedParts
        if hasUnsupportedImage {
            parts.append(["type": "text", "text": "image 不支持"])
        }
        if hasUnsupportedVideo {
            parts.append(["type": "text", "text": "video 不支持"])
        }
        return parts
    }

    private static func encodeMessage(
        _ message: ChatQuery.ChatCompletionMessageParam,
        family: ProviderFamily,
        capability: MultimediaCapability
    ) throws -> [String: Any] {
        switch message {
        case .system(let systemMessage):
            var encoded: [String: Any] = ["role": "system"]
            if case .textContent(let text) = systemMessage.content {
                encoded["content"] = text
            }
            if let name = systemMessage.name {
                encoded["name"] = name
            }
            return encoded

        case .user(let userMessage):
            var encoded: [String: Any] = ["role": "user"]
            encoded["content"] = encodeUserContent(
                userMessage.content,
                capability: capability
            )
            if let name = userMessage.name {
                encoded["name"] = name
            }
            return encoded

        case .assistant(let assistantMessage):
            var encoded: [String: Any] = ["role": "assistant"]
            if let content = assistantMessage.content {
                encoded["content"] = content
            }
            if let name = assistantMessage.name {
                encoded["name"] = name
            }
            if let toolCalls = assistantMessage.toolCalls {
                encoded["tool_calls"] = try toolCalls.map { try jsonValue($0) }
            }
            if let reasoningContent = assistantMessage.reasoningContent {
                switch family.assistantReasoningEncoding {
                case .reasoningContent:
                    encoded["reasoning_content"] = reasoningContent
                case .reasoningDetails:
                    encoded["reasoning_details"] = [
                        ["text": reasoningContent]
                    ]
                case .omit:
                    break
                }
            }
            return encoded

        case .tool(let toolMessage):
            var encoded: [String: Any] = [
                "role": "tool",
                "tool_call_id": toolMessage.toolCallId
            ]
            encoded["content"] = encodeToolContent(
                toolMessage.content,
                capability: capability
            )
            return encoded

        case .reminder(let reminderMessage):
            let wireRole: String
            switch family.reminderWireRole {
            case .latestReminder:
                wireRole = "latest_reminder"
            case .system:
                wireRole = "system"
            case .user:
                wireRole = "user"
            }
            var encoded: [String: Any] = ["role": wireRole]
            if case .textContent(let text) = reminderMessage.content {
                encoded["content"] = text
            }
            if let name = reminderMessage.name {
                encoded["name"] = name
            }
            return encoded
        }
    }

    private static func encodeUserContent(
        _ content: UserMessageParam.Content,
        capability: MultimediaCapability
    ) -> Any {
        switch content {
        case .string(let string):
            return string
        case .contentParts(let parts):
            var texts: [String] = []
            var encodedParts: [[String: Any]] = []
            var hasUnsupportedImage = false
            var hasUnsupportedVideo = false
            var keptSupportedMedia = false

            for part in parts {
                switch part {
                case .text(let textContent):
                    texts.append(textContent.text)
                    encodedParts.append([
                        "type": "text",
                        "text": textContent.text
                    ])
                case .image(let imageContent):
                    if capability.supportsImage {
                        keptSupportedMedia = true
                        encodedParts.append(
                            encodeImageURLPart(
                                url: imageContent.imageUrl.url,
                                detail: imageContent.imageUrl.detail.rawValue
                            )
                        )
                    } else {
                        hasUnsupportedImage = true
                    }
                case .video(let videoContent):
                    if capability.supportsVideo {
                        keptSupportedMedia = true
                        encodedParts.append(
                            encodeVideoURLPart(
                                url: videoContent.videoUrl.url,
                                fps: videoContent.videoUrl.fps
                            )
                        )
                    } else {
                        hasUnsupportedVideo = true
                    }
                }
            }

            return finalizeMultimediaContent(
                encodedParts: encodedParts,
                texts: texts,
                hasUnsupportedImage: hasUnsupportedImage,
                hasUnsupportedVideo: hasUnsupportedVideo,
                keptSupportedMedia: keptSupportedMedia
            )
        }
    }

    private static func encodeToolContent(
        _ content: ToolMessageParam.Content,
        capability: MultimediaCapability
    ) -> Any {
        switch content {
        case .textContent(let string):
            return string
        case .contentParts(let parts):
            var texts: [String] = []
            var encodedParts: [[String: Any]] = []
            var hasUnsupportedImage = false
            var hasUnsupportedVideo = false
            var keptSupportedMedia = false

            for part in parts {
                switch part {
                case .text(let textContent):
                    texts.append(textContent.text)
                    encodedParts.append([
                        "type": "text",
                        "text": textContent.text
                    ])
                case .image(let imageContent):
                    if capability.supportsImage {
                        keptSupportedMedia = true
                        encodedParts.append(
                            encodeImageURLPart(
                                url: imageContent.imageUrl.url,
                                detail: imageContent.imageUrl.detail.rawValue
                            )
                        )
                    } else {
                        hasUnsupportedImage = true
                    }
                case .video(let videoContent):
                    if capability.supportsVideo {
                        keptSupportedMedia = true
                        encodedParts.append(
                            encodeVideoURLPart(
                                url: videoContent.videoUrl.url,
                                fps: videoContent.videoUrl.fps
                            )
                        )
                    } else {
                        hasUnsupportedVideo = true
                    }
                }
            }

            return finalizeMultimediaContent(
                encodedParts: encodedParts,
                texts: texts,
                hasUnsupportedImage: hasUnsupportedImage,
                hasUnsupportedVideo: hasUnsupportedVideo,
                keptSupportedMedia: keptSupportedMedia
            )
        }
    }

    /// 按厂家能力将 `response_format` 降级：`json_schema` → `json_object` → 去掉。
    static func normalizeResponseFormat(
        _ format: ChatQuery.ResponseFormat?,
        family: ProviderFamily,
        model: String
    ) -> ChatQuery.ResponseFormat? {
        guard let format else { return nil }

        var capability = family.responseFormatCapability
        if family == .moonshot, model.lowercased().contains("thinking") {
            capability = .none
        }

        switch format.type {
        case "json_schema":
            switch capability {
            case .jsonSchema:
                return format
            case .jsonObject:
                return .jsonObject
            case .none:
                return nil
            }
        case "json_object":
            switch capability {
            case .jsonSchema, .jsonObject:
                return format
            case .none:
                return nil
            }
        default:
            return format
        }
    }

    private static func encodeResponseFormat(_ responseFormat: ChatQuery.ResponseFormat) throws -> [String: Any] {
        var encoded: [String: Any] = ["type": responseFormat.type]
        if let jsonSchema = responseFormat.jsonSchema {
            var encodedSchema: [String: Any] = ["name": jsonSchema.name]
            if let description = jsonSchema.description {
                encodedSchema["description"] = description
            }
            if let strict = jsonSchema.strict {
                encodedSchema["strict"] = strict
            }
            if let schemaDict = jsonSchema.schema {
                encodedSchema["schema"] = schemaDict.toAnyDictionary()
            }
            encoded["json_schema"] = encodedSchema
        }
        return encoded
    }

    private static func encodeToolChoice(_ toolChoice: ChatQuery.ChatCompletionFunctionCallOptionParam) throws -> Any {
        switch toolChoice {
        case .none:
            return "none"
        case .auto:
            return "auto"
        case .required:
            return "required"
        case .function(let name):
            return [
                "type": "function",
                "function": [
                    "name": name
                ]
            ]
        }
    }

    private static func applyThinking(
        into body: inout [String: Any],
        thinkLevel: ThinkLevel?,
        family: ProviderFamily
    ) {
        switch family {
        case .minimax:
            body["reasoning_split"] = true
            guard let thinkLevel else { return }
            body["thinking"] = [
                "type": thinkLevel.enablesReasoning ? "adaptive" : "disabled"
            ]

        case .zhipuGLM, .volcengineArk:
            guard let thinkLevel else { return }
            body["thinking"] = [
                "type": thinkLevel.enablesReasoning ? "enabled" : "disabled"
            ]
            if thinkLevel.enablesReasoning {
                body["reasoning_effort"] = thinkLevel.rawValue
            }

        case .deepseek, .genericOpenAICompatible:
            guard let thinkLevel else { return }
            body["thinking"] = [
                "type": thinkLevel.enablesReasoning ? "enabled" : "disabled"
            ]
            if thinkLevel.enablesReasoning {
                body["reasoning_effort"] = thinkLevel.rawValue
            }

        case .dashscope:
            guard let thinkLevel else { return }
            body["enable_thinking"] = thinkLevel.enablesReasoning

        case .openai:
            guard let thinkLevel else { return }
            body["reasoning_effort"] = thinkLevel.rawValue

        case .moonshot:
            break
        }
    }

    private static func normalizedBasePath(from basePath: String?) -> String {
        let trimmed = (basePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? basePath!.trimmingCharacters(in: .whitespacesAndNewlines)
            : "/v1"
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: true)
        var normalized = "/" + components.joined(separator: "/")
        if normalized == "/chat/completions" {
            return normalized
        }
        if normalized.hasSuffix("/chat/completions") {
            return normalized
        }
        if normalized == "/" {
            return "/chat/completions"
        }
        normalized += "/chat/completions"
        return normalized
    }

    private static func makeRequestURL(
        configuration: OpenAIConfiguration,
        normalizedBasePath: String
    ) throws -> URL {
        var components = URLComponents()
        components.scheme = configuration.scheme
        components.host = configuration.host
        components.port = configuration.port
        components.path = normalizedBasePath

        guard let url = components.url else {
            throw OpenAIError.invalidURL
        }
        return url
    }

    private static func mergeExtraBody(
        _ configurationExtraBody: [String: AnyCodableValue]?,
        _ queryExtraBody: [String: AnyCodableValue]?
    ) -> [String: AnyCodableValue] {
        var merged = configurationExtraBody ?? [:]
        if let queryExtraBody {
            for (key, value) in queryExtraBody {
                merged[key] = value
            }
        }
        return merged
    }

    private static func applyProviderDefaults(
        into body: inout [String: Any],
        request: CanonicalChatRequest,
        family: ProviderFamily
    ) {
        guard request.stream == true else { return }

        var streamOptions = body["stream_options"] as? [String: Any] ?? [:]
        if streamOptions["include_usage"] == nil {
            streamOptions["include_usage"] = true
        }
        body["stream_options"] = streamOptions

        switch family {
        case .minimax:
            break
        case .openai, .moonshot, .zhipuGLM, .volcengineArk, .dashscope, .genericOpenAICompatible, .deepseek:
            break
        }
    }

    private static func encodeTools(
        _ tools: [ChatQuery.ChatCompletionToolParam],
        family: ProviderFamily
    ) throws -> [Any] {
        let encoded: [Any] = try tools.map { try jsonValue($0) }
        guard !family.supportsToolStrict else { return encoded }
        // 不支持 strict 的 Provider：剥除 function.strict，即使工具声明了也不发送
        return encoded.map { tool in
            guard var dict = tool as? [String: Any],
                  var function = dict["function"] as? [String: Any] else {
                return tool
            }
            function.removeValue(forKey: "strict")
            dict["function"] = function
            return dict
        }
    }

    private static func jsonValue<T: Encodable>(_ value: T) throws -> Any {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data, options: [])
    }
}

struct ProviderStreamNormalizationState {
    var contentByChoiceIndex: [Int: String] = [:]
    var reasoningByChoiceIndex: [Int: String] = [:]
    var toolCallIDs: [Int: [Int: String]] = [:]
    var toolCallTypes: [Int: [Int: String]] = [:]
    var toolCallNames: [Int: [Int: String]] = [:]
    var toolCallArguments: [Int: [Int: String]] = [:]
}

enum ProviderResponseNormalizer {
    static func requestID(from response: HTTPURLResponse) -> String? {
        let candidates = [
            "x-request-id",
            "request-id",
            "x-req-id",
            "x-b3-traceid"
        ]
        for candidate in candidates {
            if let value = response.value(forHTTPHeaderField: candidate), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    #if !os(Windows)
    static func requestID(from headers: HTTPHeaders) -> String? {
        let candidates = [
            "x-request-id",
            "request-id",
            "x-req-id",
            "x-b3-traceid"
        ]
        for candidate in candidates {
            if let value = headers[candidate].first, !value.isEmpty {
                return value
            }
        }
        return nil
    }
    #endif

    static func normalize(
        streamChunk: ChatStreamResult,
        family: ProviderFamily,
        state: inout ProviderStreamNormalizationState
    ) -> ChatStreamResult {
        guard family == .minimax else {
            return streamChunk
        }

        let normalizedChoices = streamChunk.choices.map { choice in
            let (normalizedContent, updatedContent) = deltaFromCumulative(
                choice.delta.content,
                previous: state.contentByChoiceIndex[choice.index] ?? ""
            )
            state.contentByChoiceIndex[choice.index] = updatedContent

            let (normalizedReasoning, updatedReasoning) = deltaFromCumulative(
                choice.delta.reasoning,
                previous: state.reasoningByChoiceIndex[choice.index] ?? ""
            )
            state.reasoningByChoiceIndex[choice.index] = updatedReasoning

            var normalizedToolCalls: [ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall]?
            if let toolCalls = choice.delta.toolCalls {
                normalizedToolCalls = toolCalls.map { call in
                    let previousID = state.toolCallIDs[choice.index]?[call.index]
                    let previousType = state.toolCallTypes[choice.index]?[call.index]
                    let previousName = state.toolCallNames[choice.index]?[call.index] ?? ""
                    let previousArguments = state.toolCallArguments[choice.index]?[call.index] ?? ""

                    let (normalizedName, updatedName) = deltaFromCumulative(
                        call.function?.name,
                        previous: previousName
                    )
                    let (normalizedArguments, updatedArguments) = deltaFromCumulative(
                        call.function?.arguments,
                        previous: previousArguments
                    )

                    state.toolCallIDs[choice.index, default: [:]][call.index] = call.id ?? previousID
                    state.toolCallTypes[choice.index, default: [:]][call.index] = call.type ?? previousType
                    state.toolCallNames[choice.index, default: [:]][call.index] = updatedName
                    state.toolCallArguments[choice.index, default: [:]][call.index] = updatedArguments

                    let normalizedFunction: ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall.ChoiceDeltaToolCallFunction?
                    if normalizedName != nil || normalizedArguments != nil {
                        normalizedFunction = .init(name: normalizedName, arguments: normalizedArguments)
                    } else {
                        normalizedFunction = nil
                    }

                    return ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall(
                        index: call.index,
                        id: previousID == nil ? call.id : (previousID == call.id ? nil : call.id),
                        type: previousType == nil ? call.type : (previousType == call.type ? nil : call.type),
                        function: normalizedFunction
                    )
                }
            }

            let normalizedDelta = ChatStreamResult.Choice.ChoiceDelta(
                role: choice.delta.role,
                content: normalizedContent,
                reasoning: normalizedReasoning,
                toolCalls: normalizedToolCalls
            )

            return ChatStreamResult.Choice(
                index: choice.index,
                delta: normalizedDelta,
                logprobs: choice.logprobs,
                finishReason: choice.finishReason,
                usage: choice.usage
            )
        }

        return ChatStreamResult(
            id: streamChunk.id,
            object: streamChunk.object,
            created: streamChunk.created,
            model: streamChunk.model,
            systemFingerprint: streamChunk.systemFingerprint,
            choices: normalizedChoices,
            usage: streamChunk.usage
        )
    }

    private static func deltaFromCumulative(_ current: String?, previous: String) -> (String?, String) {
        guard let current, !current.isEmpty else {
            return (nil, previous)
        }

        if current.hasPrefix(previous) {
            let delta = String(current.dropFirst(previous.count))
            return (delta.isEmpty ? nil : delta, current)
        }

        return (current, previous + current)
    }

    static func extractReasoningText(from details: [ReasoningDetailPayload]) -> String? {
        let combined = details.compactMap(\.text).joined()
        return combined.isEmpty ? nil : combined
    }
}
