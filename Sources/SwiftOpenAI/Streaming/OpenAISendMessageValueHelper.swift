import Foundation

/// OpenAI 消息发送值辅助器
///
/// 用于在流式处理过程中安全地管理和更新状态。
/// 作为 actor 确保并发访问的线程安全。
///
/// ## Topics
///
/// ### 状态属性
/// - ``state``
/// - ``fullThinkingText``
/// - ``fullText``
/// - ``allToolCalls``
///
/// ### 状态更新
/// - ``setText(thinkingText:text:)``
/// - ``setState(_:)``
/// - ``setAllToolCalls(index:call:)``
/// - ``appendAllToolCalls(_:)``
/// - ``reset()``
///
public actor OpenAISendMessageValueHelper {
    private enum ThinkTag {
        static let opening = "<think>"
        static let closing = "</think>"
    }

    /// 累积的完整思考文本
    public var fullThinkingText: String = ""
    
    /// 累积的完整输出文本
    public var fullText: String = ""
    
    /// 所有工具调用列表
    public var allToolCalls: [ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall] = []
    
    /// Token 使用统计信息
    public var usage: ChatStreamResult.Choice.UsageInfo?
    
    public init() {}
    
    public var subText: String = ""
    public var subThinkingText: String = ""
    private var toolCallsDirty: Bool = false
    private var pendingTaggedText: String = ""
    private var isInsideThinkTag = false
    
    public func getResult() -> OpenAIChatStreamResult {
        
        let result = OpenAIChatStreamResult(
            subThinkingText: subThinkingText,
            subText: subText,
            fullThinkingText: fullThinkingText,
            fullText: fullText,
            allToolCalls: allToolCalls
        )
        
        subText = ""
        subThinkingText = ""
        toolCallsDirty = false
        
        return result
    }
    
    public func peekResult() -> OpenAIChatStreamResult {
        OpenAIChatStreamResult(
            subThinkingText: subThinkingText,
            subText: subText,
            fullThinkingText: fullThinkingText,
            fullText: fullText,
            allToolCalls: allToolCalls
        )
    }
    
    public func hasPendingDelta() -> Bool {
        !subThinkingText.isEmpty || !subText.isEmpty || toolCallsDirty
    }
    
    public func clearPendingDelta() {
        subThinkingText = ""
        subText = ""
        toolCallsDirty = false
    }
    
    /// 设置文本内容并更新状态
    ///
    /// - Parameters:
    ///   - thinkingText: 思考文本增量
    ///   - text: 输出文本增量
    public func setText(thinkingText: String, text: String) {
        appendThinkingText(thinkingText)
        parseTaggedText(text)
    }

    public func finalizePendingTaggedText() {
        guard !pendingTaggedText.isEmpty else { return }

        if isInsideThinkTag {
            if !ThinkTag.closing.hasPrefix(pendingTaggedText) {
                appendThinkingText(pendingTaggedText)
            }
        } else {
            appendVisibleText(pendingTaggedText)
        }

        pendingTaggedText = ""
    }
    
    /// 更新指定索引的工具调用
    ///
    /// - Parameters:
    ///   - index: 工具调用在列表中的索引
    ///   - call: 新的工具调用数据
    public func setAllToolCalls(index: Int, call: ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall) {
        guard index < allToolCalls.count else { return }
        allToolCalls[index] = call
        toolCallsDirty = true
    }
    
    /// 添加新的工具调用
    ///
    /// - Parameter call: 要添加的工具调用
    public func appendAllToolCalls(_ call: ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall) {
        allToolCalls.append(call)
        toolCallsDirty = true
    }
    
    /// 设置 Token 使用统计信息
    ///
    /// - Parameter newUsage: 新的使用统计信息
    public func setUsage(_ newUsage: ChatStreamResult.Choice.UsageInfo?) {
        usage = newUsage
    }
    
    /// 重置所有状态
    public func reset() {
        fullThinkingText = ""
        fullText = ""
        subThinkingText = ""
        subText = ""
        toolCallsDirty = false
        pendingTaggedText = ""
        isInsideThinkTag = false
        allToolCalls = []
        usage = nil
    }

    private func appendThinkingText(_ text: String) {
        guard !text.isEmpty else { return }
        fullThinkingText += text
        subThinkingText += text
    }

    private func appendVisibleText(_ text: String) {
        guard !text.isEmpty else { return }
        fullText += text
        subText += text
    }

    private func parseTaggedText(_ text: String) {
        guard !text.isEmpty else { return }

        pendingTaggedText += text

        while !pendingTaggedText.isEmpty {
            if isInsideThinkTag {
                if let range = pendingTaggedText.range(of: ThinkTag.closing) {
                    appendThinkingText(String(pendingTaggedText[..<range.lowerBound]))
                    pendingTaggedText.removeSubrange(..<range.upperBound)
                    isInsideThinkTag = false
                    continue
                }

                let safeCount = safeEmissionCount(
                    in: pendingTaggedText,
                    token: ThinkTag.closing
                )
                guard safeCount > 0 else { break }

                let splitIndex = pendingTaggedText.index(
                    pendingTaggedText.startIndex,
                    offsetBy: safeCount
                )
                appendThinkingText(String(pendingTaggedText[..<splitIndex]))
                pendingTaggedText.removeSubrange(..<splitIndex)
            } else {
                if let range = pendingTaggedText.range(of: ThinkTag.opening) {
                    appendVisibleText(String(pendingTaggedText[..<range.lowerBound]))
                    pendingTaggedText.removeSubrange(..<range.upperBound)
                    isInsideThinkTag = true
                    continue
                }

                let safeCount = safeEmissionCount(
                    in: pendingTaggedText,
                    token: ThinkTag.opening
                )
                guard safeCount > 0 else { break }

                let splitIndex = pendingTaggedText.index(
                    pendingTaggedText.startIndex,
                    offsetBy: safeCount
                )
                appendVisibleText(String(pendingTaggedText[..<splitIndex]))
                pendingTaggedText.removeSubrange(..<splitIndex)
            }
        }
    }

    private func safeEmissionCount(in text: String, token: String) -> Int {
        let maxOverlap = min(text.count, token.count - 1)

        for overlap in stride(from: maxOverlap, through: 1, by: -1) {
            let suffix = String(text.suffix(overlap))
            if token.hasPrefix(suffix) {
                return text.count - overlap
            }
        }

        return text.count
    }
}
