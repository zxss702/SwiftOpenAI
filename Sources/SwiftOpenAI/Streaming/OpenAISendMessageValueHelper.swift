import Foundation

public actor OpenAISendMessageValueHelper {
    public var state: OpenAIChatStreamResultState = .wait
    public var fullThinkingText: String = ""
    public var fullText: String = ""
    public var allToolCalls: [ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall] = []
    
    public init() {}
    
    public func setText(thinkingText: String, text: String) {
        fullThinkingText += thinkingText
        fullText += text
        
        if !thinkingText.isEmpty {
            state = .think
        } else if !text.isEmpty {
            state = .text
        }
    }
    
    public func setState(_ newState: OpenAIChatStreamResultState) {
        state = newState
    }
    
    public func setAllToolCalls(index: Int, call: ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall) {
        guard index < allToolCalls.count else { return }
        allToolCalls[index] = call
    }
    
    public func appendAllToolCalls(_ call: ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall) {
        allToolCalls.append(call)
    }
    
    public func reset() {
        fullThinkingText = ""
        fullText = ""
        state = .wait
        allToolCalls = []
    }
}