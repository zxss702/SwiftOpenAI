import Foundation

/// 出站消息对图像 / 视频的支持能力
struct MultimediaCapability: Sendable, Equatable {
    var supportsImage: Bool
    var supportsVideo: Bool

    static let none = MultimediaCapability(supportsImage: false, supportsVideo: false)
}

enum MultimediaCapabilityResolver {
    /// 按厂商线路 + 模型发现性匹配解析多模态能力。未知模型默认双 false。
    static func resolve(
        family: ProviderFamily,
        wireAPI: AIModelWireAPI,
        model: String
    ) -> MultimediaCapability {
        let id = normalizedModelID(model)

        // MiniMax OpenAI 兼容 Completions：线路不接受 image_url（含聚合上误走 completions）
        if wireAPI == .completions, isMiniMaxModel(id) {
            return .none
        }
        if family == .minimax, wireAPI == .completions {
            return .none
        }

        var capability = discover(id)

        if family == .deepseek || id.contains("deepseek") {
            if isDeepSeekVisionExpModelID(id) {
                capability = MultimediaCapability(supportsImage: true, supportsVideo: false)
            }
        }

        if family == .openai {
            capability.supportsVideo = false
        }

        // Anthropic Messages：仅 MiniMax-M3 有 video block；Claude 等关 video
        if wireAPI == .anthropic, !isMiniMaxM3(id) {
            capability.supportsVideo = false
        }

        return capability
    }

    /// 与 Files offload 对齐的 vision-exp 判定。
    static func isDeepSeekVisionExpModelID(_ model: String) -> Bool {
        let id = model.lowercased()
        return id.contains("vision-exp") || id.contains("vision_exp")
    }

    static func normalizedModelID(_ model: String) -> String {
        var id = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let slash = id.lastIndex(of: "/") {
            id = String(id[id.index(after: slash)...])
        }
        if let at = id.lastIndex(of: "@") {
            id = String(id[..<at])
        }
        if let colon = id.firstIndex(of: ":") {
            id = String(id[..<colon])
        }
        let bedrockMarkers = [
            "anthropic.", "openai.", "meta.", "amazon.", "google.",
            "mistral.", "xai.", "qwen.", "moonshotai.", "nvidia."
        ]
        for marker in bedrockMarkers {
            if let range = id.range(of: marker, options: .backwards) {
                id = String(id[range.upperBound...])
                break
            }
        }
        return id
    }

    private static func isMiniMaxM3(_ id: String) -> Bool {
        let compact = id.replacingOccurrences(of: "_", with: "-")
        return compact == "minimax-m3" || compact.hasPrefix("minimax-m3-")
    }

    private static func isMiniMaxModel(_ id: String) -> Bool {
        let compact = id.replacingOccurrences(of: "_", with: "-")
        return compact.hasPrefix("minimax-m") || compact.hasPrefix("minimax_m")
    }

