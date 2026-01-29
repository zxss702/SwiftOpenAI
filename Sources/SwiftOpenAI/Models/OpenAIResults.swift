import Foundation

// MARK: - Stream State

/// OpenAI 聊天流式响应状态
///
/// 表示流式聊天过程中的当前状态。
public enum OpenAIChatStreamResultState: String, Codable, CaseIterable {
    /// 等待状态（没有任何输出）
    case wait
    
    /// 思考状态（正在输出思考过程）
    case think
    
    /// 文本输出状态（正在输出内容）
    case text
    
    /// 状态的可读描述
    public var description: String {
        switch self {
        case .wait:
            return "等待中"
        case .think:
            return "思考中"
        case .text:
            return "输出内容"
        }
    }
}

// MARK: - Stream Result

/// OpenAI 聊天流式结果
///
/// 封装流式聊天的增量和累积结果，
/// 包含思考过程和实际输出内容。
public struct OpenAIChatStreamResult {
    /// 本次增量的思考文本
    public let subThinkingText: String
    
    /// 本次增量的输出文本
    public let subText: String
    
    /// 累积的完整思考文本
    public let fullThinkingText: String
    
    /// 累积的完整输出文本
    public let fullText: String
    
    /// 当前流式响应状态
    public let state: OpenAIChatStreamResultState
    
    /// 所有工具调用列表
    public let allToolCalls: [ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall]
    
    public init(
        subThinkingText: String,
        subText: String,
        fullThinkingText: String,
        fullText: String,
        state: OpenAIChatStreamResultState,
        allToolCalls: [ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall]
    ) {
        self.subThinkingText = subThinkingText
        self.subText = subText
        self.fullThinkingText = fullThinkingText
        self.fullText = fullText
        self.state = state
        self.allToolCalls = allToolCalls
    }
}

// MARK: - Final Result

/// OpenAI 聊天最终结果
///
/// 表示聊天完成后的最终结果，
/// 包含完整的思考过程和输出内容。
public struct OpenAIChatResult {
    /// 完整的思考文本
    public let fullThinkingText: String
    
    /// 完整的输出文本
    public let fullText: String
    
    /// 最终状态
    public let state: OpenAIChatStreamResultState
    
    /// 所有工具调用列表
    public let allToolCalls: [ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall]
    
    public init(
        fullThinkingText: String,
        fullText: String,
        state: OpenAIChatStreamResultState,
        allToolCalls: [ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall]
    ) {
        self.fullThinkingText = fullThinkingText
        self.fullText = fullText
        self.state = state
        self.allToolCalls = allToolCalls
    }
}
