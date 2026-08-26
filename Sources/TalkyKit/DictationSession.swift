import Foundation
@preconcurrency import AVFAudio
import TalkyCore
import TalkyAudio
import TalkyClean
import TalkyTranscribe

/// Orchestrates one push-to-talk dictation cycle:
/// mic → streaming transcriber → (optional) LLM cleanup → final text.
///
/// Events are delivered on the main queue so UI can consume them directly.
public final class DictationSession: @unchecked Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case recording
        case processing
    }

    public enum Event: Sendable {
        case stateChanged(State)
        /// Finalized text so far + current volatile hypothesis — join for live display.
        case liveText(finalized: String, volatile: String)
        /// The finished, cleaned result.
        case result(text: String, raw: String)
        case error(String)
    }

    public private(set) var state: State = .idle
    public var onEvent: ((Event) -> Void)?

    private let config: TalkyConfig
    private let transcriber: Transcriber
    private let mic = MicCapture()
    private var stream: TranscriptionStream?
    private var eventTask: Task<Void, Never>?
    private var finalizedText = ""
    private var sessionDir: URL?

    private var timestamp: String { ISO8601DateFormatter().string(from: Date()) }

    public init(config: TalkyConfig, transcriber: Transcriber? = nil) {
        self.config = config
        self.transcriber = transcriber
            ?? AppleTranscriber(locale: Locale(identifier: config.locale), vocabulary: config.vocabulary)
    }

    private func emit(_ event: Event) {
        DispatchQueue.main.async { [onEvent] in onEvent?(event) }
    }

    private func setState(_ new: State) {
        state = new
        emit(.stateChanged(new))
    }

    public func start() async {
        guard state == .idle else { return }
        guard await MicCapture.requestPermission() else {
            emit(.error("Microphone access denied. Enable it in System Settings → Privacy & Security → Microphone."))
            return
        }
        do {
            finalizedText = ""
            let stream = try await transcriber.makeStream(inputFormat: mic.inputFormat)
            self.stream = stream

            eventTask = Task { [weak self] in
                do {
                    for try await event in stream.events {
                        guard let self else { return }
                        switch event {
                        case .partial(let text):
                            self.emit(.liveText(finalized: self.finalizedText, volatile: text))
                        case .segment(let segment):
                            self.finalizedText = Transcript(
                                segments: [TranscriptSegment(text: self.finalizedText), segment]
                            ).text
                            self.emit(.liveText(finalized: self.finalizedText, volatile: ""))
                        }
                    }
                } catch {
                    self?.emit(.error("Transcription failed: \(error.localizedDescription)"))
                }
            }

            if config.recordings.enabled {
                sessionDir = try? RecordingStore.newSessionDir()
            }
            try mic.start(recordTo: sessionDir?.appendingPathComponent("audio.m4a")) { [weak self] buffer in
                self?.stream?.feed(buffer)
            }
            setState(.recording)
        } catch {
            stream?.cancel()
            stream = nil
            emit(.error("Could not start dictation: \(error.localizedDescription)"))
        }
    }

    /// Stops recording, finalizes, cleans, and emits `.result`.
    public func stop() async {
        guard state == .recording, let stream else { return }
        mic.stop()
        setState(.processing)
        do {
            let transcript = try await stream.finish()
            self.stream = nil
            eventTask?.cancel()

            let raw = transcript.text
            // Spoken commands ("new paragraph") are applied deterministically
            // here so breaks never depend on the cleanup model.
            var text = Vocabulary.applyKnownMishearings(
                to: SpokenCommands.apply(to: raw), vocabulary: config.vocabulary)
            var usedProvider: String? = nil
            if !text.isEmpty, config.cleanup.enabled, let provider = config.cleanup.activeProvider {
                do {
                    let cleaner = try CleanerFactory.make(
                        provider: provider,
                        systemPrompt: config.effectiveCleanupPrompt,
                        timeout: config.cleanup.timeoutSeconds
                    )
                    let candidate = try await cleaner.clean(text)
                    if CleanupValidator.looksFaithful(raw: text, cleaned: candidate) {
                        text = candidate
                        usedProvider = provider.id
                    } else {
                        emit(.error("Cleanup model hallucinated — using raw transcript"))
                    }
                } catch {
                    // Never lose a dictation to a cleanup failure — fall back to raw.
                    emit(.error("Cleanup failed (using raw transcript): \(error.localizedDescription)"))
                }
            }
            if !raw.isEmpty {
                DictationHistory.append(raw: raw, cleaned: text, provider: usedProvider)
            }
            if let sessionDir {
                RecordingStore.writeRecord(
                    RecordingStore.SessionRecord(
                        timestamp: timestamp, raw: raw, cleaned: text,
                        provider: usedProvider, segments: transcript.segments),
                    to: sessionDir)
            }
            RecordingStore.prune(olderThanHours: config.recordings.retentionHours)
            sessionDir = nil
            setState(.idle)
            emit(.result(text: text, raw: raw))
        } catch {
            self.stream = nil
            eventTask?.cancel()
            // Finalization failed — the audio file is already on disk; save
            // what we transcribed so far so nothing is lost.
            if let sessionDir {
                RecordingStore.writeRecord(
                    RecordingStore.SessionRecord(
                        timestamp: timestamp, raw: finalizedText, cleaned: nil,
                        provider: nil, segments: [], error: error.localizedDescription),
                    to: sessionDir)
            }
            sessionDir = nil
            setState(.idle)
            emit(.error("Could not finalize transcription: \(error.localizedDescription)"))
        }
    }

    public func cancelRecording() {
        guard state == .recording else { return }
        mic.stop()
        stream?.cancel()
        stream = nil
        eventTask?.cancel()
        setState(.idle)
    }
}