    private static func discover(_ id: String) -> MultimediaCapability {
        if id.hasPrefix("gpt-image") || id.hasPrefix("chatgpt-image") {
            return .none
        }
        if id.hasPrefix("veo-") || id.hasPrefix("lyria") || id.hasPrefix("imagen") || id.hasPrefix("seedance") {
            return .none
        }
        if id.contains("codex-spark") {
            return .none
        }

        var image = false
        var video = false
        let compact = id.replacingOccurrences(of: ".", with: "-")

        if isMiniMaxM3(id) {
            return MultimediaCapability(supportsImage: true, supportsVideo: true)
        }
        if isDeepSeekVisionExpModelID(id) || id.contains("deepseek-ocr") {
            return MultimediaCapability(supportsImage: true, supportsVideo: false)
        }

        // 通用视觉 token
        if id.contains("vision")
            || id.contains("multimodal")
            || id.contains("pixtral")
            || id.contains("llava")
            || id.contains("moondream")
            || id.contains("idefics")
            || id.contains("internvl")
            || id.contains("cogvlm")
            || id.contains("bakllava")
            || id.contains("paligemma")
            || id.contains("minicpm")
            || containsVLToken(id)
        {
            image = true
        }

        // OpenAI
        if id.hasPrefix("gpt-4o")
            || id.hasPrefix("chatgpt-4o")
            || id.hasPrefix("gpt-4.1")
            || id.hasPrefix("gpt-4.5")
            || id.hasPrefix("gpt-5")
            || id.hasPrefix("gpt-4-turbo")
            || id.hasPrefix("gpt-4-vision")
        {
            image = true
        }
        if id == "o1" || id.hasPrefix("o1-") || id == "o3" || id.hasPrefix("o3-") || id.hasPrefix("o4") {
            if !id.hasPrefix("o3-mini") {
                image = true
            }
        }

        // Anthropic Claude（含 fable）
        if id.hasPrefix("claude-3")
            || id.hasPrefix("claude-4")
            || id.hasPrefix("claude-sonnet")
            || id.hasPrefix("claude-opus")
            || id.hasPrefix("claude-haiku")
            || id.hasPrefix("claude-fable")
        {
            image = true
        }

        // Google Gemini / Gemma
        if id.hasPrefix("gemini"),
           !id.contains("embedding"),
           !id.contains("imagen")
        {
            image = true
            if id.hasPrefix("gemini-1")
                || id.hasPrefix("gemini-2")
                || id.hasPrefix("gemini-3")
                || id.hasPrefix("gemini-flash")
                || id.hasPrefix("gemini-pro")
                || id.contains("omni")
            {
                video = true
            }
        }
        if id.hasPrefix("gemma-3") || id.hasPrefix("gemma-4") || id.hasPrefix("gemma3") || id.hasPrefix("gemma4") {
            image = true
            if id.hasPrefix("gemma-4") || id.hasPrefix("gemma4") {
                video = true
            }
        }

        // xAI Grok 4+（Grok 3 / grok-code 无视觉）
        if id.hasPrefix("grok-4") || id.hasPrefix("grok-imagine") || id.hasPrefix("grok-build") {
            image = true
        }
        if id.contains("grok"), id.contains("vision") || id.contains("image") {
            image = true
        }

        // Meta Llama 4 / Muse Spark
        if id.hasPrefix("llama-4") || id.hasPrefix("llama4") {
            image = true
        }
        if id.hasPrefix("muse-spark") {
            image = true
            video = true
        }

        // Amazon Nova
        if id.hasPrefix("nova-lite") || id.hasPrefix("nova-pro") || id.hasPrefix("nova-2") || id.hasPrefix("nova-micro") {
            image = true
            video = true
        }

        // Mistral 近年视觉（Pixtral 已覆盖；small/medium/large 2025+）
        if id.hasPrefix("mistral-small-")
            || id.hasPrefix("mistral-medium-")
            || id.hasPrefix("mistral-large-")
            || id.hasPrefix("ministral-3")
        {
            image = true
        }

        // Cohere / Perplexity / Vercel v0
        if id.hasPrefix("command-a-plus") || id.contains("aya-vision") {
            image = true
        }
        if id.hasPrefix("sonar") {
            image = true
        }
        if id.hasPrefix("v0-") {
            image = true
        }

        // Qwen：VL/Omni/QVQ + 3.5/3.6/3.8 原生多模态；3.7-max 为纯文本
        if id.contains("qwen") && (containsVLToken(id) || id.contains("vl")) {
            image = true
            video = true
        }
        if hasQwenGeneration(compact, "3-5")
            || hasQwenGeneration(compact, "3-6")
            || hasQwenGeneration(compact, "3-8")
        {
            image = true
            video = true
        }
        if hasQwenGeneration(compact, "3-7"), !compact.contains("max") {
            image = true
            video = true
        }
        if id.hasPrefix("qvq") || id.contains("qvq") {
            image = true
            video = true
        }

        // GLM-4V / 5V / 5.3-flash（glm-5 / 5.1 / 5.2 / 5.3 正文模型为文本）
        if id.contains("glm-4v")
            || id.contains("glm4v")
            || id.contains("glm4.5v")
            || id.contains("glm-4.5v")
            || id.contains("glm-4.6v")
            || id.contains("glm4.6v")
            || id.contains("glm-4.1v")
            || id.contains("glm-5v")
            || compact.contains("glm-5-3-flash")
            || compact.contains("glm-53-flash")
        {
            image = true
            video = true
        }

        // Moonshot Kimi 视觉代（含 k2-6 横杠别名）
        if id.contains("moonshot"), id.contains("vision") {
            image = true
        }
        if compact.hasPrefix("kimi-k2-5")
            || compact.hasPrefix("kimi-k2-6")
            || compact.hasPrefix("kimi-k2-7")
            || compact.hasPrefix("kimi-k3")
            || compact.hasPrefix("kimi-for-coding")
        {
            image = true
            video = true
        }

        // Xiaomi MiMo（v2.5 非 Pro；omni 另含图）
        if (compact.contains("mimo-v2-5") || compact.contains("mimo-v25")),
           !compact.contains("pro")
        {
            image = true
            video = true
        }
        if id.contains("mimo"), id.contains("omni") {
            image = true
        }

        // ByteDance Seed / Doubao
        if id.hasPrefix("doubao-seed") || id.contains("doubao-1.5-vision") {
            image = true
            video = true
        }
        if compact.hasPrefix("seed-1-") || compact.hasPrefix("seed-2-")
            || compact == "seed-1" || compact == "seed-2"
        {
            image = true
            video = true
        }

        // StepFun / Baidu ERNIE / NVIDIA Nemotron VL / OpenCode ox-alpha
        if compact.hasPrefix("step-3") {
            image = true
            video = true
        }
        if id.contains("ernie"), id.contains("vl") || id.contains("vision") {
            image = true
            video = true
        }
        if id.contains("nemotron"), id.contains("vl") || id.contains("omni") || id.contains("vision") {
            image = true
        }
        if compact.hasPrefix("ox-alpha") {
            image = true
            video = true
        }

        // Video 通用
        if id.contains("video") || id.contains("omni") {
            video = true
            image = true
        }

        return MultimediaCapability(supportsImage: image, supportsVideo: video)
    }

