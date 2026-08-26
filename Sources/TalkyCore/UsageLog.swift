import Foundation

/// Append-only usage ledger at `~/.config/talky/usage.jsonl`.
/// STT engines log seconds of audio processed; text models log tokens
/// in/out. Costs are derived at read time from provider rates in config,
/// so historical entries reprice correctly if rates change.
public enum UsageLog {
    public struct Entry: Codable, Sendable {
        public let ts: String
        /// "stt" or "cleanup"
        public let kind: String
        public let provider: String
        public let model: String
        public let seconds: Double?
        public let tokensIn: Int?
        public let tokensOut: Int?

        public var day: String { String(ts.prefix(10)) }
    }

    public static var fileURL: URL {
        TalkyConfig.fileURL.deletingLastPathComponent().appendingPathComponent("usage.jsonl")
    }

    public static func record(
        kind: String, provider: String, model: String,
        seconds: Double? = nil, tokensIn: Int? = nil, tokensOut: Int? = nil
    ) {
        let entry = Entry(
            ts: ISO8601DateFormatter().string(from: Date()),
            kind: kind, provider: provider, model: model,
            seconds: seconds, tokensIn: tokensIn, tokensOut: tokensOut)
        guard var data = try? JSONEncoder().encode(entry) else { return }
        data.append(0x0A)
        let url = fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    public static func entries() -> [Entry] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return content.split(separator: "\n").compactMap {
            try? decoder.decode(Entry.self, from: Data($0.utf8))
        }
    }
}
