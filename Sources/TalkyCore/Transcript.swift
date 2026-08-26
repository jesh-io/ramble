import Foundation

/// A finalized piece of transcribed speech.
///
/// `speaker` is reserved for diarization-capable transcribers (see
/// `TranscriberCapabilities.diarization`). Engines that cannot identify
/// speakers leave it `nil`.
public struct TranscriptSegment: Codable, Sendable, Equatable {
    public var text: String
    public var start: TimeInterval?
    public var end: TimeInterval?
    public var speaker: String?

    public init(text: String, start: TimeInterval? = nil, end: TimeInterval? = nil, speaker: String? = nil) {
        self.text = text
        self.start = start
        self.end = end
        self.speaker = speaker
    }
}

/// An ordered collection of finalized segments produced by a `Transcriber`.
public struct Transcript: Codable, Sendable, Equatable {
    public var segments: [TranscriptSegment]

    public init(segments: [TranscriptSegment] = []) {
        self.segments = segments
    }

    public var isEmpty: Bool { text.isEmpty }

    public var hasSpeakers: Bool { segments.contains { $0.speaker != nil } }

    /// Plain text of the whole transcript, whitespace-normalized.
    public var text: String {
        segments
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Text formatted with speaker labels when diarization data is present,
    /// e.g. "S1: hello\nS2: hi there". Falls back to `text` otherwise.
    public var formattedText: String {
        guard hasSpeakers else { return text }
        var lines: [String] = []
        var currentSpeaker: String? = nil
        var currentParts: [String] = []
        func flush() {
            guard !currentParts.isEmpty else { return }
            let body = currentParts.joined(separator: " ")
            lines.append(currentSpeaker.map { "\($0): \(body)" } ?? body)
            currentParts = []
        }
        for segment in segments {
            let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if segment.speaker != currentSpeaker {
                flush()
                currentSpeaker = segment.speaker
            }
            currentParts.append(trimmed)
        }
        flush()
        return lines.joined(separator: "\n")
    }
}

/// General-purpose error with a human-readable message.
public struct TalkyError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