    /// `qwen3.5` / `qwen3-5` / `qwen-3-5`
    private static func hasQwenGeneration(_ compact: String, _ generation: String) -> Bool {
        compact.hasPrefix("qwen\(generation)") || compact.hasPrefix("qwen-\(generation)")
    }

    /// `vl` 作为片段：-vl- / vlplus / -vl / _vl_，避免单独字母误伤。
    private static func containsVLToken(_ id: String) -> Bool {
        if id.contains("-vl-") || id.contains("_vl_") || id.contains(".vl.") {
            return true
        }
        if id.contains("vlplus") || id.contains("vl-plus") || id.contains("vl_plus") {
            return true
        }
        if id.hasSuffix("-vl") || id.hasSuffix("_vl") || id.hasSuffix(".vl") {
            return true
        }
        if id.hasPrefix("vl-") || id.hasPrefix("vl_") {
            return true
        }
        // qwen3-vl / qwen-vl
        if id.contains("qwen") && id.contains("vl") {
            return true
        }
        return false
    }
}

/// 不支持多媒体时：保留文本并追加提示，避免整条删除导致 tool_call 不配对
nonisolated func plaintextReplacingUnsupportedMultimedia(
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

/// 按能力过滤图/视频：全不支持则降为纯文本；部分支持则保留可用 parts 并追加提示
nonisolated func finalizeMultimediaContentParts(
    encodedParts: [[String: Any]],
    texts: [String],
    hasUnsupportedImage: Bool,
    hasUnsupportedVideo: Bool,
    keptSupportedMedia: Bool,
    forceArray: Bool = false
) -> Any {
    let hasUnsupported = hasUnsupportedImage || hasUnsupportedVideo
    if !hasUnsupported {
        return encodedParts
    }
    if !keptSupportedMedia {
        let plain = plaintextReplacingUnsupportedMultimedia(
            texts: texts,
            hasImage: hasUnsupportedImage,
            hasVideo: hasUnsupportedVideo
        )
        if forceArray {
            return [["type": "text", "text": plain] as [String: Any]]
        }
        return plain
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
