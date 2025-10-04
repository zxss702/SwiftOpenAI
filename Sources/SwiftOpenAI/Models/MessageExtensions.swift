import Foundation

// MARK: - ChatCompletionMessageParam 便捷方法
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
    public static nonisolated func assistant(
        _ text: String,
        toolCalls: [AssistantMessageParam.ToolCallParam]? = nil,
        name: String? = nil
    ) -> Self {
        return .assistant(
            AssistantMessageParam(
                content: text,
                name: name,
                toolCalls: (toolCalls?.isEmpty ?? true) ? nil : toolCalls
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
    
    /// 创建工具调用消息
    public static nonisolated func assistantWithToolCalls(
        _ toolCalls: [AssistantMessageParam.ToolCallParam]
    ) -> Self {
        return .assistant(
            AssistantMessageParam(
                content: nil,
                name: nil,
                toolCalls: toolCalls
            )
        )
    }
}

// MARK: - 便捷属性
extension ChatQuery.ChatCompletionMessageParam {
    
    /// 获取消息内容（如果有的话）
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
    
    /// 获取消息的名称（如果有的话）
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
    
    /// 获取工具调用（如果是助手消息的话）
    public var toolCalls: [AssistantMessageParam.ToolCallParam]? {
        if case .assistant(let assistantParam) = self {
            return assistantParam.toolCalls
        }
        return nil
    }
}

// MARK: - 数组便捷方法
extension Array where Element == ChatQuery.ChatCompletionMessageParam {
    
    /// 添加用户消息
    public mutating func addUserMessage(_ text: String, name: String? = nil) {
        self.append(.user(text, name: name))
    }
    
    /// 添加系统消息
    public mutating func addSystemMessage(_ text: String, name: String? = nil) {
        self.append(.system(text, name: name))
    }
    
    /// 添加助手消息
    public mutating func addAssistantMessage(_ text: String, toolCalls: [AssistantMessageParam.ToolCallParam]? = nil, name: String? = nil) {
        self.append(.assistant(text, toolCalls: toolCalls, name: name))
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
