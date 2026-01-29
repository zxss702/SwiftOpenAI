import Foundation

// MARK: - Protocols

/// AI 模型 JSON Schema 协议
///
/// 用于标识可以自动生成 JSON Schema 的类型。
/// 通过 `@AIModelSchema` 宏自动生成实现。
///
/// ## Topics
///
/// ### Schema 生成
/// - ``outputSchema``
///
public protocol AIModelSchema {
    /// JSON Schema 字符串表示
    static var outputSchema: String { get }
}

/// 工具参数转换协议
///
/// 用于将 Swift 类型转换为 OpenAI 工具参数格式。
/// 通过 `@SYToolArgs` 宏自动生成实现。
///
/// ## Topics
///
/// ### 参数转换
/// - ``toolProperties``
/// - ``parametersSchema``
///
public protocol SYToolArgsConvertible {
    /// 工具属性的 JSON 字符串表示
    static var toolProperties: String { get }
    
    /// 参数 Schema 字典
    static var parametersSchema: [String: Any] { get }
}

// MARK: - Macros

/// AI 模型 Schema 宏
///
/// 自动为类型生成 `AIModelSchema` 协议实现，
/// 将 Swift 类型转换为 JSON Schema 格式。
///
/// ## Example
///
/// ```swift
/// @AIModelSchema
/// struct MyModel: Codable {
///     let name: String
///     let age: Int
/// }
/// ```
@attached(extension, conformances: AIModelSchema, names: named(outputSchema))
public macro AIModelSchema() = #externalMacro(module: "SwiftOpenAIMacros", type: "AIModelSchemaMacro")

/// OpenAI 工具宏
///
/// 自动为类型生成 `OpenAIToolConvertible` 协议实现，
/// 使类型可以作为 OpenAI 函数工具使用。
///
/// ## Example
///
/// ```swift
/// @SYTool
/// struct MyTool {
///     let name: String
///     let description: String
/// }
/// ```
@attached(extension, conformances: OpenAIToolConvertible, names: named(asChatCompletionTool))
public macro SYTool() = #externalMacro(module: "SwiftOpenAIMacros", type: "SYToolMacro")

/// 工具参数宏
///
/// 自动为类型生成 `SYToolArgsConvertible` 协议实现，
/// 将参数类型转换为 OpenAI 工具参数格式。
///
/// ## Example
///
/// ```swift
/// @SYToolArgs
/// struct MyToolArgs: Codable {
///     let query: String
///     let limit: Int
/// }
/// ```
@attached(extension, conformances: SYToolArgsConvertible, names: named(parametersSchema), named(toolProperties))
public macro SYToolArgs() = #externalMacro(module: "SwiftOpenAIMacros", type: "SYToolArgsMacro")
