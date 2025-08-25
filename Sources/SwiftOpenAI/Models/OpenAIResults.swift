import Foundation

public enum OpenAIChatStreamResultState: String, Codable, CaseIterable {
    case wait    // 等待，没有任何输出
    case think   // 正在输出思考过程
    case text    // 正在输出content
    
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

public struct OpenAIChatStreamResult {
    public let subThinkingText: String
    public let subText: String
    
    public let fullThinkingText: String
    public let fullText: String
    
    public let state: OpenAIChatStreamResultState
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

public struct OpenAIChatResult {
    public let fullThinkingText: String
    public let fullText: String
    
    public let state: OpenAIChatStreamResultState
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
