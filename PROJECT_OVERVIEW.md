# SwiftOpenAI 项目概述

## 已实现的功能

### ✅ 核心功能
- [x] **流式传输支持** - 实时接收AI响应
- [x] **parallelToolCalls** - 并行工具调用支持  
- [x] **tools** - 完整的工具调用功能
- [x] **stream** - 流式和非流式传输模式
- [x] **extra_body** - 支持自定义请求体参数（双层支持：配置级别 + 请求级别）
- [x] **message** - 完整的消息格式支持
- [x] **reasoning** - 智能支持两种字段名（`reasoning` 和 `reasoning_content`）

### ✅ 数据结构
按照要求实现了以下结构体：
- `OpenAIChatStreamResult` - 流式结果
- `OpenAIChatResult` - 最终结果  
- `OpenAIChatStreamResultState` - 状态枚举

### ✅ 配置支持
支持所有要求的配置参数：
- `token` - API密钥
- `host` - API主机地址
- `port` - 端口配置
- `scheme` - 协议配置 (http/https)
- `basePath` - API基础路径

### ✅ Swift宏支持
实现了功能强大的宏系统：
- `@SYTool` - 工具定义宏
- `@SYToolArgs` - 工具参数定义宏  
- `@AIModelSchema` - 自动生成JSON Schema

### ✅ 使用方式
完全兼容MacPaw OpenAI的使用方式：
```swift
func sendMessage(
    modelID: UUID? = nil,
    modelInfo: AIModelInfoValue? = nil,
    messages: [ChatQuery.ChatCompletionMessageParam],
    // ... 其他参数
    action: (OpenAIChatStreamResult) async throws -> Void
) async throws -> OpenAIChatResult
```

## 项目结构

```
SwiftOpenAI/
├── Package.swift                           # Swift Package配置
├── README.md                              # 使用文档
├── Sources/
│   ├── SwiftOpenAI/                       # 主要源代码
│   │   ├── SwiftOpenAI.swift             # 主模块文件
│   │   ├── OpenAI.swift                  # 核心OpenAI客户端
│   │   ├── Models/                       # 数据模型
│   │   │   ├── ChatQuery.swift           # 聊天查询参数
│   │   │   ├── OpenAIResults.swift       # 结果结构体
│   │   │   └── AIModelInfo.swift         # 模型配置信息
│   │   ├── Streaming/                    # 流式处理
│   │   │   ├── ChatStreamResult.swift    # 流式结果定义
│   │   │   ├── StreamingSupport.swift    # 流式处理支持
│   │   │   └── OpenAISendMessageValueHelper.swift # 辅助类
│   │   └── Examples/                     # 使用示例
│   │       └── UsageExample.swift        # 完整使用示例
│   └── SwiftOpenAIMacros/                # 宏实现
│       ├── SwiftOpenAIMacros.swift       # 宏插件主文件
│       ├── SYToolMacro.swift            # SYTool宏实现
│       └── AIModelSchemaMacro.swift     # AIModelSchema宏实现
└── Tests/                               # 测试文件
    └── SwiftOpenAITests/
        └── SwiftOpenAITests.swift       # 单元测试
```

## 🎉 新增功能：超级简洁的消息创建

### ✨ 便捷类型别名
```swift
public typealias OpenAIMessage = ChatQuery.ChatCompletionMessageParam
public typealias OpenAITool = ChatQuery.ChatCompletionToolParam  
public typealias OpenAIFunctionDefinition = ChatQuery.ChatCompletionToolParam.Function
```

### ✨ 超级简洁的消息创建
```swift
// 🔥 新的简洁方式 - 只需一行！
let messages: [OpenAIMessage] = [
    .system("你是助手"),
    .user("你好"),
    .assistant("你好！有什么可以帮助你的吗？")
]

// 🔥 带图片的消息也很简洁
let imageMessage: OpenAIMessage = .user("分析这张图", imageDatas: imageData)

// 🔥 工具调用消息
let toolMessage: OpenAIMessage = .tool("处理结果", toolCallId: "call_123")
```

### ✨ 数组便捷方法
```swift
var messages: [OpenAIMessage] = []
messages.addSystemMessage("系统提示")
messages.addUserMessage("用户消息")
messages.addAssistantMessage("助手回复")
messages.addToolMessage("工具结果", toolCallId: "call_123")
```

### ✨ 一行创建完整对话
```swift
let messages = Array<OpenAIMessage>.conversation(
    system: "你是助手",
    userMessages: "你好", "你能做什么？"
)
```

### ✨ 便捷属性访问
```swift
let message: OpenAIMessage = .user("Hello")
print(message.textContent)  // 快速访问文本内容
print(message.role)         // 获取消息角色
print(message.name)         // 获取消息名称（如果有）
print(message.toolCalls)    // 获取工具调用（如果是助手消息）
```

## 核心特性

