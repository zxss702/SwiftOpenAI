import SwiftOpenAI
import Foundation

// MARK: - 工具定义示例

@SYToolArgs
struct 前言 {
    let 内容: String
}

@SYTool
struct forewordTool {
    let name: String = "前言"
    let description: String = "向用户说明你下一步的计划。不应该超过两句话。"
    let parameters = 前言.self
}

@SYToolArgs
struct WeatherArgs {
    let location: String
    let unit: String?
}

@SYTool
struct WeatherTool {
    let name = "get_weather"
    let description = "获取指定城市的天气信息"
    let parameters = WeatherArgs.self
}

// MARK: - 使用示例

@main
struct MainActorIsolationExample {
    static func main() async throws {
        print("🚀 SwiftOpenAI Main Actor 隔离问题修复示例")
        print("=" * 50)
        
        // 1. 创建工具实例（现在不会产生 Main actor 隔离错误）
        let foreword = forewordTool()
        let weather = WeatherTool()
        
        print("✅ 工具创建成功")
        print("   - forewordTool: \(foreword.name)")
        print("   - WeatherTool: \(weather.name)")
        
        // 2. 转换为 ChatCompletionToolParam（现在不会产生 Main actor 隔离错误）
        let forewordChatTool = foreword.asChatCompletionTool
        let weatherChatTool = weather.asChatCompletionTool
        
        print("✅ 工具转换成功")
        print("   - forewordTool 转换: \(forewordChatTool.function.name)")
        print("   - WeatherTool 转换: \(weatherChatTool.function.name)")
        
        // 3. 创建工具数组（现在不会产生 Main actor 隔离错误）
        let tools: [any OpenAIToolConvertible] = [foreword, weather]
        
        print("✅ 工具数组创建成功")
        print("   - 工具数量: \(tools.count)")
        
        // 4. 在 sendMessage 中使用工具（现在不会产生 Main actor 隔离错误）
        let modelInfo = AIModelInfoValue(
            token: "your-api-token",
            modelID: "gpt-4"
        )
        
        let messages: [OpenAIMessage] = [
            .system("你是一个有用的AI助手"),
            .user("请使用前言工具，然后查询北京的天气")
        ]
        
        print("✅ 准备发送消息")
        print("   - 消息数量: \(messages.count)")
        print("   - 工具数量: \(tools.count)")
        
        // 注意：这里只是演示，不实际发送请求
        // 在实际使用中，你可以这样调用：
        /*
        let result = try await sendMessage(
            modelInfo: modelInfo,
            messages: messages,
            tools: tools,  // 🎯 现在不会产生 Main actor 隔离错误
            temperature: 0.7
        ) { streamResult in
            print("💬 AI回复: \(streamResult.subText)")
        }
        */
        
        print("✅ 所有操作完成，没有 Main actor 隔离错误！")
        print("=" * 50)
        print("🎉 Swift 6 兼容性测试通过")
    }
}
