import XCTest
@testable import SwiftOpenAI

final class SSEByteBufferTests: XCTestCase {
    func testDrainLinesDecodesCompleteLine() {
        var buffer = SSEByteBuffer()
        buffer.append(Data("data: hello\n".utf8))

        let lines = buffer.drainLines()
        XCTAssertEqual(lines, ["data: hello"])
    }

    func testDrainLinesWaitsForNewlineBeforeDecoding() {
        var buffer = SSEByteBuffer()
        let fullLine = "data: {\"choices\":[{\"delta\":{\"content\":\"你好\"}}]}\n"
        let fullData = Data(fullLine.utf8)

        guard let splitIndex = fullData.firstIndex(of: 0xBD) else {
            XCTFail("Expected multi-byte UTF-8 sequence")
            return
        }

        buffer.append(fullData[..<splitIndex])
        XCTAssertTrue(buffer.drainLines().isEmpty)

        buffer.append(fullData[splitIndex...])
        let lines = buffer.drainLines()
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("你好"))
    }

    func testDrainLinesHandlesCRLF() {
        var buffer = SSEByteBuffer()
        buffer.append(Data("data: hello\r\n".utf8))

        let lines = buffer.drainLines()
        XCTAssertEqual(lines, ["data: hello"])
    }

    func testDrainLinesFinalizeFlushesRemainingBytes() {
        var buffer = SSEByteBuffer()
        buffer.append(Data("data: tail".utf8))

        let lines = buffer.drainLines(finalize: true)
        XCTAssertEqual(lines, ["data: tail"])
    }

    func testMultipleLinesInSingleAppend() {
        var buffer = SSEByteBuffer()
        buffer.append(Data("data: one\n\ndata: two\n".utf8))

        let lines = buffer.drainLines()
        XCTAssertEqual(lines, ["data: one", "data: two"])
    }
}
