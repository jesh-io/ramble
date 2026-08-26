import Foundation
import Speech
@preconcurrency import AVFAudio
import TalkyCore

/// Fully local speech-to-text using Apple's on-device SpeechAnalyzer
/// (macOS 26+). Streams volatile partials for live display and produces
/// finalized, timestamped segments. The recognition model is downloaded
/// once by the system and shared across apps.
public final class AppleTranscriber: Transcriber, @unchecked Sendable {
    public let id = "apple"
    public let capabilities: TranscriberCapabilities = [.streamingPartials, .timestamps]

    private let locale: Locale
    private let vocabulary: [String]

    public init(locale: Locale = Locale(identifier: "en-US"), vocabulary: [String] = []) {
        self.locale = locale
        // contextualStrings biases recognition toward these exact terms;
        // strip any "(misheard: ...)" hints meant only for the LLM cleaner.
        self.vocabulary = vocabulary.map {
            $0.components(separatedBy: "(")[0].trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
    }

    private func applyContext(to analyzer: SpeechAnalyzer) async {
        guard !vocabulary.isEmpty else { return }
        let context = AnalysisContext()
        context.contextualStrings[.general] = vocabulary
        try? await analyzer.setContext(context)
    }

    private func makeModule(volatile: Bool) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: volatile ? [.volatileResults, .fastResults] : [],
            attributeOptions: [.audioTimeRange]
        )
    }

    // Asset/locale checks hit slow system services; cache per process so
    // dictation startup stays instant after the first run.
    private static let preparedLock = NSLock()
    private nonisolated(unsafe) static var preparedLocales: Set<String> = []

    /// Ensures the on-device model for our locale is installed.
    public func prepare() async throws {
        let key = locale.identifier(.bcp47)
        let alreadyPrepared = Self.preparedLock.withLock { Self.preparedLocales.contains(key) }
        if alreadyPrepared { return }
        let supported = await SpeechTranscriber.supportedLocales
        guard supported.contains(where: {
            $0.identifier(.bcp47) == locale.identifier(.bcp47)
        }) else {
            throw TalkyError("Locale '\(locale.identifier)' is not supported by Apple speech recognition")
        }
        let transcriber = makeModule(volatile: false)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        Self.preparedLock.withLock { _ = Self.preparedLocales.insert(key) }
    }

    public func makeStream(inputFormat: AVAudioFormat) async throws -> TranscriptionStream {
        try await prepare()
        let transcriber = makeModule(volatile: true)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        await applyContext(to: analyzer)
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TalkyError("No compatible audio format for speech analysis")
        }
        return try await AppleStream(
            analyzer: analyzer,
            transcriber: transcriber,
            inputFormat: inputFormat,
            analyzerFormat: analyzerFormat
        )
    }

    public func transcribeFile(
        _ url: URL,
        onSegment: (@Sendable (TranscriptSegment) -> Void)? = nil
    ) async throws -> Transcript {
        try await prepare()
        let transcriber = makeModule(volatile: false)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        await applyContext(to: analyzer)
        let file = try AVAudioFile(forReading: url)

        let collector = Task {
            var segments: [TranscriptSegment] = []
            for try await result in transcriber.results {
                guard let segment = Self.segment(from: result), !segment.text.isEmpty else { continue }
                segments.append(segment)
                onSegment?(segment)
            }
            return segments
        }

        do {
            if let lastSample = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: lastSample)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            collector.cancel()
            throw error
        }

        return Transcript(segments: try await collector.value)
    }

    static func segment(from result: SpeechTranscriber.Result) -> TranscriptSegment? {
        let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var start: TimeInterval?
        var end: TimeInterval?
        let range = result.range
        if range.start.isNumeric { start = range.start.seconds }
        if range.end.isNumeric { end = range.end.seconds }
        return TranscriptSegment(text: text, start: start, end: end)
    }
}

/// Live microphone session backed by one SpeechAnalyzer run.
final class AppleStream: TranscriptionStream, @unchecked Sendable {
    let events: AsyncThrowingStream<TranscriberEvent, Error>

    private let analyzer: SpeechAnalyzer
    private let transcriber: SpeechTranscriber
    private let inputContinuation: AsyncStream<AnalyzerInput>.Continuation
    private let converter: AVAudioConverter?
    private let analyzerFormat: AVAudioFormat
    private let collector: Task<Transcript, Error>

    init(
        analyzer: SpeechAnalyzer,
        transcriber: SpeechTranscriber,
        inputFormat: AVAudioFormat,
        analyzerFormat: AVAudioFormat
    ) async throws {
        self.analyzer = analyzer
        self.transcriber = transcriber
        self.analyzerFormat = analyzerFormat

        if inputFormat == analyzerFormat {
            converter = nil
        } else {
            guard let converter = AVAudioConverter(from: inputFormat, to: analyzerFormat) else {
                throw TalkyError("Cannot convert \(inputFormat) to \(analyzerFormat)")
            }
            self.converter = converter
        }

        let (inputSequence, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputContinuation = inputContinuation

        let (events, eventsContinuation) = AsyncThrowingStream<TranscriberEvent, Error>.makeStream()
        self.events = events

        collector = Task {
            var segments: [TranscriptSegment] = []
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        if let segment = AppleTranscriber.segment(from: result) {
                            segments.append(segment)
                            eventsContinuation.yield(.segment(segment))
                        }
                    } else if !text.isEmpty {
                        eventsContinuation.yield(.partial(text))
                    }
                }
                eventsContinuation.finish()
            } catch {
                eventsContinuation.finish(throwing: error)
                throw error
            }
            return Transcript(segments: segments)
        }

        try await analyzer.start(inputSequence: inputSequence)
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let converted = convert(buffer) else { return }
        inputContinuation.yield(AnalyzerInput(buffer: converted))
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        let ratio = analyzerFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up) + 16)
        guard let output = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: max(capacity, 1024)) else {
            return nil
        }
        var fed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, output.frameLength > 0 else { return nil }
        return output
    }

    func finish() async throws -> Transcript {
        inputContinuation.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await collector.value
    }

    func cancel() {
        inputContinuation.finish()
        collector.cancel()
        Task { [analyzer] in
            await analyzer.cancelAndFinishNow()
        }
    }
}
