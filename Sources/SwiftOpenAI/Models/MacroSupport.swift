import Foundation

// MARK: - 宏支持扩展

/// 重新定义协议以避免宏模块的依赖问题
public protocol OpenAIToolConvertible {
    /// 转换为ChatQuery.ChatCompletionToolParam
    var asChatCompletionTool: ChatQuery.ChatCompletionToolParam { get }
}

/// 便捷方法：从字典创建工具
extension ChatQuery.ChatCompletionToolParam {
    public static func from(_ dict: [String: Any]) -> ChatQuery.ChatCompletionToolParam? {
        guard let type = dict["type"] as? String,
              let functionDict = dict["function"] as? [String: Any],
              let name = functionDict["name"] as? String else {
            return nil
        }
        
        let description = functionDict["description"] as? String
        let parameters = functionDict["parameters"] as? [String: Any]
        
        // 直接使用字典，无需转换
        
        return ChatQuery.ChatCompletionToolParam(
            type: type,
            function: ChatQuery.ChatCompletionToolParam.Function(
                name: name,
                description: description,
                parameters: parameters  // 直接使用字典
            )
        )
    }
}