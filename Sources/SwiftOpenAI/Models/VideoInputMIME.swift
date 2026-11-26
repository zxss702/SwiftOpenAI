import Foundation

/// Uses a bounded header sample, rather than copying the entire attachment.
enum VideoInputMIME {
    static func detect(_ data: Data) -> String {
        let bytes = Array(data.prefix(4096))
        guard bytes.count >= 8 else { return "video/mp4" }
        if bytes.starts(with: [0x1A, 0x45, 0xDF, 0xA3]) {
            let matroska = Array("matroska".utf8)
            if bytes.count >= matroska.count,
               (0...(bytes.count - matroska.count)).contains(where: {
                   bytes[$0..<($0 + matroska.count)].elementsEqual(matroska)
               }) {
                return "video/x-matroska"
            }
            return "video/webm"
        }
        if bytes.starts(with: [0x52, 0x49, 0x46, 0x46]) { return "video/avi" }
        if bytes.starts(with: [0x30, 0x26, 0xB2, 0x75]) { return "video/x-ms-wmv" }
        if bytes[4..<8].elementsEqual("ftyp".utf8), bytes.count >= 12 {
            if bytes[8..<12].elementsEqual("qt  ".utf8) { return "video/quicktime" }
            if bytes[8..<11].elementsEqual("3gp".utf8) { return "video/3gpp" }
        }
        return "video/mp4"
    }

    static func miniMaxURL(_ url: String) -> String {
        let movPrefix = "data:video/quicktime;base64,"
        guard url.hasPrefix(movPrefix) else { return url }
        return "data:video/mov;base64," + String(url.dropFirst(movPrefix.count))
    }
}
