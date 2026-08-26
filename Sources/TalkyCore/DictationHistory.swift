import Foundation

/// Append-only log of dictations (raw vs cleaned) at
/// `~/.config/talky/history.jsonl` — for debugging whether the speech engine
/// or the cleanup model dropped/changed a word.
public enum DictationHistory {
    public struct Entry: Codable, Sendable {
        public let timestamp: String
        public let raw: String
        public let cleaned: String
        public let provider: String?

        public init(timestamp: String, raw: String, cleaned: String, provider: String?) {
            self.timestamp = timestamp
            self.raw = raw
            self.cleaned = cleaned
            self.provider = provider
        }
    }

    public static var fileURL: URL {
        TalkyConfig.fileURL.deletingLastPathComponent().appendingPathComponent("history.jsonl")
    }

    public static func append(raw: String, cleaned: String, provider: String?) {
        let entry = Entry(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            raw: raw,
            cleaned: cleaned,
            provider: provider
        )
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

    public static func last(_ count: Int) -> [Entry] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return content
            .split(separator: "\n")
            .suffix(count)
            .compactMap { try? decoder.decode(Entry.self, from: Data($0.utf8)) }
    }
}
