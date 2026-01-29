import Foundation

// MARK: - Message Construction Extensions

extension ChatQuery.ChatCompletionMessageParam {
    
    // MARK: - User Messages
    
    /// 创建简单文本用户消息
    public static nonisolated func user(
        _ text: String,
        name: String? = nil
    ) -> Self {
        return .user(
            UserMessageParam(
                content: .string(text),
                name: name
            )
        )
    }
    
    /// 创建带图片的用户消息
    public static nonisolated func user(
        _ text: String,
        imageDatas: Data...,
        detail: UserMessageParam.Content.ContentPart.ImageContent.ImageURL.Detail = .auto,
        name: String? = nil
    ) -> Self {
        return .user(
            UserMessageParam(
                content: .contentParts(
                    imageDatas.map { imageData in
                        UserMessageParam.Content.ContentPart.image(
                            UserMessageParam.Content.ContentPart.ImageContent(
                                imageUrl: UserMessageParam.Content.ContentPart.ImageContent.ImageURL(
                                    imageData: imageData,
                                    detail: detail
                                )
                            )
                        )
                    } + [
                        UserMessageParam.Content.ContentPart.text(
                            UserMessageParam.Content.ContentPart.TextContent(text: text)
                        )
                    ]
                ),
                name: name
            )
        )
    }
    
    /// 创建只有图片的用户消息
    public static nonisolated func user(
        imageDatas: Data...,
        detail: UserMessageParam.Content.ContentPart.ImageContent.ImageURL.Detail = .auto,
        name: String? = nil
    ) -> Self {
        return .user(
            UserMessageParam(
                content: .contentParts(
                    imageDatas.map { imageData in
                        UserMessageParam.Content.ContentPart.image(
                            UserMessageParam.Content.ContentPart.ImageContent(
                                imageUrl: UserMessageParam.Content.ContentPart.ImageContent.ImageURL(
                                    imageData: imageData,
                                    detail: detail
                                )
                            )
                        )
                    }
                ),
                name: name
            )
        )
    }
    
    // MARK: - Tool Messages
    
    /// 创建简单文本工具响应消息
    public static nonisolated func tool(
        _ text: String,
        toolCallId: String
    ) -> Self {
        return .tool(
            ToolMessageParam(
                content: .textContent(text),
                toolCallId: toolCallId
            )
        )
    }
    
    /// 创建带图片的工具响应消息
    public static nonisolated func tool(
        _ text: String,
        images imageDatas: [Data],
        detail: ToolMessageParam.Content.ContentPart.ImageContent.ImageURL.Detail = .auto,
        toolCallId: String
    ) -> Self {
        return .tool(
            ToolMessageParam(
                content: .contentParts(
                    imageDatas.map { imageData in
                        ToolMessageParam.Content.ContentPart.image(
                            ToolMessageParam.Content.ContentPart.ImageContent(
                                imageUrl: ToolMessageParam.Content.ContentPart.ImageContent.ImageURL(
                                    imageData: imageData,
                                    detail: detail
                                )
                            )
                        )
                    } + [
                        ToolMessageParam.Content.ContentPart.text(
                            ToolMessageParam.Content.ContentPart.TextContent(text: text)
                        )
                    ]
                ),
                toolCallId: toolCallId
            )
        )
    }
    
    /// 创建只有图片的工具响应消息
    public static nonisolated func tool(
        images imageDatas: [Data],
        detail: ToolMessageParam.Content.ContentPart.ImageContent.ImageURL.Detail = .auto,
        toolCallId: String
    ) -> Self {
        return .tool(
            ToolMessageParam(
                content: .contentParts(
                    imageDatas.map { imageData in
                        ToolMessageParam.Content.ContentPart.image(
                            ToolMessageParam.Content.ContentPart.ImageContent(
                                imageUrl: ToolMessageParam.Content.ContentPart.ImageContent.ImageURL(
                                    imageData: imageData,
                                    detail: detail
                                )
                            )
                        )
                    }
                ),
                toolCallId: toolCallId
            )
        )
    }
    
    // MARK: - System Messages
    
    /// 创建系统消息
    public static nonisolated func system(
        _ text: String,
        name: String? = nil
    ) -> Self {
        return .system(
            SystemMessageParam(
                content: .textContent(text),
                name: name
            )
        )
    }
    
