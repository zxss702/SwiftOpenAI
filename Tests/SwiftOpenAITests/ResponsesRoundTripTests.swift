import XCTest
@testable import SwiftOpenAI

final class ResponsesRoundTripTests: XCTestCase {
    func testCInputMapsToExpectedRForResponsesAndCodex() throws {
        let messages: [OpenAIMessage] = [
            .system("规则"), .user("你好👩‍💻"), .reminder("提醒"),
            .assistant("查一下", toolCalls: [
                .init(id: "call_1", function: .init(name: "lookup", arguments: #"{"city":"上海"}"#))
            ], reasoningContent: "plain summary is not an encrypted reasoning item"),
            .tool("结果", toolCallId: "call_1")
        ]
        for wireAPI in [AIModelWireAPI.responses, .codexResponses] {
            let instructionRole = wireAPI == .codexResponses ? "developer" : "system"
            let expected: [[String: Any]] = [
                ["type": "message", "role": instructionRole, "content": [["type": "input_text", "text": "规则"]]],
                ["type": "message", "role": "user", "content": [["type": "input_text", "text": "你好👩‍💻"]]],
                ["type": "message", "role": instructionRole, "content": [["type": "input_text", "text": "提醒"]]],
                ["type": "message", "role": "assistant", "content": [["type": "output_text", "text": "查一下"]]],
                ["type": "function_call", "call_id": "call_1", "name": "lookup", "arguments": #"{"city":"上海"}"#],
                ["type": "function_call_output", "call_id": "call_1", "output": "结果"]
            ]
            let actual = try encodeResponsesInputItems(messages, wireAPI: wireAPI)
            XCTAssertEqual(try canonical(actual), try canonical(expected), "C→R: \(wireAPI)")
        }
    }

    func testRToCToRThroughRealSSEAndPersistence() async throws {
        try await assertRoundTrips(mode: .deltas)
    }

    func testRToCToRWithOnlyItemDoneEvents() async throws {
        try await assertRoundTrips(mode: .items)
    }

    func testRToCToRWithOnlyCompletedOutput() async throws {
        try await assertRoundTrips(mode: .completed)
    }

    private enum Mode: String {
        case deltas, items, completed
    }

    private struct Fixture {
        let name: String
        let output: [[String: Any]]
        let text: String
        let thinking: String
        let calls: [AssistantMessageParam.ToolCallParam]
    }

    private func fixtures() -> [Fixture] {
        func message(_ id: String, _ texts: [String], phase: Any = "final_answer") -> [String: Any] {
            ["id": id, "type": "message", "role": "assistant", "status": "completed", "phase": phase,
             "content": texts.map { ["type": "output_text", "text": $0, "annotations": []] as [String: Any] }]
        }
        func reasoning(_ id: String, _ summary: String, full: String? = nil) -> [String: Any] {
            var item: [String: Any] = [
                "id": id, "type": "reasoning", "encrypted_content": "encrypted-\(id)",
                "summary": summary.isEmpty ? [] : [["type": "summary_text", "text": summary]]
            ]
            if let full {
                item["content"] = [["type": "reasoning_text", "text": full]]
            }
            return item
        }
        let call1: [String: Any] = [
            "id": "fc_1", "type": "function_call", "status": "completed", "call_id": "call_1",
            "name": "lookup", "arguments": #"{ "enabled": false, "city": "上海" }"#
        ]
        let call2: [String: Any] = [
            "id": "fc_2", "type": "function_call", "status": "completed", "call_id": "call_2",
            "name": "count", "arguments": #"{"count":2}"#
        ]
        let c1 = AssistantMessageParam.ToolCallParam(
            id: "call_1", function: .init(name: "lookup", arguments: #"{ "enabled": false, "city": "上海" }"#)
        )
        let c2 = AssistantMessageParam.ToolCallParam(id: "call_2", function: .init(name: "count", arguments: #"{"count":2}"#))
        return [
            Fixture(name: "plain", output: [message("msg_1", ["hello"])], text: "hello", thinking: "", calls: []),
            Fixture(name: "encrypted reasoning", output: [reasoning("rs_1", "summary"), message("msg_1", ["answer"])], text: "answer", thinking: "summary", calls: []),
            Fixture(name: "unicode parts", output: [message("msg_1", ["你好👩‍💻e", "\u{301}继续"])], text: "你好👩‍💻e\u{301}继续", thinking: "", calls: []),
            Fixture(name: "parallel calls", output: [reasoning("rs_1", ""), call1, call2], text: "", thinking: "", calls: [c1, c2]),
            Fixture(name: "interleaved", output: [
                reasoning("rs_1", "first"), message("msg_1", ["checking"], phase: "commentary"),
                reasoning("rs_2", "second"), call1
            ], text: "checking", thinking: "firstsecond", calls: [c1]),
            Fixture(name: "multiple messages", output: [
                message("msg_1", ["first"], phase: "commentary"), message("msg_2", ["second"])
            ], text: "firstsecond", thinking: "", calls: []),
            Fixture(name: "full reasoning plus summary", output: [
                reasoning("rs_1", "short summary", full: "full reasoning"), message("msg_1", ["answer"])
            ], text: "answer", thinking: "full reasoning", calls: []),
            Fixture(name: "empty text and null phase", output: [message("msg_1", [""], phase: NSNull())], text: "", thinking: "", calls: [])
        ]
    }

    private func assertRoundTrips(mode: Mode, file: StaticString = #filePath, line: UInt = #line) async throws {
        for fixture in fixtures() {
            let helper = OpenAISendMessageValueHelper()
            var state = ResponsesStreamState()
            var metadata = ChatResponseMetadata(
                providerName: "openai-codex", requestID: nil,
                resolvedModel: "gpt-6.1-sol", resolvedBasePath: "/backend-api/codex"
            )
            var events: [[String: Any]] = []
            if mode != .completed {
                for (index, item) in fixture.output.enumerated() {
                    events.append(["type": "response.output_item.added", "output_index": index, "item": item])
                    if mode == .deltas {
                        for part in item["summary"] as? [[String: Any]] ?? [] {
                            events.append(["type": "response.reasoning_summary_text.delta", "delta": part["text"] ?? ""])
                        }
                        for part in item["content"] as? [[String: Any]] ?? [] {
                            let type = item["type"] as? String == "reasoning"
                                ? "response.reasoning_text.delta" : "response.output_text.delta"
                            events.append(["type": type, "delta": part["text"] ?? ""])
                        }
                    }
                    events.append(["type": "response.output_item.done", "output_index": index, "item": item])
                }
            }
            var response: [String: Any] = ["id": "resp_1"]
            if mode != .items { response["output"] = fixture.output }
            events.append(["type": "response.completed", "response": response])
            let sse = try events.map(TestFixtures.makeSSELine).joined(separator: "\n") + "\n"
            // Split in the middle of arbitrary JSON/UTF-8 bytes, as a real stream may do.
            let bytes = Data(sse.utf8)
            let midpoint = bytes.count / 2
            try await processResponsesSSEBytes(
                bytes.prefix(midpoint), actorHelper: helper, state: &state, metadata: &metadata
            )
            try await processResponsesSSEBytes(
                bytes.suffix(from: midpoint), actorHelper: helper, state: &state, metadata: &metadata, finalize: true
            )

            // Build C from the actual parser output, never from the expected fixture values.
            let result = await helper.peekResult()
            let label = "\(mode.rawValue): \(fixture.name)"
            XCTAssertEqual(result.fullText, fixture.text, label, file: file, line: line)
            XCTAssertEqual(result.fullThinkingText, fixture.thinking, label, file: file, line: line)
            let calls = result.allToolCalls.map {
                AssistantMessageParam.ToolCallParam(
                    id: $0.id ?? "", function: .init(name: $0.function?.name ?? "", arguments: $0.function?.arguments ?? "")
                )
            }
            XCTAssertEqual(try canonicalCalls(calls), try canonicalCalls(fixture.calls), label, file: file, line: line)
            let c = OpenAIMessage.assistant(
                result.fullText, toolCalls: calls, reasoningContent: result.fullThinkingText,
                contentBlocks: mergeContentBlocksForResult(
                    anthropic: nil, fileBindings: [:], responses: ResponsesMessageContext(outputItems: state.outputItems)
                )
            )
            let persisted = try JSONEncoder().encode(c)
            let restored = try JSONDecoder().decode(OpenAIMessage.self, from: persisted)
            for wireAPI in [AIModelWireAPI.responses, .codexResponses] {
                let r = try encodeResponsesInputItems([restored], wireAPI: wireAPI)
                XCTAssertEqual(try canonical(r), try canonical(fixture.output), "R→C→R \(wireAPI), \(label)", file: file, line: line)
            }
        }
    }

    private func canonical(_ items: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: items, options: [.sortedKeys])
    }

    private func canonicalCalls(_ calls: [AssistantMessageParam.ToolCallParam]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(calls)
    }
}
