import Foundation
@preconcurrency import AVFAudio

/// What a transcription engine can do. Lets callers adapt without knowing
/// the concrete engine.
public struct TranscriberCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Emits volatile (live, in-progress) hypotheses while streaming.
    public static let streamingPartials = TranscriberCapabilities(rawValue: 1 << 0)
    /// Segments carry start/end timestamps.
    public static let timestamps = TranscriberCapabilities(rawValue: 1 << 1)
    /// Segments carry speaker labels. No built-in engine supports this yet;
    /// the pipeline and data model are ready for one that does.
    public static let diarization = TranscriberCapabilities(rawValue: 1 << 2)
}

public enum TranscriberEvent: Sendable {
    /// Volatile hypothesis for live display. Replaced by later partials and
    /// eventually superseded by a `.segment`.
    case partial(String)
    /// A finalized segment. Accumulate these to build the transcript.
    case segment(TranscriptSegment)
}

/// A live microphone transcription session. Feed it PCM buffers; consume
/// `events` for live UI; call `finish()` for the final transcript.
public protocol TranscriptionStream: AnyObject {
    var events: AsyncThrowingStream<TranscriberEvent, Error> { get }
    func feed(_ buffer: AVAudioPCMBuffer)
    func finish() async throws -> Transcript
    func cancel()
}

/// A speech-to-text engine. Implementations must be fully self-contained;
/// callers pick one via config and interact only through this protocol.
public protocol Transcriber: Sendable {
    var id: String { get }
    var capabilities: TranscriberCapabilities { get }

    /// Performs any one-time setup (e.g. downloading an on-device model).
    func prepare() async throws

    /// Starts a streaming session for live microphone input.
    func makeStream(inputFormat: AVAudioFormat) async throws -> TranscriptionStream

    /// Transcribes an audio file (callers extract audio from video first).
    /// `onSegment` fires as each segment finalizes, for progress display.
    func transcribeFile(_ url: URL, onSegment: (@Sendable (TranscriptSegment) -> Void)?) async throws -> Transcript
}