    // MARK: - Assistant Messages
    
    /// 创建助手消息
    ///
    /// - Parameters:
    ///   - text: 消息的文本内容
    ///   - toolCalls: 助手请求的工具调用列表
    ///   - name: 消息的可选名称标识符
    ///   - reasoningContent: 推理模型的思考过程内容（用于 o1/o3 等模型）
    /// - Returns: 配置好的助手消息
    public static nonisolated func assistant(
        _ text: String,
        toolCalls: [AssistantMessageParam.ToolCallParam]? = nil,
        name: String? = nil,
        reasoningContent: String? = nil
    ) -> Self {
        return .assistant(
            AssistantMessageParam(
                content: text,
                name: name,
                toolCalls: (toolCalls?.isEmpty ?? true) ? nil : toolCalls,
                reasoningContent: reasoningContent
            )
        )
    }
}

// MARK: - 更多便捷方法
extension ChatQuery.ChatCompletionMessageParam {
    
    /// 从字符串快速创建用户消息
    public static nonisolated func userMessage(_ text: String) -> Self {
        return .user(text)
    }
    
    /// 从字符串快速创建系统消息
    public static nonisolated func systemMessage(_ text: String) -> Self {
        return .system(text)
    }
    
    /// 从字符串快速创建助手消息
    public static nonisolated func assistantMessage(_ text: String) -> Self {
        return .assistant(text)
    }
    
    /// 创建仅包含工具调用的助手消息
    ///
    /// 当助手响应只需要调用工具而不返回文本内容时使用此方法。
    ///
    /// - Parameters:
    ///   - toolCalls: 助手请求的工具调用列表
    ///   - reasoningContent: 推理模型的思考过程内容（用于 o1/o3 等模型）
    /// - Returns: 配置好的助手消息
    public static nonisolated func assistantWithToolCalls(
        _ toolCalls: [AssistantMessageParam.ToolCallParam],
        reasoningContent: String? = nil
    ) -> Self {
        return .assistant(
            AssistantMessageParam(
                content: nil,
                name: nil,
                toolCalls: toolCalls,
                reasoningContent: reasoningContent
            )
        )
    }
    
    /// 创建带推理内容的助手消息
    ///
    /// 专门用于 o1、o3 等推理模型，当需要在历史消息中保留推理过程时使用。
    ///
    /// - Parameters:
    ///   - text: 消息的文本内容
    ///   - reasoningContent: 推理模型的思考过程内容
    ///   - toolCalls: 助手请求的工具调用列表
    ///   - name: 消息的可选名称标识符
    /// - Returns: 配置好的助手消息
    public static nonisolated func assistantWithReasoning(
        _ text: String,
        reasoningContent: String,
        toolCalls: [AssistantMessageParam.ToolCallParam]? = nil,
        name: String? = nil
    ) -> Self {
        return .assistant(
            AssistantMessageParam(
                content: text,
                name: name,
                toolCalls: (toolCalls?.isEmpty ?? true) ? nil : toolCalls,
                reasoningContent: reasoningContent
            )
        )
    }
}

// MARK: - Message Properties

extension ChatQuery.ChatCompletionMessageParam {
    
    /// 获取消息的文本内容
    ///
    /// 从消息中提取可读文本内容，支持所有消息类型。
    /// 对于多部分内容，会连接所有文本部分。
    public var textContent: String? {
        switch self {
        case .system(let systemParam):
            if case .textContent(let text) = systemParam.content {
                return text
            }
            return nil
        case .user(let userParam):
            if case .string(let text) = userParam.content {
                return text
            } else if case .contentParts(let parts) = userParam.content {
                // 提取所有文本部分
                return parts.compactMap { part in
                    if case .text(let textContent) = part {
                        return textContent.text
                    }
                    return nil
                }.joined(separator: " ")
            }
            return nil
        case .assistant(let assistantParam):
            return assistantParam.content
        case .tool(let toolParam):
            if case .textContent(let text) = toolParam.content {
                return text
            } else if case .contentParts(let parts) = toolParam.content {
                // 提取所有文本部分
                return parts.compactMap { part in
                    if case .text(let textContent) = part {
                        return textContent.text
                    }
                    return nil
                }.joined(separator: " ")
            }
            return nil
        }
    }
    
