import Foundation

/// Shared helpers for normalizing configured API roots and appending wire paths.
enum APIBaseURL {
    /// Trim whitespace and a single trailing slash from a base URL string.
    static func normalize(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.count > 1, trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }

    static func parse(_ raw: String) throws -> URL {
        let normalized = normalize(raw)
        guard let url = URL(string: normalized), url.scheme != nil, url.host != nil else {
            throw OpenAIError.invalidURL
        }
        return url
    }

    /// Path of the configured base (`""` when the URL has no path / only `/`).
    static func configuredPath(of raw: String) -> String {
        guard let url = try? parse(raw) else { return "" }
        let path = url.path
        if path.isEmpty || path == "/" {
            return ""
        }
        return path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    static func host(of raw: String) -> String? {
        (try? parse(raw))?.host
    }

    /// Whether a URL path segment includes `beta` (e.g. `/beta/chat/completions`).
    static func pathContainsBeta(_ path: String) -> Bool {
        path.lowercased()
            .split(separator: "/", omittingEmptySubsequences: true)
            .contains { $0 == "beta" }
    }

    /// Completions: empty path → `/v1/chat/completions`; else append `/chat/completions` unless already present.
    static func appendChatCompletions(to raw: String) throws -> URL {
        try append(
            to: raw,
            emptyPathReplacement: "/v1/chat/completions",
            suffix: "/chat/completions",
            alreadyHasSuffix: { $0 == "/chat/completions" || $0.hasSuffix("/chat/completions") }
        )
    }

    /// Responses: empty path → `/v1/responses`; else append `/responses` unless already present.
    static func appendResponses(to raw: String) throws -> URL {
        try append(
            to: raw,
            emptyPathReplacement: "/v1/responses",
            suffix: "/responses",
            alreadyHasSuffix: { $0 == "/responses" || $0.hasSuffix("/responses") }
        )
    }

    /// Anthropic: empty → `/v1/messages`; ends with `/v1` → `/messages`; else `/v1/messages`.
    static func appendMessages(to raw: String) throws -> URL {
        var components = try components(from: raw)
        var path = normalizedPath(from: components.path)

        if path.isEmpty || path == "/" {
            path = "/v1/messages"
        } else if path == "/messages" || path.hasSuffix("/messages") {
            // already complete
        } else if path == "/v1" || path.hasSuffix("/v1") {
            path += "/messages"
        } else {
            path += "/v1/messages"
        }

        components.path = path
        guard let url = components.url else {
            throw OpenAIError.invalidURL
        }
        return url
    }

    private static func append(
        to raw: String,
        emptyPathReplacement: String,
        suffix: String,
        alreadyHasSuffix: (String) -> Bool
    ) throws -> URL {
        var components = try components(from: raw)
        var path = normalizedPath(from: components.path)

        if path.isEmpty || path == "/" {
            path = emptyPathReplacement
        } else if alreadyHasSuffix(path) {
            // keep
        } else {
            path += suffix
        }

        components.path = path
        guard let url = components.url else {
            throw OpenAIError.invalidURL
        }
        return url
    }

    /// Files: empty path → `/v1/files`; else append `/files` unless already present.
    static func appendFiles(to raw: String) throws -> URL {
        try append(
            to: raw,
            emptyPathReplacement: "/v1/files",
            suffix: "/files",
            alreadyHasSuffix: { $0 == "/files" || $0.hasSuffix("/files") }
        )
    }

    private static func components(from raw: String) throws -> URLComponents {
        let url = try parse(raw)
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw OpenAIError.invalidURL
        }
        return components
    }

    private static func normalizedPath(from path: String) -> String {
        if path.isEmpty || path == "/" {
            return ""
        }
        var normalized = path
        while normalized.count > 1, normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }
}
