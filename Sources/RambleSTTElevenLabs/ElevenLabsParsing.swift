import Foundation
import RambleCore

// Payload parsing for the ElevenLabs Scribe APIs.
//
// Deliberately free of AVFoundation/URLSession so it can be exercised
// directly against the sample payloads published in the vendor docs — see
// `ElevenLabsSelfTest` at the bottom of this file.
//
// Batch response  : https://elevenlabs.io/docs/api-reference/speech-to-text/convert
// Realtime events : https://elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime
enum ElevenLabsParser {

    // MARK: - Batch: POST /v1/speech-to-text

    /// One entry of the response's `words` array.
    struct Word {
        var text: String
        /// "word" | "spacing" | "audio_event"
        var type: String
        var start: Double?
        var end: Double?
        var speakerID: String?
    }

    /// Silence between two words that starts a new segment when we are not
    /// grouping by speaker.
    static let pauseSplitSeconds: Double = 0.8
    /// Hard cap so an unpunctuated monologue still yields usable segments.
    static let maxWordsPerSegment = 60

    /// Maps ElevenLabs speaker ids ("speaker_0", "speaker_1", …) onto the
    /// short labels the rest of Ramble uses ("S1", "S2", …), numbered by
    /// order of first appearance so the first voice heard is always S1.
    static func speakerLabels(for words: [Word]) -> [String: String] {
        var labels: [String: String] = [:]
        var next = 1
        for word in words {
            guard let id = word.speakerID, labels[id] == nil else { continue }
            labels[id] = "S\(next)"
            next += 1
        }
        return labels
    }

    static func words(from json: [String: Any]) -> [Word] {
        guard let raw = json["words"] as? [[String: Any]] else { return [] }
        return raw.compactMap { entry in
            guard let text = entry["text"] as? String else { return nil }
            return Word(
                text: text,
                type: (entry["type"] as? String) ?? "word",
                start: entry["start"] as? Double,
                end: entry["end"] as? Double,
                speakerID: entry["speaker_id"] as? String
            )
        }
    }

    /// Groups words into segments: per `speaker_id` when diarizing, else on
    /// sentence ends and pauses.
    static func segments(from words: [Word], diarized: Bool) -> [TranscriptSegment] {
        let labels = diarized ? speakerLabels(for: words) : [:]
        var out: [TranscriptSegment] = []

        var text = ""
        var pendingSpacing = ""
        var start: Double?
        var end: Double?
        var speaker: String?
        var wordCount = 0
        var afterSentenceEnd = false

        func flush() {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                out.append(TranscriptSegment(text: trimmed, start: start, end: end, speaker: speaker))
            }
            text = ""
            pendingSpacing = ""
            start = nil
            end = nil
            speaker = nil
            wordCount = 0
            afterSentenceEnd = false
        }

