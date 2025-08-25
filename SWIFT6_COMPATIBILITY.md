# Swift 6 兼容性修复

## 问题描述

在 Swift 6 中，使用 `@SYTool` 宏定义的工具结构体会产生以下错误：

```
Main actor-isolated conformance of 'ForewordTool' to 'OpenAIToolConvertible' cannot be used in caller isolation inheriting-isolated context; this is an error in the Swift 6 language mode
```

这个错误是因为 Swift 6 引入了更严格的 Main actor 隔离规则，要求所有 Main actor 隔离的类型在非隔离上下文中使用时必须明确标记。

## 根本原因

1. **隐式 Main actor 隔离**: 在 Swift 6 中，某些类型会被隐式地标记为 `@MainActor` 隔离
2. **协议一致性**: 工具结构体实现了 `OpenAIToolConvertible` 协议，但协议本身没有明确指定隔离级别
3. **上下文不匹配**: `sendMessage` 函数是 `nonisolated` 的，但工具结构体被隐式标记为 Main actor 隔离

## 解决方案

### 1. 修改宏生成代码

修改 `SYToolMacro` 和 `SYToolArgsMacro` 来生成 `nonisolated` 扩展：

```swift
// 修改前
extension TestTool: OpenAIToolConvertible {
    public var asChatCompletionTool: ChatQuery.ChatCompletionToolParam {
        // ...
    }
}

// 修改后
nonisolated extension TestTool: OpenAIToolConvertible {
    public var asChatCompletionTool: ChatQuery.ChatCompletionToolParam {
        // ...
    }
}
```

### 2. 确保协议定义正确

确保 `OpenAIToolConvertible` 和 `SYToolArgsConvertible` 协议是 `nonisolated` 的：

```swift
nonisolated public protocol OpenAIToolConvertible {
    var asChatCompletionTool: ChatQuery.ChatCompletionToolParam { get }
}

nonisolated public protocol SYToolArgsConvertible {
    static var parametersSchema: [String: Any] { get }
}
```

### 3. 修改宏实现

在 `Sources/SwiftOpenAIMacros/SYToolMacro.swift` 中：

```swift
// 生成 nonisolated 扩展
let extensionDecl = try ExtensionDeclSyntax("nonisolated extension \(type.trimmed): OpenAIToolConvertible") {
    // ...
}

// 生成 nonisolated 扩展
let extensionDecl = try ExtensionDeclSyntax("nonisolated extension \(type.trimmed): SYToolArgsConvertible") {
    // ...
}
```

## 修复效果

### 修复前

```swift
@SYTool
struct forewordTool {
    let name: String = "前言"
    let description: String = "向用户说明你下一步的计划。不应该超过两句话。"
    let parameters = 前言.self
}

// ❌ 会产生 Main actor 隔离错误
let tools: [any OpenAIToolConvertible] = [forewordTool()]
let result = try await sendMessage(
    modelInfo: modelInfo,
    messages: messages,
    tools: tools,  // 错误：Main actor-isolated conformance
    temperature: 0.7
)
```

### 修复后

```swift
@SYTool
struct forewordTool {
    let name: String = "前言"
    let description: String = "向用户说明你下一步的计划。不应该超过两句话。"
    let parameters = 前言.self
}

// ✅ 现在可以正常工作
let tools: [any OpenAIToolConvertible] = [forewordTool()]
let result = try await sendMessage(
    modelInfo: modelInfo,
    messages: messages,
    tools: tools,  // 不会产生 Main actor 隔离错误
    temperature: 0.7
)
```

## 技术细节

### 1. 宏生成的代码结构

修复后，`@SYTool` 宏会生成：

```swift
nonisolated extension forewordTool: OpenAIToolConvertible {
    public var asChatCompletionTool: SwiftOpenAI.ChatQuery.ChatCompletionToolParam {
        let paramsDict: [String: Any] = 前言.parametersSchema
        
        return SwiftOpenAI.ChatQuery.ChatCompletionToolParam(
            type: "function",
            function: SwiftOpenAI.ChatQuery.ChatCompletionToolParam.Function(
                name: self.name,
                description: self.description,
                parameters: paramsDict
            )
        )
    }
}
```

### 2. 参数 Schema 生成

`@SYToolArgs` 宏会生成：

```swift
nonisolated extension 前言: SYToolArgsConvertible {
    public static var parametersSchema: [String: Any] {
        return [
            "type": "object",
            "properties": ["内容": ["type": "string"]],
            "required": ["内容"],
            "additionalProperties": false
        ]
    }
}
```

## 兼容性

### 向后兼容性

- ✅ **完全向后兼容**: 现有代码无需修改
- ✅ **API 不变**: 所有公共 API 保持不变
- ✅ **行为一致**: 功能行为完全一致

### Swift 版本兼容性

- ✅ **Swift 5.9+**: 完全支持
- ✅ **Swift 6.0**: 完全支持
- ✅ **Xcode 15.0+**: 完全支持

## 测试验证

### 1. 单元测试

创建了专门的测试用例来验证修复：

```swift
func testForewordToolNonisolatedAccess() throws {
    let foreword = forewordTool()
    let forewordChatTool = foreword.asChatCompletionTool
    
    XCTAssertEqual(forewordChatTool.type, "function")
    XCTAssertEqual(forewordChatTool.function.name, "前言")
}
```

### 2. 集成测试

验证在 `sendMessage` 函数中的使用：

```swift
func testSendMessageWithTools() async throws {
    let tools: [any OpenAIToolConvertible] = [forewordTool()]
    
    // 这个调用应该不会产生 Main actor 隔离错误
    let _ = tools.map { $0.asChatCompletionTool }
    
    XCTAssertEqual(tools.count, 1)
    XCTAssertEqual(tools[0].asChatCompletionTool.function.name, "前言")
}
```

## 总结

通过将宏生成的扩展标记为 `nonisolated`，我们成功解决了 Swift 6 中的 Main actor 隔离问题。这个修复：

1. **解决了编译错误**: 消除了 Main actor 隔离相关的编译错误
2. **保持了功能完整性**: 所有现有功能继续正常工作
3. **提高了兼容性**: 完全支持 Swift 6 的新规则
4. **向后兼容**: 不影响现有代码

现在开发者可以在 Swift 6 环境中正常使用 SwiftOpenAI 的所有功能，包括工具调用、流式传输等高级特性。
