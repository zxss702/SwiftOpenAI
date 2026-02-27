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
    /// 当前流式响应状态
    public var state: OpenAIChatStreamResultState = .wait
    
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
    
    public func getResult() -> OpenAIChatStreamResult {
        let result = OpenAIChatStreamResult(
            subThinkingText: subThinkingText,
            subText: subText,
            fullThinkingText: fullThinkingText,
            fullText: fullText,
            state: state,
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
            state: state,
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
        fullThinkingText += thinkingText
        fullText += text
        subThinkingText += thinkingText
        subText += text
        
        if !thinkingText.isEmpty {
            state = .think
        } else if !text.isEmpty {
            state = .text
        }
    }
    
    /// 设置当前状态
    ///
    /// - Parameter newState: 新的流式响应状态
    public func setState(_ newState: OpenAIChatStreamResultState) {
        state = newState
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
        state = .wait
        allToolCalls = []
        usage = nil
    }
}
