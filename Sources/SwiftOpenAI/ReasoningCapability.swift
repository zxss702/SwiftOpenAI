import Foundation

/// A model's available controls, independently of the percentage shown by a client.
enum ReasoningCapability: Sendable {
    case unsupported
    case levels([String], off: String?)
    case deepSeek([String])
    case glm([String], off: String?)
    case grok([String])
    case ernie([String])
    case toggle(key: ToggleKey, canDisable: Bool)
    case adaptive([String], canDisable: Bool)
    case budget([Int], canDisable: Bool = true)
    case dashScopeBudget([Int], canDisable: Bool)
    case miniMaxM3
    case miniMaxLegacy

    enum ToggleKey: Sendable { case thinking, enableThinking }

    static let standard = ["minimal", "low", "medium", "high", "xhigh", "max"]
    static let legacyAnthropicBudgets = [1024, 2048, 8192, 16384, 24576, 32000]
    static let three = ["low", "medium", "high"]
    static let throughMax = three + ["xhigh", "max"]
    static let lowHighMax = ["low", "high", "max"]

    /// Positive intervals are left-closed at each internal boundary. 0 is handled
    /// separately by the control; 1 stays in the final interval.
    static func tier<T>(_ ratio: Double, in values: [T]) -> T {
        let index = (1..<values.count).first { ratio < Double($0) / Double(values.count) }
            .map { $0 - 1 } ?? values.count - 1
        return values[index]
    }

    static func normalized(_ ratio: Double?) -> Double? {
        guard let ratio, ratio.isFinite else { return nil }
        return min(1, max(0, ratio))
    }

