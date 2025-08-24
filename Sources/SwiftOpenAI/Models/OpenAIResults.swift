import Foundation

public enum OpenAIChatStreamResultState: String, Codable, CaseIterable {
    case streaming
    case completed
    case failed
    case cancelled
    
    public var description: String {
        switch self {
        case .streaming:
            return "流式传输中"
        case .completed:
            return "已完成"
        case .failed:
            return "失败"
        case .cancelled:
            return "已取消"
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
