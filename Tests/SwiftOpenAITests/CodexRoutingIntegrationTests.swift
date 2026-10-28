#if canImport(Network) && canImport(SwiftData)
import Foundation
import Network
import SwiftData
import XCTest
@testable import SwiftOpenAI

@Model
private final class RoutingMessageRow {
    var id: UUID = UUID()
    var payload: Data
    @Transient var message: OpenAIMessage?

    init(_ message: OpenAIMessage) throws {
        self.payload = try JSONEncoder().encode(message)
        self.message = message
    }
}

@Model
private final class RoutingMessageHistory {
    @Relationship(deleteRule: .cascade) var items: [RoutingMessageRow] = []
    var order: [UUID] = []

    init() {}
}

final class CodexRoutingIntegrationTests: XCTestCase {
    @MainActor
    func testHTTPResultSurvivesSwiftDataAndRoutesNextToolRequestToSameTurn() async throws {
        let output: [[String: Any]] = [[
            "type": "function_call", "id": "fc_1", "call_id": "call_1",
            "name": "message_user", "arguments": #"{"content":"你好","name":"打招呼"}"#,
            "status": "completed"
        ]]
        let sse = try TestFixtures.makeSSELine([
            "type": "response.completed", "response": ["id": "resp_1", "model": "gpt-6.1-sol", "output": output]
        ]) + "\n\n"
        let server = try RoutingHTTPServer(sse: sse)
        let port = try await server.start()
        defer { server.stop() }
        let initial: [OpenAIMessage] = [.system("stable rules"), .user("你好")]
        let first = try prepare(port: port, messages: initial)
        let result = try await executeResponsesStream(preparedRequest: first) { _ in }
        let blocks = try XCTUnwrap(result.contentBlocks)
        XCTAssertEqual(blocks.codexSessionID, first.urlRequest.value(forHTTPHeaderField: "session-id"))
        XCTAssertEqual(blocks.codexTurnState, "server-issued-turn-token")
        XCTAssertEqual(blocks.codexTurnScope, first.codexTurnScope)
        let reply = OpenAIMessage.assistant(
            result.fullText,
            toolCalls: result.allToolCalls.map {
                .init(id: $0.id ?? "", function: .init(name: $0.function?.name ?? "", arguments: $0.function?.arguments ?? ""))
            },
            reasoningContent: result.fullThinkingText,
            contentBlocks: result.contentBlocks
        )

        // The application stores C messages as JSON Data rows, with transient decoded caches.
        let schema = Schema([RoutingMessageRow.self, RoutingMessageHistory.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
        let writer = ModelContext(container)
        let history = RoutingMessageHistory()
        writer.insert(history)
        for message in initial + [reply, .tool("已提交", toolCallId: "call_1"), .reminder("已批准")] {
            let row = try RoutingMessageRow(message)
            writer.insert(row)
            history.items.append(row)
            history.order.append(row.id)
        }
        try writer.save()
        let reader = ModelContext(container)
        let loaded = try XCTUnwrap(reader.fetch(FetchDescriptor<RoutingMessageHistory>()).first)
        var restored: [OpenAIMessage] = []
        for id in loaded.order {
            let row = try XCTUnwrap(loaded.items.first { $0.id == id })
            row.message = nil
            restored.append(try JSONDecoder().decode(OpenAIMessage.self, from: row.payload))
        }
        let second = try prepare(port: port, messages: restored)
        _ = try await executeResponsesStream(preparedRequest: second) { _ in }
        let requests = server.requests
        XCTAssertEqual(requests.count, 2)
        guard requests.count == 2 else { return }
        XCTAssertEqual(requests[0]["session-id"], requests[1]["session-id"])
        XCTAssertNil(requests[0]["x-codex-turn-state"])
        XCTAssertEqual(requests[1]["x-codex-turn-state"], "server-issued-turn-token")
        XCTAssertEqual(first.codexTurnScope, second.codexTurnScope)
    }

    private func prepare(port: UInt16, messages: [OpenAIMessage]) throws -> PreparedResponsesRequest {
        let baseURL = "http://127.0.0.1:\(port)/backend-api/codex"
        return try makeResponsesURLRequest(
            config: .init(
                modelID: "gpt-6.1-sol", baseURL: try APIBaseURL.parse(baseURL),
                resolvedBasePath: "/backend-api/codex", providerName: "openai-codex",
                defaultHeaders: ["Authorization": "Bearer test-token", "ChatGPT-Account-ID": "test-account"]
            ),
            messages: messages, frequencyPenalty: nil, maxCompletionTokens: nil, parallelToolCalls: true,
            presencePenalty: nil, responseFormat: nil, stop: nil, temperature: nil, toolChoice: nil,
            tools: nil, topP: nil, thinkLevel: ThinkLevel.none, extraBody: nil, extraHeaders: nil
        )
    }
}

private final class RoutingHTTPServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "swiftopenai.routing-test")
    private let lock = NSLock()
    private let response: Data
    private var ready: CheckedContinuation<UInt16, Error>?
    private var capturedRequests: [[String: String]] = []

    var requests: [[String: String]] { lock.withLock { capturedRequests } }

    init(sse: String) throws {
        listener = try NWListener(using: .tcp, on: .any)
        let headers = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: \(sse.utf8.count)\r\nX-Codex-Turn-State: server-issued-turn-token\r\nConnection: close\r\n\r\n"
        response = Data((headers + sse).utf8)
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock { ready = continuation }
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    if let port = self.listener.port {
                        self.finishStart(.success(port.rawValue))
                    }
                case .failed(let error): self.finishStart(.failure(error))
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { connection.cancel(); return }
                connection.start(queue: self.queue)
                self.receive(connection)
            }
            listener.start(queue: queue)
        }
    }

    func stop() { listener.cancel() }

    private func finishStart(_ result: Result<UInt16, Error>) {
        let continuation = lock.withLock { let value = ready; ready = nil; return value }
        continuation?.resume(with: result)
    }

    private func receive(_ connection: NWConnection, buffer: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            var bytes = buffer
            if let data { bytes.append(data) }
            if let separator = bytes.range(of: Data("\r\n\r\n".utf8)) {
                let lines = String(decoding: bytes[..<separator.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
                var headers: [String: String] = [:]
                for line in lines.dropFirst() {
                    let pair = line.split(separator: ":", maxSplits: 1)
                    if pair.count == 2 {
                        headers[String(pair[0]).lowercased()] = pair[1].trimmingCharacters(in: .whitespaces)
                    }
                }
                let length = Int(headers["content-length"] ?? "0") ?? 0
                if bytes.count >= separator.upperBound + length {
                    self.lock.withLock { self.capturedRequests.append(headers) }
                    connection.send(content: self.response, completion: .contentProcessed { _ in connection.cancel() })
                    return
                }
            }
            if complete || error != nil { connection.cancel() }
            else { self.receive(connection, buffer: bytes) }
        }
    }
}
#endif
