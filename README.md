# SwiftOpenAI

An AI conversation library for Swift apps, with a unified interface for streaming responses, tool calling, and multimodal messages. Supports four protocols: Chat Completions, Responses, ChatGPT Codex, and Anthropic Messages.

- [Installation](#installation)
- [Sending Messages](#sending-messages)
- [Supported Protocols](#supported-protocols)
- [Tool Calling](#tool-calling)
- [Platform Differences](#platform-differences)
- [Protocol Compatibility](#protocol-compatibility)

## Installation

Use a Swift 6 toolchain and add the dependency through Swift Package Manager. This example targets the repository's current `main` branch:

```swift
// In Package.swift dependencies
.package(url: "https://github.com/zxss702/SwiftOpenAI.git", branch: "main")

// In the consuming target's dependencies
.product(name: "SwiftOpenAI", package: "SwiftOpenAI")
```

You can also add the repository URL in Xcode under `File > Add Package Dependencies…` and select the `main` branch.

## Sending Messages

The request examples below run in an `async throws` context. For UI events, start the request in a `Task` and handle errors at the call site.

### Streaming Responses

```swift
import SwiftOpenAI

let modelInfo = AIModelInfoValue.completions(
    .init(
        token: "YOUR_API_KEY",
        baseURL: "https://api.openai.com/v1",
        modelID: "gpt-4.1"
    )
)

let messages: [OpenAIMessage] = [
    .system("You are a concise assistant."),
    .user("Introduce Swift in one sentence.")
]

let result = try await sendMessage(
    modelInfo: modelInfo,
    messages: messages
) { update in
    print(update.subText, terminator: "")
}

// The complete response after the request finishes
let answer = result.fullText
```

In the callback, `subText` contains newly received text, while `fullText` contains the accumulated text. Reasoning text is available through `subThinkingText` / `fullThinkingText` when returned by the service and model.

The callback is `@Sendable`. Switch to `MainActor` when updating SwiftUI / UIKit views. To stop a request, cancel the Swift `Task` that started it.

### Getting a Complete Response

```swift
let result = try await sendMessageSync(
    modelInfo: modelInfo,
    messages: [.user("Introduce Swift in one sentence.")]
)
let answer = result.fullText
```

`sendMessageSync` is still an `async throws` API. Call it with `try await`; it returns only when the complete response is ready.

### Continuing a Conversation

The app stores conversation history and passes it with the next request. This example continues the streaming example with another round of plain text conversation:

```swift
var history = messages
history.append(.assistant(
    result.fullText,
    reasoningContent: result.fullThinkingText,
    contentBlocks: result.contentBlocks
))
history.append(.user("Give me a simple code example as well."))

let next = try await sendMessageSync(
    modelInfo: modelInfo,
    messages: history
)
```

Keep `reasoningContent` and `contentBlocks` so the library can carry the protocol context needed to continue the conversation; you do not need to parse their contents. Responses with tool calls also require preserving `toolCalls`. See [Tool Calling](#tool-calling) for the complete example.

### Sending Images

```swift
import Foundation

let imageData = try Data(contentsOf: URL(fileURLWithPath: "/path/to/photo.jpg"))
let result = try await sendMessageSync(
    modelInfo: modelInfo,
    messages: [.user("Describe this image.", imageDatas: imageData)]
)
```

You can also pass images through `images: [Data]`; for videos, use `videoDatas:` or `videos: [Data]`. Actual support depends on the protocol, provider, and model. See [Multimodal Handling](#multimodal-handling).

## Supported Protocols

Select the protocol explicitly through `AIModelInfoValue`. All protocols use the same `sendMessage` / `sendMessageSync` APIs, `OpenAIMessage`, and tool definitions.

| Configuration | Protocol / Default Endpoint | Authentication |
| --- | --- | --- |
| `.completions` | Chat Completions: `https://api.openai.com/v1/chat/completions` | Bearer API key |
| `.responses` | Responses: `https://api.openai.com/v1/responses` | Bearer API key |
| `.codex` | ChatGPT Codex: `https://chatgpt.com/backend-api/codex/responses` | access token + ChatGPT account ID |
| `.anthropic` | Anthropic Messages: `https://api.anthropic.com/v1/messages` | `x-api-key` + `anthropic-version` |

```swift
let completions = AIModelInfoValue.completions(
    .init(token: "YOUR_API_KEY", modelID: "gpt-4.1")
)

let responses = AIModelInfoValue.responses(
    .init(token: "YOUR_API_KEY", modelID: "gpt-4.1")
)

let codex = AIModelInfoValue.codex(
    .init(accessToken: "YOUR_ACCESS_TOKEN", accountID: "YOUR_ACCOUNT_ID")
)

let anthropic = AIModelInfoValue.anthropic(
    .init(token: "YOUR_API_KEY", modelID: "claude-sonnet-4-5")
)
```

Use model IDs offered by your provider. Codex uses the ChatGPT backend; the library accepts existing credentials and does not handle login or token refresh.

### Custom Base URLs

Each configuration accepts a `baseURL`, for example:

```swift
let modelInfo = AIModelInfoValue.completions(
    .init(
        token: "YOUR_API_KEY",
        baseURL: "https://api.deepseek.com",
        modelID: "deepseek-chat"
    )
)
```

Paths are completed according to the selected protocol:

- **Completions / Responses**: A URL with no path gets `/v1/chat/completions` or `/v1/responses`. An existing path gets `/chat/completions` or `/responses` appended. A complete resource path is not appended again.
- **Anthropic**: A URL with no path gets `/v1/messages`. A path ending in `/v1` gets only `/messages` appended. A custom prefix gets `/v1/messages` appended. A path already ending in `/messages` is kept as is.
- **Codex**: Uses the ChatGPT backend shown in the table by default. You can specify a compatible backend with `baseURL`.

**The caller must select the protocol explicitly.** Setting a provider URL or changing the model ID does not switch protocols automatically. A service that advertises OpenAI compatibility does not necessarily support Responses or Anthropic Messages.

## Tool Calling

Tool calling has three steps: **provide tool definitions → execute the tools requested by the model in your app → return the results and continue the request**. Neither the library nor the Swift macros execute your business logic automatically.

The examples below use an addition tool. Choose either the standard approach or the macro approach; both define the same `AdditionArgs` and `tools`, followed by the shared execution flow.

### Standard Approach: JSON Schema

```swift
import Foundation
import SwiftOpenAI

struct AdditionArgs: Codable, Sendable {
    let a: Double
    let b: Double
}

let additionTool = ChatQuery.ChatCompletionToolParam(
    type: "function",
    function: .init(
        name: "add_numbers",
        description: "Calculate the sum of two numbers.",
        strict: true,
        parameters: [
            "type": .string("object"),
            "properties": .object([
                "a": .object(["type": .string("number")]),
                "b": .object(["type": .string("number")])
            ]),
            "required": .array([.string("a"), .string("b")]),
            "additionalProperties": .bool(false)
        ]
    )
)

let tools: [any OpenAIToolConvertible] = [additionTool]
```

### Swift Macro Approach: Generate Definitions from Types

```swift
import Foundation
import SwiftOpenAI

@SYToolArgs
struct AdditionArgs: Codable, Sendable {
    /// The first number to add.
    let a: Double
    /// The second number to add.
    let b: Double
}

@SYTool
struct AdditionTool {
    let name = "add_numbers"
    let description = "Calculate the sum of two numbers."
    let parameters = AdditionArgs.self
}

let tools: [any OpenAIToolConvertible] = [AdditionTool()]
```

- `@SYToolArgs` generates a JSON Schema from parameter types and documentation comments.
- `@SYTool` generates a tool definition from `name`, `description`, and `parameters = ArgumentType.self`, with `strict` enabled by default.
- Both approaches pass tools through `OpenAIToolConvertible` and can be mixed. Macros only generate definitions; the app still decodes arguments and executes the tools.

### Executing Tools and Returning Results

Place this after either tool definition approach and reuse the earlier `modelInfo`. This example waits for each request to finish before executing tools, so streamed arguments are complete before use.

```swift
enum ToolCallError: Error {
    case incompleteCall
    case unknownTool(String)
}

var history: [OpenAIMessage] = [
    .user("Use the addition tool to calculate 12.5 + 7.5.")
]

while true {
    let result = try await sendMessageSync(
        modelInfo: modelInfo,
        messages: history,
        tools: tools
    )

    // Convert complete tool calls to the history message type without dropping any calls.
    let toolCalls: [AssistantMessageParam.ToolCallParam] = try result.allToolCalls.map { call in
        guard let id = call.id,
              let function = call.function,
              let name = function.name,
              let arguments = function.arguments else {
            throw ToolCallError.incompleteCall
        }
        return .init(id: id, function: .init(name: name, arguments: arguments))
    }

    history.append(.assistant(
        result.fullText,
        toolCalls: toolCalls,
        reasoningContent: result.fullThinkingText,
        contentBlocks: result.contentBlocks
    ))

    if toolCalls.isEmpty {
        print(result.fullText)
        break
    }

    for call in toolCalls {
        switch call.function.name {
        case "add_numbers":
            let args = try JSONDecoder().decode(
                AdditionArgs.self,
                from: Data(call.function.arguments.utf8)
            )
            let output = String(args.a + args.b)
            history.append(.tool(output, toolCallId: call.id))
        default:
            throw ToolCallError.unknownTool(call.function.name)
        }
    }
}
```

For each tool-calling round, first save the complete assistant message, then append a `.tool` result with the matching `toolCallId` for every call, and send another request with the same tool definitions. The model may request multiple rounds of tool calls. Returning only tool results or preserving only `fullText` is not sufficient.

Set `toolChoice` to `.auto`, `.required`, or `.function("add_numbers")`. To disable tools, use `ChatQuery.ChatCompletionFunctionCallOptionParam.none`. Setting `parallelToolCalls: true` allows the model to request multiple tools at once; the app controls their execution order and concurrency.

## Platform Differences

Minimum Apple platform versions: macOS 14, iOS 17, Mac Catalyst 17, and visionOS 1.

| Platform | Conversation Requests and Streaming |
| --- | --- |
| Apple platforms, Linux, and other non-Windows platforms | Use AsyncHTTPClient / SwiftNIO to receive streaming responses. |
| Windows | Uses a URLSession delegate to receive data incrementally, with true streaming callbacks. |
| Files uploads / deletions on all platforms | Use URLSession. |

The public API is the same across platforms, so there is no need to switch conversation APIs. Linux / Windows builds also depend on platform support in the Swift toolchain and dependencies you use.

## Protocol Compatibility

### Completions Provider Adaptations

The Completions path identifies OpenAI, Moonshot / Kimi, MiniMax, Zhipu, Volcengine Ark, Alibaba Cloud DashScope, DeepSeek, and TokenDance by the `baseURL` domain and handles common differences between these services:

- Maps the unified `thinkLevel` to provider-supported reasoning parameters and reads reasoning output from fields such as `reasoning` / `reasoning_content`.
- Adjusts the role of `reminder` messages and accommodates differences in usage reporting and streamed tool arguments. MiniMax's cumulative streaming output is converted to deltas.
- Downgrades `responseFormat` according to provider capabilities: from `json_schema` to `json_object`, or removes it when unsupported.
- Removes `strict` for services that do not support strict tool schemas. For DeepSeek, it is kept only when a `/beta` URL is explicitly configured; the library does not switch to the beta endpoint automatically.

Unknown domains and proxy URLs use generic compatibility rules. The library does not infer the underlying provider from the model ID. These adaptations do not guarantee identical capabilities across all OpenAI-compatible services.

### Parameter Handling Across Protocols

| Protocol | Behavior Callers Should Be Aware Of |
| --- | --- |
| Responses / Codex | Do not support `prediction`, `user`, or `n != 1`; passing them results in an unsupported-parameter-combination error. |
| Codex | Automatically removes the request fields corresponding to `temperature`, `topP`, and `maxCompletionTokens`. |
| Anthropic | Does not support `prediction`, `user`, `n != 1`, frequency / presence penalties, or `responseFormat`. When reasoning is enabled, required tool use or a specific function choice is changed to `auto`. |

Use the unified `thinkLevel` parameter to choose reasoning intensity, such as `.high`. To disable reasoning, pass `ThinkLevel.none` explicitly; Swift interprets `.none` alone as the optional value `nil`. Supported levels depend on the service and model.

Add provider-specific request parameters through `extraBody` and custom request headers through `extraHeaders`. The Codex field-removal rules above also apply to `extraBody`.

### Multimodal Handling

- The library determines image / video support from the protocol and model ID; unknown models are treated as unsupported by default. Unsupported media is replaced with a text notice, while the rest of the text is preserved.
- DeepSeek data URL images are uploaded to Files automatically. Upload bindings are preserved through `contentBlocks` for reuse in later conversation turns. This does not mean every DeepSeek model supports vision.
- When using multimodal input or images in tool results, also confirm that the server and model support that input format.

## License

[MIT License](LICENSE)