        for word in words {
            // "spacing" entries carry the literal whitespace between words.
            // Hold onto it — it is only real if another word joins this segment.
            if word.type == "spacing" {
                if !text.isEmpty { pendingSpacing += word.text.isEmpty ? " " : word.text }
                continue
            }
            guard !word.text.isEmpty else { continue }

            let label = word.speakerID.flatMap { labels[$0] }
            if !text.isEmpty {
                let speakerChanged = diarized && label != speaker
                let longPause: Bool = {
                    guard let s = word.start, let e = end else { return false }
                    return s - e > pauseSplitSeconds
                }()
                if speakerChanged || (!diarized && (afterSentenceEnd || longPause)) || wordCount >= maxWordsPerSegment {
                    flush()
                }
            }

            if text.isEmpty {
                start = word.start
                speaker = label
            } else {
                text += pendingSpacing.isEmpty ? " " : pendingSpacing
            }
            pendingSpacing = ""
            text += word.text
            if let e = word.end { end = e }
            wordCount += 1
            afterSentenceEnd = endsSentence(word.text)
        }
        flush()
        return out
    }

    /// Parses a `/v1/speech-to-text` response body.
    static func batchTranscript(from data: Data, diarized: Bool, providerID: String) throws -> Transcript {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RambleError("elevenlabs: '\(providerID)' returned a non-JSON transcription response")
        }
        let segments = self.segments(from: words(from: json), diarized: diarized)
        if !segments.isEmpty { return Transcript(segments: segments) }
        // No word timings (e.g. timestamps were rejected) — fall back to the
        // flat `text` field.
        if let text = json["text"] as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return Transcript(segments: [TranscriptSegment(text: trimmed)]) }
        }
        return Transcript()
    }

    /// Human-readable message from an error body (`detail.message`, `detail`,
    /// `message`, or the raw body).
    static func errorMessage(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let detail = json["detail"] as? [String: Any],
               let message = detail["message"] as? String { return message }
            if let detail = json["detail"] as? String { return detail }
            if let message = json["message"] as? String { return message }
        }
        return String(decoding: data.prefix(300), as: UTF8.self)
    }

    static func endsSentence(_ text: String) -> Bool {
        let terminators: Set<Character> = [".", "!", "?", "…", "。", "！", "？"]
        // Ignore trailing quotes/brackets: `he said "stop!"` still ends a sentence.
        let closers: Set<Character> = ["\"", "'", ")", "]", "}", "”", "’", "»"]
        var chars = Array(text)
        while let last = chars.last, closers.contains(last) || last.isWhitespace { chars.removeLast() }
        guard let last = chars.last else { return false }
        return terminators.contains(last)
    }

    // MARK: - Realtime: wss://api.elevenlabs.io/v1/speech-to-text/realtime

    enum RealtimeEvent {
        case sessionStarted
        case partial(String)
        /// `timed` is true for `committed_transcript_with_timestamps`, which
        /// the server may send in addition to the plain `committed_transcript`
        /// for the same segment.
        case committed(text: String, start: Double?, end: Double?, timed: Bool)
        case failure(String)
        case ignored(String)
    }

    static func realtimeEvent(from raw: String) -> RealtimeEvent {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .ignored("unparseable")
        }
        // The wire field is `message_type`; accept `type` too in case the
        // server ever uses the shorter spelling.
        let kind = (json["message_type"] as? String) ?? (json["type"] as? String) ?? ""
        switch kind {
        case "session_started":
            return .sessionStarted
        case "partial_transcript":
            return .partial((json["text"] as? String) ?? "")
        case "committed_transcript":
            return .committed(text: (json["text"] as? String) ?? "", start: nil, end: nil, timed: false)
        case "committed_transcript_with_timestamps":
            let words = (json["words"] as? [[String: Any]]) ?? []
            let starts = words.compactMap { $0["start"] as? Double }
            let ends = words.compactMap { $0["end"] as? Double }
            return .committed(text: (json["text"] as? String) ?? "",
                              start: starts.first, end: ends.last, timed: true)
        default:
            // Every documented failure (auth_error, quota_exceeded,
            // rate_limited, chunk_size_exceeded, transcriber_error, …) is
            // `{"message_type": "<name>", "error": "..."}`.
            if kind.contains("error") || kind == "invalid_request" || json["error"] != nil {
                let detail = (json["error"] as? String)
                    ?? (json["message"] as? String)
                    ?? (json["reason"] as? String)
                    ?? raw.prefix(200).description
                return .failure(kind.isEmpty ? detail : "\(kind): \(detail)")
            }
            return .ignored(kind)
        }
    }
}

#if DEBUG
/// Parser checks against the sample payloads in the ElevenLabs docs. There
/// is no API key in this environment, so this stands in for a live call.
///
/// Run it from a scratch executable linked against this library:
/// ```
/// swift build --scratch-path .build-elevenlabs
/// cat > /tmp/eltest.swift <<'EOF'
/// import RambleSTTElevenLabs
/// let failures = ElevenLabsSelfTest.run()
/// print(failures.isEmpty ? "PASS" : "FAIL:\n" + failures.joined(separator: "\n"))
/// EOF
/// swiftc -I .build-elevenlabs/debug/Modules -L .build-elevenlabs/debug \
///     -lRambleSTTElevenLabs -lRambleTranscribe -lRambleCore /tmp/eltest.swift -o /tmp/eltest && /tmp/eltest
/// ```
public enum ElevenLabsSelfTest {

