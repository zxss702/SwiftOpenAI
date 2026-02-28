import Foundation

// MARK: - Stream Result

/// OpenAI 聊天流式结果
///
/// 封装流式聊天的增量和累积结果，
/// 包含思考过程和实际输出内容。
public struct OpenAIChatStreamResult: Sendable {
    /// 本次增量的思考文本
    public let subThinkingText: String
    
    /// 本次增量的输出文本
    public let subText: String
    
    /// 累积的完整思考文本
    public let fullThinkingText: String
    
    /// 累积的完整输出文本
    public let fullText: String
    
    /// 所有工具调用列表
    public let allToolCalls: [ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall]
    
    public init(
        subThinkingText: String,
        subText: String,
        fullThinkingText: String,
        fullText: String,
        allToolCalls: [ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall]
    ) {
        self.subThinkingText = subThinkingText
        self.subText = subText
        self.fullThinkingText = fullThinkingText
        self.fullText = fullText
        self.allToolCalls = allToolCalls
    }
}

// MARK: - Final Result

/// OpenAI 聊天最终结果
///
/// 表示聊天完成后的最终结果，
/// 包含完整的思考过程和输出内容。
public struct OpenAIChatResult: Sendable {
    /// 完整的思考文本
    public let fullThinkingText: String
    
    /// 完整的输出文本
    public let fullText: String
    
    /// 所有工具调用列表
    public let allToolCalls: [ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall]
    
    /// Token 使用统计信息
    public let usage: ChatStreamResult.Choice.UsageInfo?
    
    public init(
        fullThinkingText: String,
        fullText: String,
        allToolCalls: [ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall],
        usage: ChatStreamResult.Choice.UsageInfo? = nil
    ) {
        self.fullThinkingText = fullThinkingText
        self.fullText = fullText
        self.allToolCalls = allToolCalls
        self.usage = usage
    }
}
