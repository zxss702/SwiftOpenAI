# SwiftOpenAI

🚀 **现代化的 Swift OpenAI SDK** - 使用纯 Swift Foundation 实现，支持流式传输、工具调用、Swift 宏、多模态等高级功能。

[![Swift](https://img.shields.io/badge/swift-5.9+-brightgreen.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey.svg)](https://github.com/apple/swift)

## ✨ 特性

### 🎯 核心功能
- ✅ **流式传输** - 实时获取 AI 响应，支持思考过程（reasoning）
- ✅ **工具调用** - 完整支持 Function Calling 和并行工具调用
- ✅ **多模态** - 支持文本、图像混合输入
- ✅ **Swift 宏** - 使用 `@SYTool`、`@SYToolArgs`、`@AIModelSchema` 自动生成代码
  - 🆕 **简洁参数定义** - 使用 `= TypeName.self` 语法，简洁优雅
  - ✨ **简化工具调用** - 直接传入工具对象，无需 `.asChatCompletionTool` 转换
- ✅ **类型安全** - 完整的 Swift 类型系统支持
- ✅ **async/await** - 现代异步编程

### 🔧 高级特性
- ✅ **Extra Body** - 双层支持（配置级别 + 请求级别）
- ✅ **API 兼容性** - 智能支持 `reasoning` 和 `reasoning_content` 字段
- ✅ **自定义端点** - 支持任意 OpenAI 兼容 API（如 SiliconFlow）
- ✅ **便捷 API** - 一行代码创建消息和对话
- ✅ **错误处理** - 完整的错误类型和本地化

## 📦 安装

### Swift Package Manager

在 `Package.swift` 中添加依赖：

```swift
dependencies: [
    .package(url: "https://github.com/zxss702/SwiftOpenAI.git", from: "1.0.0")
]
```

或在 Xcode 中：`File > Add Package Dependencies...`

## 🚀 快速开始

### 基础聊天

```swift
import SwiftOpenAI

// 配置 API
let modelInfo = AIModelInfoValue(
    token: "your-openai-api-key",
    modelID: "gpt-4"
)

// 超简洁的消息创建 ✨
let messages: [OpenAIMessage] = [
    .system("你是一个有用的 AI 助手"),
    .user("你好！请介绍一下你自己")
]

// 流式传输
let result = try await sendMessage(
    modelInfo: modelInfo,
    messages: messages,
    temperature: 0.7,
    stream: true
) { streamResult in
    print("💭 AI 思考: \(streamResult.subThinkingText)")
    print("💬 AI 回复: \(streamResult.subText)")
    print("📝 完整内容: \(streamResult.fullText)")
}

print("✅ 对话完成: \(result.fullText)")
```

### 一行创建对话 🎉

```swift
// 超级简洁！
let messages = Array<OpenAIMessage>.conversation(
    system: "你是编程助手",
    userMessages: "什么是 Swift？", "如何学习 Swift？"
)
```

## 🛠 工具调用（Function Calling）

### 参数定义语法

使用 `@SYTool` 宏定义工具参数的推荐语法：

```swift
@SYTool
struct MyTool {
    let name = "my_tool"
    let description = "工具描述"
    
    // 使用 .self 语法定义参数类型（推荐）
    let parameters = MyArgs.self
}
```

#### 具体示例

```swift
// 中文工具定义示例
@SYTool
struct forewordTool {
    let name: String = "前言"
    let description: String = "向用户说明你下一步的计划。不应该超过两句话。"
    let parameters = 前言.self  // 🎯 支持中文类型名！
}

@SYToolArgs
struct 前言 {
    /// 你想说的话。
    let 内容: String
}
```

### 定义工具

使用 Swift 宏轻松定义工具：

```swift
// 1. 定义参数结构
@SYToolArgs
struct WeatherArgs {
    /// 城市名称
    let location: String
    /// 温度单位，可选
    let unit: String?
    /// 是否包含预报
    let includeForecast: Bool
}

// 2. 定义工具 - 使用 .self 语法
@SYTool
struct WeatherTool {
    let name = "get_weather"
    let description = "获取指定城市的天气信息"
    let parameters = WeatherArgs.self
}

// 3. 使用工具 - ✨ 简化语法
let result = try await sendMessage(
    modelInfo: modelInfo,
    messages: [.user("北京今天天气如何？")],
    tools: [WeatherTool()],  // 🎯 直接传入工具对象，无需 .asChatCompletionTool
    temperature: 0.7
) { streamResult in
    print(streamResult.subText, terminator: "")
    
    // 显示工具调用
    for toolCall in streamResult.allToolCalls {
        print("🔧 使用工具: \(toolCall.function?.name ?? "")")
    }
}

// 4. 定义返回数据结构（自动生成 JSON Schema）
/// 天气信息响应
@AIModelSchema
struct WeatherResponse {
    /// 当前温度
    let temperature: Double
    /// 天气状况
    let condition: String
    /// 湿度百分比
    let humidity: Int
    /// 未来几天预报
    let forecast: [DailyForecast]?
}
```

### 使用工具

```swift
let weatherTool = WeatherTool()
let tools = [weatherTool.asChatCompletionTool]

let messages: [OpenAIMessage] = [
    .system("你是天气助手，可以查询天气信息"),
    .user("北京今天天气怎么样？")
]

let result = try await sendMessage(
    modelInfo: modelInfo,
    messages: messages,
    tools: tools,
    parallelToolCalls: true  // 支持并行调用
) { streamResult in
    // 处理工具调用
    for toolCall in streamResult.allToolCalls {
        print("🔧 调用工具: \(toolCall.function?.name ?? "")")
        print("📋 参数: \(toolCall.function?.arguments ?? "")")
    }
    print("💬 回复: \(streamResult.subText)")
}
```

## 🖼 多模态支持

### 图像分析

```swift
// 读取图像数据
let imageData = // ... 你的图像数据

// 创建带图片的消息 - 超简洁！
let messages: [OpenAIMessage] = [
    .system("你是专业的图像分析师"),
    .user("请分析这张图片的内容", imageDatas: imageData, detail: .high)
]

let result = try await sendMessage(
    modelInfo: modelInfo,
    messages: messages
) { stream in
    print("🖼️ 图像分析: \(stream.subText)")
}
```

### 多图片处理

```swift
// 支持多张图片
let messages: [OpenAIMessage] = [
    .system("比较这些图片的差异"),
    .user("请比较这两张图片", imageDatas: imageData1, imageData2)
]
```

## 🔧 高级配置

### 自定义 API 端点

```swift
// 使用 SiliconFlow 或其他兼容 API
let modelInfo = AIModelInfoValue(
    token: "your-api-key",
    host: "api.siliconflow.cn",
    port: nil,
    scheme: "https",
    basePath: "/v1",
    modelID: "Qwen/Qwen2.5-7B-Instruct"
)
```

### Extra Body 参数

```swift
// 配置级别的额外参数
let config = OpenAIConfiguration(
    token: "your-token",
    extraBody: [
        "provider": "custom",
        "timeout": 30
    ]
)

// 请求级别的额外参数（会覆盖配置级别）
let query = ChatQuery(
    messages: messages,
    model: "gpt-4",
    extraBody: [
        "custom_param": .string("value"),
        "max_retries": .int(3),
        "enable_cache": .bool(true),
        "metadata": .object([
            "user_id": .string("123"),
            "session_id": .string("abc")
        ])
    ]
)
```

## ✨ 简化工具语法

SwiftOpenAI v2.0 引入了简化的工具调用语法，让工具使用更加直观和便捷。

### 🎯 新语法 vs 旧语法

**🆕 新的简化语法（推荐）**：
```swift
// 直接传入工具对象，自动转换
let result = try await sendMessage(
    modelInfo: modelInfo,
    messages: messages,
    tools: [WeatherTool(), CalculatorTool()],  // 🎯 简洁优雅
    temperature: 0.7
) { streamResult in
    print(streamResult.subText, terminator: "")
}
```

**🔧 传统语法（仍然支持）**：
```swift
// 需要手动转换工具对象
let result = try await sendMessage(
    modelInfo: modelInfo,
    messages: messages,
    tools: [WeatherTool().asChatCompletionTool, CalculatorTool().asChatCompletionTool],  // 🔄 需要转换
    temperature: 0.7
) { streamResult in
    print(streamResult.subText, terminator: "")
}
```

### 📊 语法对比

| 特性 | 新语法 | 传统语法 |
|------|-------|----------|
| **简洁性** | ✅ 更简洁 | ❌ 较繁琐 |
| **类型安全** | ✅ 完全类型安全 | ✅ 完全类型安全 |
| **自动转换** | ✅ 自动处理 | ❌ 手动转换 |
| **代码可读性** | ✅ 更清晰 | ❌ 较冗长 |
| **兼容性** | ✅ 向下兼容 | ✅ 继续支持 |

### 🚀 实际使用示例

```swift
import SwiftOpenAI

// 定义多个工具
@SYTool
struct WeatherTool {
    let name = "get_weather"
    let description = "获取天气信息"
    let parameters = WeatherArgs.self
}

@SYTool  
struct CalculatorTool {
    let name = "calculator"
    let description = "执行数学计算"
    let parameters = CalculatorArgs.self
}

// 🎯 使用简化语法 - 一次性传入多个工具
let result = try await sendMessage(
    modelInfo: AIModelInfoValue(
        token: "your-api-token",
        host: "api.openai.com",
        modelID: "gpt-4-turbo"
    ),
    messages: [.user("北京天气怎么样？然后帮我计算 15 + 27")],
    tools: [WeatherTool(), CalculatorTool()],  // ✨ 直接传入多个工具
    temperature: 0.8
) { streamResult in
    print("💬 AI回复: \(streamResult.subText, terminator: "")")
    
    // 实时显示工具调用
    for toolCall in streamResult.allToolCalls {
        print("\n🔧 调用工具: \(toolCall.function?.name ?? "未知")")
        print("📋 参数: \(toolCall.function?.arguments ?? "无")")
    }
}

print("✅ 最终回复: \(result.fullText)")
```

## 📋 便捷的消息管理

### 数组扩展方法

```swift
var messages: [OpenAIMessage] = []

// 便捷添加方法
messages.addSystemMessage("你是AI助手")
messages.addUserMessage("你好")
messages.addAssistantMessage("你好！有什么我可以帮助的吗？")
messages.addToolMessage("工具执行结果", toolCallId: "call_123")
```

### 消息属性访问

```swift
let message: OpenAIMessage = .user("Hello")

print("内容: \(message.textContent ?? "无内容")")
print("角色: \(message.role)")
print("名称: \(message.name ?? "无名称")")

// 检查工具调用
if let toolCalls = message.toolCalls {
    print("包含 \(toolCalls.count) 个工具调用")
}
```

## 🤖 AI 思考过程

访问 AI 的推理过程（支持 `reasoning` 和 `reasoning_content` 字段）：

```swift
let result = try await sendMessage(
    modelInfo: modelInfo,
    messages: messages
) { streamResult in
    // 实时查看 AI 思考过程
    if !streamResult.subThinkingText.isEmpty {
        print("🧠 AI 思考: \(streamResult.subThinkingText)")
    }
    
    // AI 的回复内容
    if !streamResult.subText.isEmpty {
        print("💬 AI 回复: \(streamResult.subText)")
    }
    
    // 检查状态
    switch streamResult.state {
    case .wait:
        print("⏳ 等待中...")
    case .think:
        print("🤔 思考中")
    case .text:
        print("📝 输出内容")
    }
}
```

## 🔄 非流式传输

```swift
// 如果不需要实时响应，可以使用同步版本
let result = try await sendMessageSync(
    modelInfo: modelInfo,
    messages: messages,
    temperature: 0.7,
    maxCompletionTokens: 1000
)

print("最终结果: \(result.fullText)")
```

## ❌ 错误处理

```swift
do {
    let result = try await sendMessage(/* ... */) { _ in }
} catch OpenAIError.missingToken {
    print("❌ 缺少 API 密钥")
} catch OpenAIError.networkError(let error) {
    print("❌ 网络错误: \(error)")
} catch OpenAIError.decodingError(let error) {
    print("❌ 解码错误: \(error)")
} catch OpenAIError.invalidResponse {
    print("❌ 无效响应")
} catch {
    print("❌ 未知错误: \(error)")
}
```

## 🎨 JSON Schema 自动生成

```swift
/// 任务定义（支持文档注释！）
@AIModelSchema
struct Task {
    /// 任务名称
    let name: String
    /// 任务描述
    let description: String
    /// 优先级
    let priority: TaskPriority
    /// 子任务列表
    let subtasks: [Task]?
}

/// 任务优先级
@AIModelSchema
enum TaskPriority: String, CaseIterable {
    /// 高优先级
    case high
    /// 普通优先级
    case normal  
    /// 低优先级
    case low
}

// 自动生成的 JSON Schema
print(Task.outputSchema) // 完整的 JSON Schema 字符串
```

## 🧪 完整示例

```swift
import SwiftOpenAI

// 智能计算器助手
class CalculatorAssistant {
    
    // 定义计算器工具
    @SYToolArgs
    struct CalculatorArgs {
        let operation: String  // "add", "subtract", "multiply", "divide"
        let a: Double
        let b: Double
    }
    
    @SYTool
    struct CalculatorTool {
        let name = "calculator"
        let description = "执行基本数学运算"
        let parameters = CalculatorArgs.self  // 使用推荐的 .self 形式
    }
    
    @AIModelSchema
    struct CalculationResult {
        let result: Double
        let operation: String
        let operands: [Double]
    }
    
    let modelInfo = AIModelInfoValue(
        token: "your-openai-api-key",
        modelID: "gpt-4"
    )
    
    func solve(_ problem: String) async throws -> String {
        let messages = Array<OpenAIMessage>.conversation(
            system: "你是数学助手，可以使用计算器解决问题",
            userMessages: problem
        )
        
        let calculator = CalculatorTool()
        
        let result = try await sendMessage(
            modelInfo: modelInfo,
            messages: messages,
            tools: [calculator.asChatCompletionTool],
            temperature: 0.1
        ) { streamResult in
            print("🧮 计算中: \(streamResult.subText)")
            
            // 显示工具调用
            for toolCall in streamResult.allToolCalls {
                print("🔧 使用工具: \(toolCall.function?.name ?? "")")
            }
        }
        
        return result.fullText
    }
}

// 使用示例
let assistant = CalculatorAssistant()
let answer = try await assistant.solve("计算 (15.5 + 23.7) × 2 - 10.2")
print("📊 结果: \(answer)")
```

## 🌐 API 兼容性

SwiftOpenAI 与以下服务兼容：

- ✅ **OpenAI** - 原生支持
- ✅ **SiliconFlow** - 已测试通过
- ✅ **Azure OpenAI** - 支持
- ✅ **其他 OpenAI 兼容 API** - 通用支持

## 📊 性能

基于真实测试数据：
- 📡 **大量消息处理**: 51条消息，编码耗时 < 0.001秒
- 🔧 **工具参数生成**: JSON Schema 自动生成
- 🖼️ **多模态支持**: 图像+文本消息正常处理
- ⚡ **流式传输**: 实时响应，低延迟

## 🔍 系统要求

- macOS 14.0+
- Swift 5.9+
- Xcode 15.0+

## 🤝 贡献

欢迎贡献代码！请查看 [贡献指南](CONTRIBUTING.md)。

## 📄 许可证

MIT License - 查看 [LICENSE](LICENSE) 文件了解详情。

## 🆘 支持

- 📖 [文档](https://github.com/your-repo/SwiftOpenAI/wiki)
- 🐛 [问题反馈](https://github.com/your-repo/SwiftOpenAI/issues)
- 💬 [讨论区](https://github.com/your-repo/SwiftOpenAI/discussions)

---

⭐ **如果这个项目对你有帮助，请给个星标支持！**