    /// Returns a list of failures; empty means everything parsed as expected.
    public static func run() -> [String] {
        var failures: [String] = []
        func check(_ label: String, _ condition: Bool, _ actual: @autoclosure () -> String = "") {
            if !condition { failures.append("✗ \(label) — got: \(actual())") }
        }

        // 1. The example response from the docs (single word, diarized).
        let single = Data("""
        {
          "language_code": "en",
          "language_probability": 0.98,
          "text": "Hello world!",
          "words": [
            { "end": 0.5, "logprob": -0.124, "speaker_id": "speaker_1", "start": 0, "text": "Hello", "type": "word" }
          ]
        }
        """.utf8)
        if let t = try? ElevenLabsParser.batchTranscript(from: single, diarized: true, providerID: "test") {
            check("batch/single count", t.segments.count == 1, "\(t.segments.count)")
            check("batch/single text", t.segments.first?.text == "Hello", "\(t.segments.first?.text ?? "nil")")
            check("batch/single start", t.segments.first?.start == 0, "\(String(describing: t.segments.first?.start))")
            check("batch/single end", t.segments.first?.end == 0.5, "\(String(describing: t.segments.first?.end))")
            check("batch/single speaker", t.segments.first?.speaker == "S1", "\(t.segments.first?.speaker ?? "nil")")
        } else {
            failures.append("✗ batch/single — threw")
        }

        // 2. Two speakers with `spacing` entries between words (the shape
        //    `timestamps_granularity=word` + `diarize=true` returns).
        let diarized = Data("""
        {
          "language_code": "en",
          "language_probability": 0.99,
          "text": "Hello there. Hi back!",
          "words": [
            { "text": "Hello", "type": "word", "start": 0.0, "end": 0.4, "speaker_id": "speaker_0" },
            { "text": " ", "type": "spacing", "start": 0.4, "end": 0.42, "speaker_id": "speaker_0" },
            { "text": "there.", "type": "word", "start": 0.42, "end": 0.9, "speaker_id": "speaker_0" },
            { "text": " ", "type": "spacing", "start": 0.9, "end": 1.2, "speaker_id": "speaker_0" },
            { "text": "Hi", "type": "word", "start": 1.2, "end": 1.4, "speaker_id": "speaker_1" },
            { "text": " ", "type": "spacing", "start": 1.4, "end": 1.42, "speaker_id": "speaker_1" },
            { "text": "back!", "type": "word", "start": 1.42, "end": 1.9, "speaker_id": "speaker_1" },
            { "text": "(laughter)", "type": "audio_event", "start": 1.9, "end": 2.4, "speaker_id": "speaker_1" }
          ]
        }
        """.utf8)
        if let t = try? ElevenLabsParser.batchTranscript(from: diarized, diarized: true, providerID: "test") {
            check("batch/diarized count", t.segments.count == 2, "\(t.segments.count)")
            check("batch/diarized s1 text", t.segments.first?.text == "Hello there.", "\(t.segments.first?.text ?? "nil")")
            check("batch/diarized s1 label", t.segments.first?.speaker == "S1", "\(t.segments.first?.speaker ?? "nil")")
            check("batch/diarized s2 label", t.segments.last?.speaker == "S2", "\(t.segments.last?.speaker ?? "nil")")
            check("batch/diarized s2 text", t.segments.last?.text == "Hi back! (laughter)", "\(t.segments.last?.text ?? "nil")")
            check("batch/diarized s2 range",
                  t.segments.last?.start == 1.2 && t.segments.last?.end == 2.4,
                  "\(String(describing: t.segments.last?.start))–\(String(describing: t.segments.last?.end))")
            check("batch/diarized formatted",
                  t.formattedText == "S1: Hello there.\nS2: Hi back! (laughter)", t.formattedText)
        } else {
            failures.append("✗ batch/diarized — threw")
        }

        // 3. Same payload without diarization: split on sentence ends and
        //    pauses, no speaker labels.
        if let t = try? ElevenLabsParser.batchTranscript(from: diarized, diarized: false, providerID: "test") {
            // The trailing audio event starts a third segment after sentence punctuation.
            check("batch/plain count", t.segments.count == 3, "\(t.segments.count)")
            check("batch/plain speakers nil", !t.hasSpeakers, "\(t.segments.map { $0.speaker ?? "-" })")
            check("batch/plain text", t.text == "Hello there. Hi back! (laughter)", t.text)
        } else {
            failures.append("✗ batch/plain — threw")
        }

        // 4. Long-pause split without punctuation (gap > 0.8 s).
        let paused = Data("""
        {"text":"one two","words":[
          {"text":"one","type":"word","start":0.0,"end":0.3},
          {"text":"two","type":"word","start":2.0,"end":2.3}]}
        """.utf8)
        if let t = try? ElevenLabsParser.batchTranscript(from: paused, diarized: false, providerID: "test") {
            check("batch/pause split", t.segments.count == 2, "\(t.segments.count)")
        } else {
            failures.append("✗ batch/pause — threw")
        }

        // 5. No `words` at all — fall back to the flat text field.
        let textOnly = Data(#"{"language_code":"en","text":"Just the text."}"#.utf8)
        if let t = try? ElevenLabsParser.batchTranscript(from: textOnly, diarized: false, providerID: "test") {
            check("batch/text-only", t.segments.map(\.text) == ["Just the text."], t.text)
        } else {
            failures.append("✗ batch/text-only — threw")
        }

        // 6. Non-JSON body must throw, not crash.
        var threw = false
        do { _ = try ElevenLabsParser.batchTranscript(from: Data("<html>502</html>".utf8), diarized: false, providerID: "test") }
        catch { threw = true }
        check("batch/non-JSON throws", threw)

        // 7. Realtime messages.
        func event(_ s: String) -> ElevenLabsParser.RealtimeEvent { ElevenLabsParser.realtimeEvent(from: s) }

        if case .sessionStarted = event(#"{"message_type":"session_started","session_id":"s_1","config":{"sample_rate":16000,"audio_format":"pcm_16000"}}"#) {
        } else { failures.append("✗ realtime/session_started") }

        if case .partial(let text) = event(#"{"message_type":"partial_transcript","text":"hello wor"}"#) {
            check("realtime/partial text", text == "hello wor", text)
        } else { failures.append("✗ realtime/partial_transcript") }

        if case .committed(let text, let start, let end, let timed) = event(#"{"message_type":"committed_transcript","text":"Hello world."}"#) {
            check("realtime/committed text", text == "Hello world.", text)
            check("realtime/committed untimed", start == nil && end == nil && !timed)
        } else { failures.append("✗ realtime/committed_transcript") }

        let timedJSON = #"""
        {"message_type":"committed_transcript_with_timestamps","text":"Hello world.","language_code":"en","words":[{"text":"Hello","start":0.0,"end":0.5},{"text":"world.","start":0.6,"end":0.9}]}
        """#
        if case .committed(let text, let start, let end, let timed) = event(timedJSON) {
            check("realtime/timed text", text == "Hello world.", text)
            check("realtime/timed range", start == 0.0 && end == 0.9 && timed,
                  "\(String(describing: start))–\(String(describing: end))")
        } else { failures.append("✗ realtime/committed_transcript_with_timestamps") }

        if case .failure(let message) = event(#"{"message_type":"auth_error","error":"Invalid API key"}"#) {
            check("realtime/auth_error", message.contains("Invalid API key"), message)
        } else { failures.append("✗ realtime/auth_error") }

        if case .failure = event(#"{"message_type":"chunk_size_exceeded","error":"chunk too large"}"#) {
        } else { failures.append("✗ realtime/chunk_size_exceeded") }

        if case .ignored = event(#"{"message_type":"committed_transcript_entities","text":"x","entities":[]}"#) {
        } else { failures.append("✗ realtime/entities ignored") }

        if case .ignored = event("not json at all") {
        } else { failures.append("✗ realtime/garbage ignored") }

        // 8. Error-body extraction.
        check("error/detail.message",
              ElevenLabsParser.errorMessage(from: Data(#"{"detail":{"status":"invalid_api_key","message":"Invalid API key"}}"#.utf8)) == "Invalid API key")
        check("error/raw",
              ElevenLabsParser.errorMessage(from: Data("boom".utf8)) == "boom")

        return failures
    }
}
#endif
