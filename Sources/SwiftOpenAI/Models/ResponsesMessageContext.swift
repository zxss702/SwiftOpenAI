import Foundation

/// Responses 补充上下文。正文、思考文本和工具参数只保存在 assistant 的 C 字段中。
public struct ResponsesMessageContext: Codable, Sendable, Hashable {
    public struct TextPart: Codable, Sendable, Hashable {
        public let metadata: [String: AnyCodableValue]
        /// 在对应 C 文本中的 UTF-8 字节范围，不保存文本副本。
        public let textRange: Range<Int>?
    }

    public struct Item: Codable, Sendable, Hashable {
        public let metadata: [String: AnyCodableValue]
        public let content: [TextPart]?
        public let summary: [TextPart]?
        public let toolCallIndex: Int?
    }

    public let items: [Item]
    /// 绑定生成这些隐藏字段时的 C 内容；编辑后不再使用旧加密上下文。
    public let sourceHash: String

    public init?(outputItems: [[String: AnyCodableValue]]) {
        guard let message = Self.assistantMessage(from: outputItems),
              let context = message.contentBlocks?.responses else { return nil }
        self = context
    }

    private init(items: [Item], sourceHash: String) {
        self.items = items
        self.sourceHash = sourceHash
    }

    /// 同一次映射生成 C 字段及隐藏信息，避免分别解析后内容不一致。
    nonisolated static func assistantMessage(from outputItems: [[String: AnyCodableValue]]) -> AssistantMessageParam? {
        guard !outputItems.isEmpty else { return nil }
        var text = ""
        var reasoning = ""
        var calls: [AssistantMessageParam.ToolCallParam] = []
        var items: [Item] = []
        // Full reasoning text, when present, is the same source preferred by the SSE parser.
        let hasReasoningText = outputItems.contains { item in
            guard item["type"] == .string("reasoning"), case .array(let parts) = item["content"] else { return false }
            return parts.contains { part in
                guard case .object(let fields) = part else { return false }
                return fields["type"] == .string("reasoning_text")
            }
        }

        for output in outputItems {
            var metadata = output
            var content: [TextPart]?
            var summary: [TextPart]?
            var toolCallIndex: Int?
            switch output["type"] {
            case .string("message"):
                if let value = metadata.removeValue(forKey: "content") {
                    guard let parts = Self.extractTextParts(value, text: &text) else { return nil }
                    content = parts
                }
            case .string("reasoning"):
                if hasReasoningText {
                    if let value = metadata.removeValue(forKey: "content") {
                        guard let parts = Self.extractTextParts(value, text: &reasoning) else { return nil }
                        content = parts
                    }
                    // A provider summary is distinct from the full reasoning text in C.
                } else if let value = metadata.removeValue(forKey: "summary") {
                    guard let parts = Self.extractTextParts(value, text: &reasoning) else { return nil }
                    summary = parts
                }
            case .string("function_call"):
                guard case .string(let id) = metadata.removeValue(forKey: "call_id"),
                      case .string(let name) = metadata.removeValue(forKey: "name"),
                      case .string(let arguments) = metadata.removeValue(forKey: "arguments") else { return nil }
                toolCallIndex = calls.count
                calls.append(.init(id: id, function: .init(name: name, arguments: arguments)))
            default:
                break
            }
            items.append(Item(metadata: metadata, content: content, summary: summary, toolCallIndex: toolCallIndex))
        }
        guard let hash = Self.hash(content: text, reasoning: reasoning, calls: calls) else { return nil }
        return AssistantMessageParam(
            content: text,
            toolCalls: calls,
            reasoningContent: reasoning,
            contentBlocks: MessageContentBlocks(responses: ResponsesMessageContext(items: items, sourceHash: hash))
        )
    }

    nonisolated func inputItems(for assistant: AssistantMessageParam) -> [[String: Any]]? {
        guard Self.hash(
            content: assistant.content ?? "",
            reasoning: assistant.reasoningContent ?? "",
            calls: assistant.toolCalls ?? []
        ) == sourceHash else { return nil }

        var output: [[String: Any]] = []
        for item in items {
            var fields = item.metadata.toAnyDictionary()
            if let parts = item.content {
                let source = item.metadata["type"] == .string("message")
                    ? assistant.content : assistant.reasoningContent
                guard let content = Self.restoreTextParts(parts, text: source ?? "") else { return nil }
                fields["content"] = content
            }
            if let parts = item.summary {
                guard let summary = Self.restoreTextParts(parts, text: assistant.reasoningContent ?? "") else { return nil }
                fields["summary"] = summary
            }
            if let index = item.toolCallIndex {
                guard let calls = assistant.toolCalls, calls.indices.contains(index) else { return nil }
                let call = calls[index]
                fields["call_id"] = call.id
                fields["name"] = call.function.name
                fields["arguments"] = call.function.arguments
            }
            output.append(fields)
        }
        return output
    }

    private nonisolated static func extractTextParts(
        _ value: AnyCodableValue,
        text: inout String
    ) -> [TextPart]? {
        guard case .array(let parts) = value else { return nil }
        var result: [TextPart] = []
        for part in parts {
            guard case .object(var metadata) = part else { return nil }
            var range: Range<Int>?
            if case .string(let partText) = metadata["text"] {
                metadata.removeValue(forKey: "text")
                let start = text.utf8.count
                text += partText
                range = start..<text.utf8.count
            }
            result.append(TextPart(metadata: metadata, textRange: range))
        }
        return result
    }

    private nonisolated static func restoreTextParts(_ parts: [TextPart], text: String) -> [[String: Any]]? {
        let bytes = Array(text.utf8)
        var result: [[String: Any]] = []
        for part in parts {
            var fields = part.metadata.toAnyDictionary()
            if let range = part.textRange {
                guard range.lowerBound >= 0, range.upperBound <= bytes.count else { return nil }
                fields["text"] = String(decoding: bytes[range], as: UTF8.self)
            }
            result.append(fields)
        }
        return result
    }

    private nonisolated static func hash(
        content: String,
        reasoning: String,
        calls: [AssistantMessageParam.ToolCallParam]
    ) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(AssistantMessageParam(
            content: content,
            toolCalls: calls,
            reasoningContent: reasoning
        )) else { return nil }
        return ContentBlocksCrypto.sha256Hex(of: data)
    }
}