    static func resolve(model: String, family: ProviderFamily, wireAPI: AIModelWireAPI) -> Self {
        let id = MultimediaCapabilityResolver.normalizedModelID(model)
        var key = id.replacingOccurrences(of: ".", with: "-").replacingOccurrences(of: "_", with: "-")
        if key.hasPrefix("qwen-3") || key.hasPrefix("qwen-4") {
            key.remove(at: key.index(key.startIndex, offsetBy: 4))
        }
        func matches(_ prefix: String) -> Bool { key == prefix || key.hasPrefix(prefix + "-") }
        func matchesAny(_ prefixes: [String]) -> Bool { prefixes.contains(where: matches) }
        let anthropic = wireAPI == .anthropic
        let completions = wireAPI == .completions
        let switchOnly: Self = .toggle(key: .thinking, canDisable: true)
        let unknown: Self = anthropic ? .adaptive(standard, canDisable: true) : .levels(standard, off: "none")

        if matches("deepseek-v4") || matchesAny(["deepseek-pro", "deepseek-flash"]) {
            if family == .dashscope, completions {
                return .dashScopeBudget(legacyAnthropicBudgets, canDisable: true)
            }
            return .deepSeek(lowHighMax)
        }
        if matchesAny(["deepseek-v3-1", "deepseek-v3-2"]) { return switchOnly }
        if matchesAny(["deepseek-reasoner", "deepseek-r1", "deepseek-v3", "deepseek-v2", "deepseek-coder"]) {
            return .unsupported
        }
        if matches("deepseek-chat") { return family == .deepseek ? switchOnly : .unsupported }

        if key.hasPrefix("claude-") {
            guard anthropic else { return unknown }
            if matchesAny(["claude-fable-5", "claude-mythos-5", "claude-opus-5-5", "claude-sonnet-5-5"]) {
                return .adaptive(throughMax, canDisable: false)
            }
            if matches("claude-mythos-preview") { return .adaptive(three + ["max"], canDisable: false) }
            if matchesAny(["claude-opus-4-7", "claude-opus-4-8", "claude-opus-5", "claude-sonnet-5", "claude-haiku-5-5"]) {
                return .adaptive(throughMax, canDisable: true)
            }
            if matchesAny(["claude-opus-4-6", "claude-sonnet-4-6"]) {
                return .adaptive(three + ["max"], canDisable: true)
            }
            if matchesAny(["claude-3-7-sonnet", "claude-3-7", "claude-opus-4", "claude-sonnet-4", "claude-haiku-4-5"]) {
                return .budget(legacyAnthropicBudgets)
            }
            if matchesAny(["claude-1", "claude-2", "claude-3", "claude-instant"]) { return .unsupported }
        }

        if key.hasPrefix("gpt-") || key.hasPrefix("chatgpt-") || matchesAny(["o1", "o3", "o4-mini"]) {
            guard !anthropic else { return unknown }
            if matchesAny(["gpt-3-5", "gpt-4", "chatgpt-4o", "gpt-4o", "gpt-5-chat", "gpt-5-1-chat", "gpt-5-2-chat", "gpt-5-3-chat", "gpt-image", "gpt-realtime", "gpt-audio"]) {
                return .unsupported
            }
            if matchesAny(["o1-mini", "o1-preview"]) { return .unsupported }
            if matchesAny(["o1", "o3", "o4-mini"]) {
                return .levels(matches("o3-pro") ? ["high"] : three, off: nil)
            }
            if matchesAny(["gpt-6-2-astra", "gpt-6-2-sol", "gpt-6-1-sol", "gpt-6-astra"]) {
                return .levels(throughMax, off: nil)
            }
            if matchesAny(["gpt-5-6", "gpt-6-1-terra", "gpt-6-sol", "gpt-6-luna"]) {
                return .levels(throughMax, off: "none")
            }
            if matches("gpt-5-2-pro") || matches("gpt-5-4-pro") {
                return .levels(["medium", "high", "xhigh"], off: nil)
            }
            if matches("gpt-5-pro") { return .levels(["high"], off: nil) }
            if matches("gpt-5-1-codex-max") { return .levels(three + ["xhigh"], off: nil) }
            if matches("gpt-5-1-codex-mini") { return .levels(["medium", "high"], off: nil) }
            if matchesAny(["gpt-5-2-codex", "gpt-5-3-codex"]) { return .levels(three + ["xhigh"], off: nil) }
            if matchesAny(["gpt-5-codex", "gpt-5-1-codex"]) { return .levels(three, off: nil) }
            if matchesAny(["gpt-5-2", "gpt-5-4", "gpt-5-5"]) { return .levels(three + ["xhigh"], off: "none") }
            if matches("gpt-5-1") { return .levels(three, off: "none") }
            if ["gpt-5", "gpt-5-mini", "gpt-5-nano"].contains(key)
                || key.hasPrefix("gpt-5-2025-") || key.hasPrefix("gpt-5-mini-2025-") || key.hasPrefix("gpt-5-nano-2025-") {
                return .levels(["minimal"] + three, off: nil)
            }
        }

        if matchesAny(["qwen3-coder", "qwen2", "qwen2-5", "qwen-turbo", "qwen-max", "qwen-long", "qwen-vl-ocr"]) { return .unsupported }
        if key.contains("-ocr") || key.contains("-tts") || key.contains("-asr") || key.contains("embedding") || key.contains("rerank")
            || matchesAny(["unifuncs", "sora", "seedance", "seedream", "kling", "qwen-image"]) { return .unsupported }
        if matches("qwen3-8-omni-flash") { return .levels(["low", "medium", "xhigh"], off: "none") }
        if matchesAny(["qwen3-8-2-4t-a95b", "qwen3-7-max-preview", "qwen3-7-max-2026-05-17", "qwen3-max-thinking", "qvq", "qwq"])
            || key.hasPrefix("qwen3-") && key.contains("-thinking") {
            return anthropic ? .budget(legacyAnthropicBudgets, canDisable: false) : .dashScopeBudget(legacyAnthropicBudgets, canDisable: false)
        }
        if matchesAny(["qwen-plus", "qwen-flash", "qwen3", "qwen3-5", "qwen3-6", "qwen3-7", "qwen3-8", "qwen4"]) {
            return anthropic ? .budget(legacyAnthropicBudgets) : .dashScopeBudget(legacyAnthropicBudgets, canDisable: true)
        }

        if matchesAny(["glm-5-3", "glm-5-4", "zai-glm-5-3"]) { return .glm(lowHighMax, off: nil) }
        if matches("glm-5-2") { return .glm(["high", "max"], off: "none") }
        if matchesAny(["glm-4-5v", "glm-4-7"]) { return .unsupported }
        if matchesAny(["glm-4-5", "glm-4-6", "glm-5", "glm-4-6v", "glm-4-1v", "glm-5v"]) {
            return switchOnly
        }
        if matchesAny(["glm-3", "glm-4", "glm-4v"]) { return .unsupported }

        if matchesAny(["ark-code-latest", "doubao-seed-1-6", "doubao-seed-1-8", "doubao-seed-2", "seed-2", "seed-evolving"]) {
            // Ark's accepted aliases collapse into this set of real states.
            return .levels(three, off: "minimal")
        }
        if matchesAny(["doubao-1-5-thinking", "doubao-seed-thinking"]) { return .unsupported }

        if matches("kimi-k3") {
            if family == .dashscope, completions, !model.lowercased().hasPrefix("kimi/") {
                return .toggle(key: .enableThinking, canDisable: true)
            }
            return .levels(lowHighMax, off: nil)
        }
        if matches("kimi-k2-7-code") { return .unsupported }
        if matchesAny(["kimi-k2-5", "kimi-k2-6", "kimi-k2-7", "kimi-for-coding"]) {
            if family == .dashscope, completions { return .dashScopeBudget(legacyAnthropicBudgets, canDisable: true) }
            return switchOnly
        }
        if matchesAny(["kimi-k2", "moonshot-v1"]) { return .unsupported }
        if matches("minimax-m3-1-flash") { return .levels(throughMax, off: nil) }
        if matches("minimax-m3") { return .miniMaxM3 }
        if matches("minimax-m2") { return completions && family == .minimax ? .miniMaxLegacy : .unsupported }
        if matchesAny(["mimo-v2-5", "mimo-v2-6"]) { return switchOnly }
        if matchesAny(["ling-3-0-flash", "ling-3-1-flash"]), completions {
            return .toggle(key: .enableThinking, canDisable: true)
        }
        if matches("step-3-5-flash-2603") { return .levels(["low", "high"], off: nil) }
        if matchesAny(["step-3-7", "step-5"]) { return .levels(three, off: nil) }
        if matches("ernie-5-5-flash-preview"), completions { return .ernie(three) }
        if matches("ernie-light-dt-1-0"), completions { return .ernie(lowHighMax) }
        if completions {
            if matchesAny(["gemini-4-neon", "gemini-4-hydrogen"]) { return .levels(three + ["xhigh"], off: nil) }
            if matches("gemini-4") { return .levels(three, off: nil) }
            if matchesAny(["gemini-3-flash", "gemini-3-1-flash-lite"]) { return .levels(["minimal"] + three, off: nil) }
            if matchesAny(["gemini-3-pro", "gemini-3-1-pro"]) { return .levels(["low", "high"], off: nil) }
            if matches("gemini-2-5-pro") { return .levels(three, off: nil) }
            if matches("gemini-2-5-flash") { return .levels(three, off: "none") }
        }
        if matchesAny(["mistral-small-2603", "mistral-medium-3-5"]) { return .levels(["high"], off: "none") }
        if matches("mistral-large-4") { return .levels(three, off: nil) }
        if matches("magistral") { return .unsupported }
        if matchesAny(["grok-4-6", "grok-4-7", "grok-4-20-multi-agent"]) { return .grok(three + ["xhigh"]) }
        if matches("grok-4-5") { return .grok(three) }
        if matches("grok-3-mini") { return .grok(["low", "high"]) }
        if matchesAny(["grok-4", "grok-3", "grok-2", "grok-code-fast", "grok-imagine"]) { return .unsupported }

        return unknown
    }

