import Foundation

/// Append-only log of dictations (raw vs cleaned) at
/// `~/.config/ramble/history.jsonl` — for debugging whether the speech engine
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
        RambleConfig.fileURL.deletingLastPathComponent().appendingPathComponent("history.jsonl")
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
        try? PrivateFiles.directory(url.deletingLastPathComponent())
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? PrivateFiles.write(data, to: url)
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public static func last(_ count: Int) -> [Entry] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return content
            .split(separator: "\n")
            .suffix(count)
            .compactMap { try? decoder.decode(Entry.self, from: Data($0.utf8)) }
    }

    public static func clear() throws {
        try PrivateFiles.write(Data(), to: fileURL)
    }

    public static func prune(olderThanHours hours: Double) {
        guard hours > 0, let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let cutoff = Date().addingTimeInterval(-hours * 3600)
        let formatter = ISO8601DateFormatter()
        let kept = contents.split(separator: "\n").filter { line in
            guard let entry = try? JSONDecoder().decode(Entry.self, from: Data(line.utf8)),
                  let date = formatter.date(from: entry.timestamp) else { return false }
            return date >= cutoff
        }
        try? PrivateFiles.write(Data((kept.isEmpty ? "" : kept.joined(separator: "\n") + "\n").utf8), to: fileURL)
    }
}
