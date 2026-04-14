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
        }
    }

    var assistantReasoningEncoding: AssistantReasoningEncoding {
        switch self {
        // case .moonshot:
        //     return .omit
        case .minimax:
            return .reasoningDetails
        case .openai, .zhipuGLM, .volcengineArk, .dashscope, .genericOpenAICompatible, .moonshot:
            return .reasoningContent
        }
    }
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
    let think: Bool?
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
            if containsImageInput(in: request.messages) {
                throw OpenAIError.providerUnsupported("MiniMax 兼容接口当前不支持图片或音频输入")
            }
        case .moonshot:
            let isThinkingModel = request.model.lowercased().contains("thinking")
            if isThinkingModel, let tools = request.tools, !tools.isEmpty {
                throw OpenAIError.unsupportedParameterCombination("Moonshot 思考模型暂不支持 tools")
            }
            if isThinkingModel, let responseFormat = request.responseFormat, responseFormat.type == "json_object" {
                throw OpenAIError.unsupportedParameterCombination("Moonshot 思考模型暂不支持 JSON Mode")
            }
        case .openai, .zhipuGLM, .volcengineArk, .dashscope, .genericOpenAICompatible:
            break
        }
    }

    private static func containsImageInput(in messages: [ChatQuery.ChatCompletionMessageParam]) -> Bool {
        for message in messages {
            switch message {
            case .user(let userMessage):
                if case .contentParts(let parts) = userMessage.content {
                    if parts.contains(where: {
                        if case .image = $0 {
                            return true
                        }
                        return false
                    }) {
                        return true
                    }
                }
            case .tool(let toolMessage):
                if case .contentParts(let parts) = toolMessage.content {
                    if parts.contains(where: {
                        if case .image = $0 {
                            return true
                        }
                        return false
                    }) {
                        return true
                    }
                }
            case .system, .assistant:
                continue
            }
        }
        return false
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
            responseFormat: query.responseFormat,
            stop: query.stop,
            temperature: query.temperature,
            toolChoice: query.toolChoice,
            tools: query.tools,
            topP: query.topP,
            user: query.user,
            stream: query.stream,
            think: query.think,
            mergedExtraBody: mergeExtraBody(configuration.extraBody, query.extraBody)
        )

        try ProviderCompatibilityValidator.validate(canonicalRequest, family: family)
        let normalizedBasePath = normalizedBasePath(from: configuration.basePath)
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
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

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
            "messages": try encodeMessages(request.messages, family: family),
            "model": request.model
        ]

        if let frequencyPenalty = request.frequencyPenalty {
            body["frequency_penalty"] = frequencyPenalty
        }
        if let maxCompletionTokens = request.maxCompletionTokens {
            switch family {
            case .openai:
                body["max_completion_tokens"] = maxCompletionTokens
            case .moonshot, .minimax, .zhipuGLM, .volcengineArk, .dashscope, .genericOpenAICompatible:
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
            body["tools"] = try tools.map { try jsonValue($0) }
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
        applyThinking(into: &body, think: request.think, family: family)

        return body
    }

    private static func encodeMessages(
        _ messages: [ChatQuery.ChatCompletionMessageParam],
        family: ProviderFamily
    ) throws -> [[String: Any]] {
        try messages.map { try encodeMessage($0, family: family) }
    }

    private static func encodeMessage(
        _ message: ChatQuery.ChatCompletionMessageParam,
        family: ProviderFamily
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
            encoded["content"] = encodeUserContent(userMessage.content)
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
            encoded["content"] = encodeToolContent(toolMessage.content)
            return encoded
        }
    }

    private static func encodeUserContent(_ content: UserMessageParam.Content) -> Any {
        switch content {
        case .string(let string):
            return string
        case .contentParts(let parts):
            return parts.map { part -> [String: Any] in
                switch part {
                case .text(let textContent):
                    return [
                        "type": "text",
                        "text": textContent.text
                    ]
                case .image(let imageContent):
                    return [
                        "type": "image_url",
                        "image_url": [
                            "url": imageContent.imageUrl.url,
                            "detail": imageContent.imageUrl.detail.rawValue
                        ] as [String: Any]
                    ] as [String: Any]
                }
            }
        }
    }

    private static func encodeToolContent(_ content: ToolMessageParam.Content) -> Any {
        switch content {
        case .textContent(let string):
            return string
        case .contentParts(let parts):
            return parts.map { part -> [String: Any] in
                switch part {
                case .text(let textContent):
                    return [
                        "type": "text",
                        "text": textContent.text
                    ]
                case .image(let imageContent):
                    return [
                        "type": "image_url",
                        "image_url": [
                            "url": imageContent.imageUrl.url,
                            "detail": imageContent.imageUrl.detail.rawValue
                        ] as [String: Any]
                    ] as [String: Any]
                }
            }
        }
    }

    private static func encodeResponseFormat(_ responseFormat: ChatQuery.ResponseFormat) throws -> [String: Any] {
        var encoded: [String: Any] = ["type": responseFormat.type]
        if let jsonSchema = responseFormat.jsonSchema {
            var encodedSchema: [String: Any] = ["name": jsonSchema.name]
            if let description = jsonSchema.description {
                encodedSchema["description"] = description
            }
            if let schemaData = jsonSchema.schema.data(using: .utf8),
               let schemaObject = try? JSONSerialization.jsonObject(with: schemaData, options: []) {
                encodedSchema["schema"] = schemaObject
            } else {
                encodedSchema["schema"] = jsonSchema.schema
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

    private static func applyThinking(into body: inout [String: Any], think: Bool?, family: ProviderFamily) {
        switch family {
        case .minimax:
            body["reasoning_split"] = true
        case .zhipuGLM, .volcengineArk:
            guard let think else { return }
            body["thinking"] = [
                "type": think ? "enabled" : "disabled"
            ]
        case .dashscope:
            guard let think else { return }
            body["enable_thinking"] = think
        case .openai, .moonshot, .genericOpenAICompatible:
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
        switch family {
        case .minimax:
            guard request.stream == true else { return }

            var streamOptions = body["stream_options"] as? [String: Any] ?? [:]
            if streamOptions["include_usage"] == nil {
                streamOptions["include_usage"] = true
            }
            body["stream_options"] = streamOptions
        case .openai, .moonshot, .zhipuGLM, .volcengineArk, .dashscope, .genericOpenAICompatible:
            break
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
