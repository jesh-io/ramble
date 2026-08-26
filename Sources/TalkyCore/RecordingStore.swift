import Foundation

/// File-based store of dictation sessions:
/// `~/Library/Application Support/Talky/recordings/<timestamp>/`
/// containing `audio.m4a` (written live while recording — survives crashes)
/// and `transcript.json`. Audio folders are pruned after the configured
/// retention window; transcripts also live forever in history.jsonl.
public enum RecordingStore {
    public static var baseDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Talky/recordings")
    }

    private static let nameFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    public static func newSessionDir(date: Date = Date()) throws -> URL {
        var dir = baseDir.appendingPathComponent(nameFormat.string(from: date))
        // Avoid collisions if two sessions start within a second.
        var n = 1
        while FileManager.default.fileExists(atPath: dir.path) {
            n += 1
            dir = baseDir.appendingPathComponent(nameFormat.string(from: date) + "-\(n)")
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// What actually happened in one session, stored alongside the audio.
    public struct SessionRecord: Codable, Sendable {
        public let timestamp: String
        public let raw: String
        public let cleaned: String?
        public let provider: String?
        public let segments: [TranscriptSegment]
        public let error: String?
        /// The user's hand-corrected version — golden label for evals.
        public var revision: String?

        public init(timestamp: String, raw: String, cleaned: String?, provider: String?,
                    segments: [TranscriptSegment], error: String? = nil, revision: String? = nil) {
            self.timestamp = timestamp
            self.raw = raw
            self.cleaned = cleaned
            self.provider = provider
            self.segments = segments
            self.error = error
            self.revision = revision
        }
    }

    /// Stores the user's corrected text into a session (eval golden label).
    public static func saveRevision(_ text: String, in sessionDir: URL) {
        let url = sessionDir.appendingPathComponent("transcript.json")
        guard let data = try? Data(contentsOf: url),
              var record = try? JSONDecoder().decode(SessionRecord.self, from: data)
        else { return }
        record.revision = text
        writeRecord(record, to: sessionDir)
    }

    public static func writeRecord(_ record: SessionRecord, to sessionDir: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? (try? encoder.encode(record))?.write(to: sessionDir.appendingPathComponent("transcript.json"))
    }

    public struct Session: Sendable {
        public let dir: URL
        public let record: SessionRecord?
        public let audioURL: URL?
        /// Parsed from the folder name; nil for unexpected folder names.
        public let date: Date?
    }

    /// Recent sessions, newest first.
    public static func sessions(limit: Int) -> [Session] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(
            at: baseDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        return dirs
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .prefix(limit)
            .map { dir in
                let record = (try? Data(contentsOf: dir.appendingPathComponent("transcript.json")))
                    .flatMap { try? JSONDecoder().decode(SessionRecord.self, from: $0) }
                let audio = dir.appendingPathComponent("audio.m4a")
                return Session(
                    dir: dir,
                    record: record,
                    audioURL: fm.fileExists(atPath: audio.path) ? audio : nil,
                    date: nameFormat.date(from: String(dir.lastPathComponent.prefix(19)))
                )
            }
    }

    /// Deletes session folders older than `hours`. `hours <= 0` disables
    /// pruning entirely (keep everything).
    public static func prune(olderThanHours hours: Double) {
        guard hours > 0 else { return }
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-hours * 3600)
        guard let dirs = try? fm.contentsOfDirectory(
            at: baseDir, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]
        ) else { return }
        for dir in dirs {
            let created = (try? dir.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            if let created, created < cutoff {
                try? fm.removeItem(at: dir)
            }
        }
    }
}