    /// 获取消息的名称
    ///
    /// 返回消息关联的名称字段（如果存在）。
    public var name: String? {
        switch self {
        case .system(let systemParam):
            return systemParam.name
        case .user(let userParam):
            return userParam.name
        case .assistant(let assistantParam):
            return assistantParam.name
        case .tool:
            return nil
        }
    }
    
    /// 助手消息中的工具调用列表
    ///
    /// 仅当消息类型为 `assistant` 且包含工具调用时返回非空值。
    /// 对于其他消息类型，始终返回 `nil`。
    public var toolCalls: [AssistantMessageParam.ToolCallParam]? {
        if case .assistant(let assistantParam) = self {
            return assistantParam.toolCalls
        }
        return nil
    }
    
    /// 助手消息中的推理内容
    ///
    /// 仅当消息类型为 `assistant` 且包含推理内容时返回非空值。
    /// 此字段用于 o1、o3 等推理模型的 thinking 功能。
    /// 对于其他消息类型，始终返回 `nil`。
    public var reasoningContent: String? {
        if case .assistant(let assistantParam) = self {
            return assistantParam.reasoningContent
        }
        return nil
    }
}

// MARK: - Array Convenience

/// 消息数组便捷扩展
extension Array where Element == ChatQuery.ChatCompletionMessageParam {
    
    /// 添加用户消息
    public mutating func addUserMessage(_ text: String, name: String? = nil) {
        self.append(.user(text, name: name))
    }
    
    /// 添加系统消息
    public mutating func addSystemMessage(_ text: String, name: String? = nil) {
        self.append(.system(text, name: name))
    }
    
    /// 添加助手消息到数组
    ///
    /// - Parameters:
    ///   - text: 消息的文本内容
    ///   - toolCalls: 助手请求的工具调用列表
    ///   - name: 消息的可选名称标识符
    ///   - reasoningContent: 推理模型的思考过程内容（用于 o1/o3 等模型）
    public mutating func addAssistantMessage(
        _ text: String,
        toolCalls: [AssistantMessageParam.ToolCallParam]? = nil,
        name: String? = nil,
        reasoningContent: String? = nil
    ) {
        self.append(.assistant(text, toolCalls: toolCalls, name: name, reasoningContent: reasoningContent))
    }
    
    /// 添加带推理内容的助手消息到数组
    ///
    /// 专门用于 o1、o3 等推理模型，当需要在历史消息中保留推理过程时使用。
    ///
    /// - Parameters:
    ///   - text: 消息的文本内容
    ///   - reasoningContent: 推理模型的思考过程内容
    ///   - toolCalls: 助手请求的工具调用列表
    ///   - name: 消息的可选名称标识符
    public mutating func addAssistantMessageWithReasoning(
        _ text: String,
        reasoningContent: String,
        toolCalls: [AssistantMessageParam.ToolCallParam]? = nil,
        name: String? = nil
    ) {
        self.append(.assistantWithReasoning(text, reasoningContent: reasoningContent, toolCalls: toolCalls, name: name))
    }
    
    /// 添加工具响应消息
    public mutating func addToolMessage(_ text: String, toolCallId: String) {
        self.append(.tool(ToolMessageParam(content: .textContent(text), toolCallId: toolCallId)))
    }
    
    /// 添加带图片的工具响应消息
    public mutating func addToolMessageWithImages(_ text: String, imageDatas: [Data], detail: ToolMessageParam.Content.ContentPart.ImageContent.ImageURL.Detail = .auto, toolCallId: String) {
        self.append(.tool(
            ToolMessageParam(
                content: .contentParts(
                    imageDatas.map { imageData in
                        ToolMessageParam.Content.ContentPart.image(
                            ToolMessageParam.Content.ContentPart.ImageContent(
                                imageUrl: ToolMessageParam.Content.ContentPart.ImageContent.ImageURL(
                                    imageData: imageData,
                                    detail: detail
                                )
                            )
                        )
                    } + [
                        ToolMessageParam.Content.ContentPart.text(
                            ToolMessageParam.Content.ContentPart.TextContent(text: text)
                        )
                    ]
                ),
                toolCallId: toolCallId
            )
        ))
    }
}