    /// Returns whether explicitly enabled thinking is active (used for Messages tool-choice rules).
    @discardableResult
    func apply(to body: inout [String: Any], ratio: Double?, wireAPI: AIModelWireAPI) -> Bool {
        let anthropic = wireAPI == .anthropic
        let completions = wireAPI == .completions
        if case .miniMaxLegacy = self, completions { body["reasoning_split"] = true }
        guard let ratio = Self.normalized(ratio) else {
            let type = (body["thinking"] as? [String: Any])?["type"] as? String
            return type == "enabled" || type == "adaptive" || type == "between_tools"
        }
        // An explicit control supersedes older per-model extraBody settings. Keep
        // independent features such as output_config.format and reasoning.context.
        let previousThinking = body.removeValue(forKey: "thinking") as? [String: Any]
        for key in ["enable_thinking", "thinking_budget", "reasoning_effort"] {
            body.removeValue(forKey: key)
        }
        for key in ["output_config", "reasoning"] {
            if var config = body[key] as? [String: Any] {
                config.removeValue(forKey: "effort")
                body[key] = config.isEmpty ? nil : config
            }
        }

        func thinking(_ type: String, preserveHistory: Bool = false) {
            var config: [String: Any] = ["type": type]
            if preserveHistory, type == "enabled", let clear = previousThinking?["clear_thinking"] as? Bool {
                config["clear_thinking"] = clear
            }
            body["thinking"] = config
        }
        func effort(_ value: String, defaultSummary: Bool = true) {
            if anthropic {
                var output = body["output_config"] as? [String: Any] ?? [:]
                output["effort"] = value
                body["output_config"] = output
            } else if completions {
                body["reasoning_effort"] = value
            } else {
                var reasoning = body["reasoning"] as? [String: Any] ?? [:]
                reasoning["effort"] = value
                if defaultSummary && reasoning["summary"] == nil { reasoning["summary"] = "auto" }
                body["reasoning"] = reasoning
            }
        }

        switch self {
        case .unsupported:
            return false
        case .levels(let tiers, let off):
            if ratio == 0, let off { effort(off); return false }
            effort(Self.tier(ratio, in: tiers))
        case .ernie(let tiers):
            if ratio == 0 { thinking("disabled"); return false }
            thinking("enabled")
            effort(Self.tier(ratio, in: tiers))
        case .grok(let tiers):
            for key in ["presence_penalty", "frequency_penalty", "stop"] { body.removeValue(forKey: key) }
            effort(Self.tier(ratio, in: tiers), defaultSummary: false)
        case .glm(let tiers, let off):
            if ratio == 0, let off { effort(off); return false }
            if completions, let clear = previousThinking?["clear_thinking"] as? Bool {
                body["thinking"] = ["clear_thinking": clear]
            }
            effort(Self.tier(ratio, in: tiers))
        case .deepSeek(let tiers):
            let value = ratio == 0 ? "none" : Self.tier(ratio, in: tiers)
            if completions {
                thinking(ratio == 0 ? "disabled" : "enabled")
                if ratio > 0 { effort(value) }
            } else if anthropic {
                effort(value)
            } else {
                var reasoning = body["reasoning"] as? [String: Any] ?? [:]
                reasoning["effort"] = value
                body["reasoning"] = reasoning
            }
            return ratio > 0
        case .toggle(let key, let canDisable):
            let enabled = ratio > 0 || !canDisable
            if key == .enableThinking { body["enable_thinking"] = enabled }
            else { thinking(enabled ? "enabled" : "disabled", preserveHistory: true) }
            return enabled
        case .adaptive(let tiers, let canDisable):
            if ratio == 0 && canDisable { thinking("disabled"); return false }
            thinking("adaptive")
            effort(Self.tier(ratio, in: tiers))
        case .budget(let budgets, let canDisable):
            if ratio == 0 && canDisable { thinking("disabled"); return false }
            let budget = Self.tier(ratio, in: budgets)
            body["thinking"] = ["type": "enabled", "budget_tokens": budget]
            body["max_tokens"] = max(body["max_tokens"] as? Int ?? 4096, budget + 4096)
        case .dashScopeBudget(let budgets, let canDisable):
            if canDisable { body["enable_thinking"] = ratio > 0 }
            guard ratio > 0 || !canDisable else { return false }
            body["thinking_budget"] = Self.tier(ratio, in: budgets)
        case .miniMaxM3:
            thinking(ratio == 0 ? "disabled" : "adaptive")
            if ratio > 0 { effort(Self.tier(ratio, in: Self.throughMax)) }
            return ratio > 0
        case .miniMaxLegacy:
            return false
        }
        return true
    }
}
