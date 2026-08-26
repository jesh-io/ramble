import Foundation
@preconcurrency import AVFAudio
import TalkyCore
import TalkyAudio
import TalkyClean
import TalkyProviders
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
        /// Microphone loudness 0…1, ~12 Hz while recording — drive a level meter.
        case audioLevel(Float)
        /// Recording finalized; LLM cleanup is starting. The raw transcript
        /// already exists — UI may offer "skip" (see `skipCleanup()`).
        case cleaningStarted
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
    private var cleanupTask: Task<String?, Never>?
    private var startupTask: Task<Void, Never>?
    private var finalizedText = ""
    private var sessionDir: URL?
    private var recordStartDate: Date?

    // The mic starts capturing before the speech stream finishes spinning
    // up; early buffers queue here and flush once the stream attaches.
    private let feedLock = NSLock()
    private var pendingBuffers: [AVAudioPCMBuffer] = []
    private var streamReady = false

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
            pendingBuffers = []
            streamReady = false

            // Start capturing IMMEDIATELY — the speech stream takes time to
            // spin up, and any words spoken meanwhile must not be lost.
            // Audio also hits the session recording from the first buffer.
            if config.recordings.enabled {
                sessionDir = try? RecordingStore.newSessionDir()
            }
            try mic.start(recordTo: sessionDir?.appendingPathComponent("audio.m4a")) { [weak self] buffer in
                guard let self else { return }
                self.emit(.audioLevel(MicCapture.level(of: buffer)))
                self.feedLock.lock()
                if self.streamReady, let stream = self.stream {
                    self.feedLock.unlock()
                    stream.feed(buffer)
                } else {
                    self.pendingBuffers.append(buffer)
                    self.feedLock.unlock()
                }
            }
            recordStartDate = Date()
            setState(.recording)

            let inputFormat = mic.inputFormat
            startupTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let stream = try await self.transcriber.makeStream(inputFormat: inputFormat)
                    self.stream = stream

                    self.eventTask = Task { [weak self] in
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

                    // Flush everything captured during spin-up, then go live.
                    let backlog = self.feedLock.withLock {
                        let queued = self.pendingBuffers
                        self.pendingBuffers = []
                        self.streamReady = true
                        return queued
                    }
                    for buffer in backlog {
                        stream.feed(buffer)
                    }
                } catch {
                    self.emit(.error("Could not start transcription: \(error.localizedDescription)"))
                }
            }
        } catch {
            emit(.error("Could not start dictation: \(error.localizedDescription)"))
        }
    }

    /// Stops recording, finalizes, cleans, and emits `.result`.
    public func stop() async {
        guard state == .recording else { return }
        mic.stop()
        // If the user stops during spin-up, wait for the stream to attach
        // (the backlog flush delivers everything they said).
        await startupTask?.value
        startupTask = nil
        guard let stream else {
            setState(.idle)
            return
        }
        if let start = recordStartDate {
            UsageLog.record(
                kind: "stt", provider: transcriber.id, model: "SpeechAnalyzer/\(config.locale)",
                seconds: Date().timeIntervalSince(start))
            recordStartDate = nil
        }
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
            if !text.isEmpty, config.cleanup.enabled, let provider = ProviderRegistry.activeCleanupProvider(config) {
                emit(.cleaningStarted)
                let base = text
                let config = config
                let task = Task<String?, Never> {
                    do {
                        let cleaner = try CleanerFactory.make(
                            provider: provider,
                            systemPrompt: config.effectiveCleanupPrompt,
                            timeout: config.cleanup.timeoutSeconds
                        )
                        let candidate = try await cleaner.clean(base)
                        guard !Task.isCancelled else { return nil }
                        guard CleanupValidator.looksFaithful(raw: base, cleaned: candidate) else {
                            self.emit(.error("Cleanup model hallucinated — using raw transcript"))
                            return nil
                        }
                        return candidate
                    } catch {
                        // Skipped (cancelled) is silent; real failures fall
                        // back to raw with a note. Never lose a dictation.
                        if !Task.isCancelled {
                            self.emit(.error("Cleanup failed (using raw transcript): \(error.localizedDescription)"))
                        }
                        return nil
                    }
                }
                cleanupTask = task
                if let cleaned = await task.value {
                    text = cleaned
                    usedProvider = provider.id
                }
                cleanupTask = nil
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

    /// Abandons an in-flight cleanup; the raw transcript is delivered as the
    /// result immediately. No-op outside the processing phase.
    public func skipCleanup() {
        cleanupTask?.cancel()
    }

    public func cancelRecording() {
        guard state == .recording else { return }
        mic.stop()
        startupTask?.cancel()
        startupTask = nil
        stream?.cancel()
        stream = nil
        eventTask?.cancel()
        setState(.idle)
    }
}
