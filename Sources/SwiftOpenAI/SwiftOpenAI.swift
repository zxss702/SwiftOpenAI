import Foundation

// MARK: - 协议定义

/// AIModelSchema协议，用于标识可以生成JSON Schema的类型
public protocol AIModelSchema {
    static var outputSchema: String { get }
}

/// SYToolArgsConvertible协议，用于工具参数转换
public protocol SYToolArgsConvertible {
    static var parametersSchema: [String: Any] { get }
}

// MARK: - Macro Definitions
@attached(extension, conformances: AIModelSchema, names: named(outputSchema))
public macro AIModelSchema() = #externalMacro(module: "SwiftOpenAIMacros", type: "AIModelSchemaMacro")

@attached(extension, conformances: OpenAIToolConvertible, names: named(asChatCompletionTool))
public macro SYTool() = #externalMacro(module: "SwiftOpenAIMacros", type: "SYToolMacro")

@attached(extension, conformances: SYToolArgsConvertible, names: named(parametersSchema))
public macro SYToolArgs() = #externalMacro(module: "SwiftOpenAIMacros", type: "SYToolArgsMacro")