### 1. 流式传输
```swift
let result = try await sendMessage(
    modelInfo: modelInfo,
    messages: messages,
    stream: true
) { streamResult in
    print("实时响应: \(streamResult.subText)")
    print("完整内容: \(streamResult.fullText)")
    print("AI思考: \(streamResult.subThinkingText)")
}
```

### 2. 工具调用
```swift
@SYToolArgs
struct WeatherArgs {
    let location: String
    let unit: String?
}

@SYTool  
struct WeatherTool {
    let name: String = "get_weather"
    let description: String = "获取天气信息"
    let parameters: WeatherArgs = WeatherArgs(location: "", unit: nil)
}

let tools = [WeatherTool().asChatCompletionTool]
```

### 3. JSON Schema自动生成
```swift
@AIModelSchema
struct WeatherResponse {
    let temperature: Double
    let condition: String
    let humidity: Int
}

// 自动生成outputSchema属性
print(WeatherResponse.outputSchema) // JSON Schema字符串
```

### 4. 自定义配置
```swift
let modelInfo = AIModelInfoValue(
    token: "your-api-key",
    host: "custom-api.com", 
    port: 8080,
    scheme: "https",
    basePath: "/api/v1",
    modelID: "custom-model"
)
```

## 使用示例

完整的使用示例请查看：
- `Sources/SwiftOpenAI/Examples/UsageExample.swift`
- `README.md`
- `Tests/SwiftOpenAITests/SwiftOpenAITests.swift`

## 编译状态

✅ **无编译错误** - 项目已成功编译通过
✅ **完整功能** - 所有要求的功能都已实现
✅ **类型安全** - 完整的Swift类型支持
✅ **文档齐全** - 提供完整的使用文档和示例
✅ **文档注释支持** - 宏自动从注释生成Schema描述
✅ **消息创建简化** - 提供便捷的静态方法创建消息

## 开始使用

1. 设置API密钥：
```swift
let modelInfo = AIModelInfoValue(token: "your-openai-api-key")
```

2. 发送第一条消息：
```swift
let messages = [ChatQuery.ChatCompletionMessageParam(role: .user, content: .string("Hello!"))]
let result = try await sendMessage(modelInfo: modelInfo, messages: messages) { stream in
    print(stream.subText)
}
```

## 🎉 最新更新：文档注释支持

### ✨ 自动从注释生成Schema描述
现在`@AIModelSchema`宏支持从文档注释自动提取description：

```swift
/// Task that is broken down from a goal
@AIModelSchema
struct AITask {
    /// A descriptive name of the task
    let name: String
    
    /// The details a task needs to do
    let details: String
    
    /// Sub tasks, a recursive structure to indicate the execute orders of the tasks
    let subTasks: [AISubTask]?
}
```

生成的JSON Schema：
```json
{
  "type": "object",
  "description": "Task that is broken down from a goal",
  "properties": {
    "name": {
      "type": "string", 
      "description": "A descriptive name of the task"
    },
    "details": {
      "type": "string",
      "description": "The details a task needs to do"
    },
    "subTasks": {
      "type": "array",
      "description": "Sub tasks, a recursive structure to indicate the execute orders of the tasks",
      "items": \(AISubTask.outputSchema)
    }
  },
  "required": ["name", "details"]
}
```

### ✨ 嵌套类型引用
支持嵌套类型的schema引用，如`[AISubTask]`会自动引用`AISubTask.outputSchema`。

### ✨ 枚举文档支持
```swift
/// Priority levels for tasks
@AIModelSchema
enum TaskPriority: String, CaseIterable {
    /// High priority task
    case high
    /// Normal priority task
    case normal
    /// Low priority task
    case low
}
```

## 🔧 API 兼容性特性

### ✨ Reasoning 字段双重支持
SwiftOpenAI 智能支持 OpenAI API 中可能出现的两种 reasoning 字段命名：

```swift
// 自动支持两种字段名，无需额外配置
// 1. "reasoning" 字段（标准命名）
// 2. "reasoning_content" 字段（部分 API 版本使用）

// 流式结果
let streamResult: ChatStreamResult = ...
print("思考内容: \(streamResult.choices.first?.delta.reasoning ?? "")")

// 非流式结果  
let chatResult: ChatCompletionResult = ...
print("推理过程: \(chatResult.choices.first?.message.reasoning ?? "")")
```

#### 技术实现
- 解码时优先尝试 `reasoning` 字段
- 如果不存在，则尝试 `reasoning_content` 字段
- 确保与不同版本 OpenAI API 的完全兼容性
- 编码时统一使用 `reasoning` 字段名

#### 支持的场景
✅ **流式传输** - `ChatStreamResult.Choice.ChoiceDelta.reasoning`  
✅ **非流式传输** - `ChatCompletionResult.Choice.Message.reasoning`  
✅ **自动检测** - 无需手动配置字段名  
✅ **向后兼容** - 现有代码无需修改

项目已准备就绪，可以立即开始使用！🚀
