import Foundation

@MainActor
public class OpenAISendMessageValueHelper {
    private var _fullThinkingText: String = ""
    private var _fullText: String = ""
    private var _state: OpenAIChatStreamResultState = .wait
    private var _allToolCalls: [ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall] = []
    
    public init() {}
    
    public var fullThinkingText: String {
        return _fullThinkingText
    }
    
    public var fullText: String {
        return _fullText
    }
    
    public var state: OpenAIChatStreamResultState {
        return _state
    }
    
    public var allToolCalls: [ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall] {
        return _allToolCalls
    }
    
    public func setText(thinkingText: String, text: String) {
        _fullThinkingText += thinkingText
        _fullText += text
    }
    
    public func setState(_ state: OpenAIChatStreamResultState) {
        _state = state
    }
    
    public func appendAllToolCalls(_ toolCall: ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall) {
        _allToolCalls.append(toolCall)
    }
    
    public func setAllToolCalls(index: Int, call: ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall) {
        guard index < _allToolCalls.count else { return }
        _allToolCalls[index] = call
    }
    
    public func reset() {
        _fullThinkingText = ""
        _fullText = ""
        _state = OpenAIChatStreamResultState.wait
        _allToolCalls = []
    }
}
