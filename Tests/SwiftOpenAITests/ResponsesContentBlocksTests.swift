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
        let blocks = try XCTUnwrap(mergeContentBlocksForResult(
            anthropic: nil,
            fileBindings: ["image": FileBinding(fileId: "file-1")],
            responses: state.outputItems
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
        XCTAssertEqual(assistant.contentBlocks?.responses, expected)
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
        let blocks = MessageContentBlocks(
            anthropic: [["type": .string("thinking"), "signature": .string("signature")]],
            fileBindings: ["image": FileBinding(fileId: "file-1")],
            responses: output
        )
        let merged = blocks.merging(MessageContentBlocks(fileBindings: ["image": FileBinding(fileId: "file-2")]))
        XCTAssertEqual(merged.responses, output)
        XCTAssertEqual(merged.anthropic, blocks.anthropic)
        XCTAssertEqual(merged.fileBindings?["image"]?.fileId, "file-2")
        XCTAssertEqual(blocks.merging(MessageContentBlocks(responses: [])).responses, [])
    }
}
