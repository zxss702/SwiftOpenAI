import Foundation

/// SSE 原始字节缓冲，在完整行（`\n`）边界才做 UTF-8 解码，避免 TCP chunk 截断多字节字符。
struct SSEByteBuffer {
    private var pendingBytes = Data()

    mutating func append(_ bytes: Data) {
        guard !bytes.isEmpty else { return }
        pendingBytes.append(bytes)
    }

    mutating func drainLines(finalize: Bool = false) -> [String] {
        var lines: [String] = []

        while let newlineIndex = pendingBytes.firstIndex(of: 0x0A) {
            let lineBytes = pendingBytes[..<newlineIndex]
            pendingBytes.removeSubrange(0...newlineIndex)
            if let line = Self.decodeLine(Data(lineBytes)) {
                lines.append(line)
            }
        }

        if finalize, !pendingBytes.isEmpty {
            let lineBytes = pendingBytes
            pendingBytes.removeAll(keepingCapacity: false)
            if let line = Self.decodeLine(lineBytes) {
                lines.append(line)
            }
        }

        return lines
    }

    var pendingTextForDisplay: String {
        guard !pendingBytes.isEmpty else { return "" }
        return Self.decodeUTF8(pendingBytes)
    }

    private static func decodeLine(_ bytes: Data) -> String? {
        guard !bytes.isEmpty else { return nil }
        var trimmed = bytes
        if trimmed.last == 0x0D {
            trimmed = trimmed.dropLast()
        }
        guard !trimmed.isEmpty else { return nil }
        return decodeUTF8(trimmed)
    }

    private static func decodeUTF8(_ bytes: Data) -> String {
        String(data: bytes, encoding: .utf8)
            ?? String(decoding: bytes, as: UTF8.self)
    }
}

#if !os(Windows)
import NIOCore

extension ByteBuffer {
    var sseDataBytes: Data {
        var data = Data()
        data.reserveCapacity(readableBytes)
        if let bytes = getBytes(at: readerIndex, length: readableBytes) {
            data.append(contentsOf: bytes)
        }
        return data
    }
}
#endif
