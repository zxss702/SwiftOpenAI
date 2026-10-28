import XCTest
@testable import SwiftOpenAI

final class ResponsesContentBlocksTests: XCTestCase {

    func testCompletedOutputSurvivesPersistenceAndReplayWithoutDuplicateTextOrCalls() async throws {
        let output: [[String: Any]] = [
            [
                "id": "rs_1",
                "type": "reasoning",
                "summary": [["type": "summary_text", "text": "summary"]],
                "encrypted_content": "encrypted-state"
            ],
            [
                "id": "msg_1",
                "type": "message",
                "role": "assistant",
                "status": "completed",
                "phase": "commentary",
                "content": [["type": "output_text", "text": "checking", "annotations": []]]
            ],
            [
                "id": "rs_2",
                "type": "reasoning",
                "summary": [],
                "encrypted_content": "second-state"
            ],
            [
                "id": "fc_1",
                "type": "function_call",
                "call_id": "call_1",
                "name": "lookup",
                "arguments": #"{"enabled":false}"#,
                "status": "completed"
            ]
        ]
        let helper = OpenAISendMessageValueHelper()
        var state = ResponsesStreamState()
        var metadata = ChatResponseMetadata(
            providerName: "openai-codex",
            requestID: nil,
            resolvedModel: "gpt-6.1-sol",
            resolvedBasePath: "/backend-api/codex"
        )
        let events = try [
            TestFixtures.makeSSELine([
                "type": "response.output_item.done",
                "output_index": 0,
                "item": ["id": "rs_1", "type": "reasoning", "summary": []]
            ]),
            TestFixtures.makeSSELine([
                "type": "response.completed",
                "response": ["id": "resp_1", "output": output]
            ])
        ].joined(separator: "\n") + "\n"
        try await processResponsesSSEBytes(
            Data(events.utf8),
            actorHelper: helper,
            state: &state,
            metadata: &metadata,
            finalize: true
        )

        let expected = try JSONDecoder().decode(
            [[String: AnyCodableValue]].self,
            from: JSONSerialization.data(withJSONObject: output)
        )
        XCTAssertEqual(state.outputItems, expected)
        let context = try XCTUnwrap(ResponsesMessageContext(outputItems: state.outputItems))
        let blocks = try XCTUnwrap(mergeContentBlocksForResult(
            anthropic: nil,
            fileBindings: ["image": FileBinding(fileId: "file-1")],
            responses: context
        ))
        let message = OpenAIMessage.assistant(
            "checking",
            toolCalls: [.init(id: "call_1", function: .init(name: "lookup", arguments: #"{"enabled":false}"#))],
            reasoningContent: "summary",
            contentBlocks: blocks
        )
        let persisted = try JSONEncoder().encode(message)
        let restored = try JSONDecoder().decode(OpenAIMessage.self, from: persisted)
        guard case .assistant(let assistant) = restored else {
            return XCTFail("Expected assistant history")
        }
        XCTAssertEqual(assistant.contentBlocks?.responses, context)
        XCTAssertNil(context.items[1].content?.first?.metadata["text"])
        XCTAssertNil(context.items[3].metadata["call_id"])
        XCTAssertNil(context.items[3].metadata["name"])
        XCTAssertNil(context.items[3].metadata["arguments"])
        XCTAssertNil(context.items[0].summary?.first?.metadata["text"])
        XCTAssertEqual(assistant.contentBlocks?.fileBindings?["image"]?.fileId, "file-1")

        for wireAPI in [AIModelWireAPI.responses, .codexResponses] {
            let input = try encodeResponsesInputItems([
                .user("inspect"),
                restored,
                .tool("found", toolCallId: "call_1"),
                .user("continue")
            ], wireAPI: wireAPI)
            let replayed = try JSONDecoder().decode(
                [[String: AnyCodableValue]].self,
                from: JSONSerialization.data(withJSONObject: Array(input.dropFirst().prefix(output.count)))
            )
            XCTAssertEqual(replayed, expected)
            XCTAssertEqual(input.count, output.count + 3)
            XCTAssertEqual(input[output.count + 1]["type"] as? String, "function_call_output")
            XCTAssertEqual(input[output.count + 1]["call_id"] as? String, "call_1")
        }
    }

    func testItemDoneOutputIsOrderedAndNotDuplicatedWhenCompletedOmitsOutput() async throws {
        let helper = OpenAISendMessageValueHelper()
        var state = ResponsesStreamState()
        var metadata = ChatResponseMetadata(
            providerName: "openai-responses",
            requestID: nil,
            resolvedModel: "gpt-6.1-sol",
            resolvedBasePath: "/v1"
        )
        let reasoning: [String: Any] = [
            "id": "rs_1", "type": "reasoning", "summary": [], "encrypted_content": "state"
        ]
        let message: [String: Any] = [
            "id": "msg_1", "type": "message", "role": "assistant", "phase": "final_answer",
            "content": [["type": "output_text", "text": "done", "annotations": []]]
        ]
        let events = try [
            TestFixtures.makeSSELine(["type": "response.output_item.done", "output_index": 1, "item": message]),
            TestFixtures.makeSSELine(["type": "response.output_item.done", "output_index": 0, "item": reasoning]),
            TestFixtures.makeSSELine(["type": "response.output_item.done", "output_index": 1, "item": message]),
            TestFixtures.makeSSELine(["type": "response.completed", "response": ["id": "resp_1"]])
        ].joined(separator: "\n") + "\n"
        try await processResponsesSSEBytes(
            Data(events.utf8),
            actorHelper: helper,
            state: &state,
            metadata: &metadata,
            finalize: true
        )
        let expected = try JSONDecoder().decode(
            [[String: AnyCodableValue]].self,
            from: JSONSerialization.data(withJSONObject: [reasoning, message])
        )
        XCTAssertEqual(state.outputItems, expected)
    }

    func testLegacyHistoryAndContentBlockMergingRemainCompatible() throws {
        let legacy = Data(#"{"role":"assistant","content":"legacy"}"#.utf8)
        let restored = try JSONDecoder().decode(OpenAIMessage.self, from: legacy)
        let input = try encodeResponsesInputItems([restored])
        XCTAssertEqual(input.count, 1)
        XCTAssertEqual((input[0]["content"] as? [[String: Any]])?.first?["text"] as? String, "legacy")

        let output: [[String: AnyCodableValue]] = [[
            "type": .string("reasoning"), "encrypted_content": .string("state"), "summary": .array([])
        ]]
        let context = try XCTUnwrap(ResponsesMessageContext(outputItems: output))
        let blocks = MessageContentBlocks(
            anthropic: [["type": .string("thinking"), "signature": .string("signature")]],
            fileBindings: ["image": FileBinding(fileId: "file-1")],
            responses: context
        )
        let merged = blocks.merging(MessageContentBlocks(fileBindings: ["image": FileBinding(fileId: "file-2")]))
        XCTAssertEqual(merged.responses, context)
        XCTAssertEqual(merged.anthropic, blocks.anthropic)
        XCTAssertEqual(merged.fileBindings?["image"]?.fileId, "file-2")
        var cleared = merged
        cleared.responses = nil
        XCTAssertNil(cleared.responses)
    }

    func testEditedContentReasoningAndToolCallsAlwaysUseCurrentCFields() throws {
        let output: [[String: AnyCodableValue]] = [
            ["type": .string("reasoning"), "encrypted_content": .string("old-state"),
             "summary": .array([.object(["type": .string("summary_text"), "text": .string("old-thinking")])])],
            ["type": .string("message"), "id": .string("msg_old"), "role": .string("assistant"),
             "phase": .string("commentary"),
             "content": .array([.object(["type": .string("output_text"), "text": .string("old-text")])])],
            ["type": .string("function_call"), "id": .string("fc_old"), "call_id": .string("call_old"),
             "name": .string("lookup"), "arguments": .string("{}")]
        ]
        let context = try XCTUnwrap(ResponsesMessageContext(outputItems: output))
        let blocks = MessageContentBlocks(responses: context)
        let original = AssistantMessageParam.ToolCallParam(id: "call_old", function: .init(name: "lookup", arguments: "{}"))
        let edits = [
            AssistantMessageParam(content: "edited", toolCalls: [original], reasoningContent: "old-thinking", contentBlocks: blocks),
            AssistantMessageParam(content: "", toolCalls: [original], reasoningContent: "old-thinking", contentBlocks: blocks),
            AssistantMessageParam(content: "old-text", toolCalls: [original], reasoningContent: "edited-thinking", contentBlocks: blocks),
            AssistantMessageParam(content: "old-text", toolCalls: [], reasoningContent: "old-thinking", contentBlocks: blocks),
            AssistantMessageParam(content: "old-text", toolCalls: [
                .init(id: "call_old", function: .init(name: "lookup", arguments: #"{"edited":true}"#))
            ], reasoningContent: "old-thinking", contentBlocks: blocks),
            AssistantMessageParam(content: "old-text", toolCalls: [
                .init(id: "call_old", function: .init(name: "other", arguments: "{}"))
            ], reasoningContent: "old-thinking", contentBlocks: blocks),
            AssistantMessageParam(content: "old-text", toolCalls: [
                .init(id: "call_new", function: .init(name: "lookup", arguments: "{}"))
            ], reasoningContent: "old-thinking", contentBlocks: blocks),
            AssistantMessageParam(content: "old-text", toolCalls: [
                .init(id: "call_new", function: .init(name: "other", arguments: #"{"edited":true}"#))
            ], reasoningContent: "old-thinking", contentBlocks: blocks),
            AssistantMessageParam(content: "old-text", toolCalls: [original, original], reasoningContent: "old-thinking", contentBlocks: blocks)
        ]
        for edited in edits {
            // A C message without supplemental metadata is the expected mapping after an edit.
            let expected = AssistantMessageParam(
                content: edited.content, toolCalls: edited.toolCalls, reasoningContent: edited.reasoningContent
            )
            let withContext = try encodeResponsesInputItems([.assistant(edited)])
            let withoutContext = try encodeResponsesInputItems([.assistant(expected)])
            let actualData = try JSONSerialization.data(withJSONObject: withContext)
            let expectedData = try JSONSerialization.data(withJSONObject: withoutContext)
            let actualItems = try JSONDecoder().decode([[String: AnyCodableValue]].self, from: actualData)
            let expectedItems = try JSONDecoder().decode([[String: AnyCodableValue]].self, from: expectedData)
            XCTAssertEqual(actualItems, expectedItems)
            XCTAssertFalse(withContext.contains { $0["encrypted_content"] != nil || $0["phase"] != nil })
        }
    }

    func testLegacyRawBlocksMigrateToMetadataAndHonorEditedCText() throws {
        let data = Data(#"{"responses":[{"type":"message","role":"assistant","phase":"final_answer","content":[{"type":"output_text","text":"old"}]}]}"#.utf8)
        let blocks = try JSONDecoder().decode(MessageContentBlocks.self, from: data)
        let context = try XCTUnwrap(blocks.responses)
        XCTAssertNil(context.items.first?.content?.first?.metadata["text"])
        let edited = AssistantMessageParam(content: "new", contentBlocks: blocks)
        let input = try encodeResponsesInputItems([.assistant(edited)])
        XCTAssertEqual((input.first?["content"] as? [[String: Any]])?.first?["text"] as? String, "new")
        XCTAssertNil(input.first?["phase"])
    }

    func testUneditedUnicodeTextPartsUseRangesIntoSingleCContent() throws {
        let output: [[String: AnyCodableValue]] = [[
            "type": .string("message"), "role": .string("assistant"), "phase": .string("final_answer"),
            "content": .array([
                .object(["type": .string("output_text"), "text": .string("你好👩‍💻e")]),
                .object(["type": .string("output_text"), "text": .string("\u{301}继续")])
            ])
        ]]
        let context = try XCTUnwrap(ResponsesMessageContext(outputItems: output))
        let message = AssistantMessageParam(content: "你好👩‍💻e\u{301}继续", contentBlocks: MessageContentBlocks(responses: context))
        let input = try encodeResponsesInputItems([.assistant(message)])
        let parts = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0]["text"] as? String, "你好👩‍💻e")
        XCTAssertEqual(parts[1]["text"] as? String, "\u{301}继续")
        XCTAssertEqual(input.first?["phase"] as? String, "final_answer")
    }

    func testFullReasoningTextMapsToCReasoningWhileProviderSummaryRemainsSupplemental() throws {
        let output: [[String: AnyCodableValue]] = [[
            "type": .string("reasoning"), "encrypted_content": .string("state"),
            "content": .array([.object(["type": .string("reasoning_text"), "text": .string("full-thinking")])]),
            "summary": .array([.object(["type": .string("summary_text"), "text": .string("short-summary")])])
        ]]
        let context = try XCTUnwrap(ResponsesMessageContext(outputItems: output))
        XCTAssertNil(context.items.first?.content?.first?.metadata["text"])
        let message = AssistantMessageParam(reasoningContent: "full-thinking", contentBlocks: MessageContentBlocks(responses: context))
        let input = try encodeResponsesInputItems([.assistant(message)])
        let restored = try JSONDecoder().decode(
            [[String: AnyCodableValue]].self,
            from: JSONSerialization.data(withJSONObject: input)
        )
        XCTAssertEqual(restored, output)
    }
}
