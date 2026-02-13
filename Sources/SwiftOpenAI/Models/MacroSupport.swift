import Foundation

// MARK: - Tool Conversion

/// OpenAI 工具转换协议
///
/// 使类型可以转换为 `ChatQuery.ChatCompletionToolParam` 格式，
/// 用于 OpenAI API 的函数调用功能。
///
/// ## Topics
///
/// ### 转换方法
/// - ``asChatCompletionTool``
///
public protocol OpenAIToolConvertible: Sendable {
    /// 转换为 ChatQuery.ChatCompletionToolParam
    var asChatCompletionTool: ChatQuery.ChatCompletionToolParam { get }
}

// MARK: - Convenience Extensions

extension ChatQuery.ChatCompletionToolParam {
    /// 从字典创建工具参数
    ///
    /// - Parameter dict: 包含工具定义的字典
    /// - Returns: 工具参数实例，如果字典格式无效则返回 nil
    public static func from(_ dict: [String: Any]) -> ChatQuery.ChatCompletionToolParam? {
        guard let type = dict["type"] as? String,
              let functionDict = dict["function"] as? [String: Any],
              let name = functionDict["name"] as? String else {
            return nil
        }
        
        let description = functionDict["description"] as? String
        let parameters = (functionDict["parameters"] as? [String: Any])?.mapValues { AnyCodableValue.from($0) }
        
        return ChatQuery.ChatCompletionToolParam(
            type: type,
            function: ChatQuery.ChatCompletionToolParam.Function(
                name: name,
                description: description,
                parameters: parameters
            )
        )
    }
}
