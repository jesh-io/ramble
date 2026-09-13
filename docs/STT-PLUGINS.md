# Speech-to-text plugin contract

Each remote STT engine is its own SPM target (`Sources/RambleSTT<Name>/`),
registered with `TranscriberFactory` and gated by `canImport` in
`Sources/RambleKit/STTPlugins.swift`. Removing a target from `RambleKit`'s
dependencies in `Package.swift` drops the engine cleanly.

## What a plugin implements

```swift
public enum <Name>STTPlugin {
    public static func register()   // TranscriberFactory.register(engine: "<engine>") { provider, options in ... }
}
```
The builder returns a `Transcriber` (RambleCore):

```swift
public protocol Transcriber: Sendable {
    var id: String { get }                       // = provider.id
    var capabilities: TranscriberCapabilities { get }   // .streamingPartials, .timestamps, .diarization
    func prepare() async throws                  // validate key/config; cheap
    func makeStream(inputFormat: AVAudioFormat) async throws -> TranscriptionStream   // live mic
    func transcribeFile(_ url: URL, onSegment: (@Sendable (TranscriptSegment) -> Void)?) async throws -> Transcript
}
public protocol TranscriptionStream: AnyObject {
    var events: AsyncThrowingStream<TranscriberEvent, Error> { get }   // .partial(String) / .segment(TranscriptSegment)
    func feed(_ buffer: AVAudioPCMBuffer)        // called from the audio thread, ~12×/s
    func finish() async throws -> Transcript     // flush, wait for finals, close
    func cancel()
}
```

Inputs: `STTProvider` (id, engine, baseURL, model, resolvedAPIKey,
supportsStreaming, supportsDiarization) and `STTOptions` (locale,
vocabulary [bare terms — use for keyword boosting if the API supports it],
mode "auto|streaming|batch", diarize).

## Rules

- **Mode**: if `options.wantsStreaming(engineSupportsStreaming:)` and the
  model streams → real streaming. Otherwise return
  `BatchFallbackStream(inputFormat:) { url in try await transcribeFile(url) }`
  (records a 16 kHz WAV, transcribes at finish).
- **Streaming**: convert with `PCM16Converter(inputFormat:)` → 16 kHz mono
  s16le. Use `WebSocketClient` (connect / send(json:|data:) / `messages`
  async stream / close). Emit `.partial` for interim hypotheses and
  `.segment` for finalized text with start/end seconds when available. On
  `finish()`, signal end-of-audio per the API, drain remaining finals with
  a bounded wait (≤ 5 s), close, and return the Transcript of all segments.
  Never block `feed`; queue if the socket isn't open yet.
- **Batch**: upload the file (`MultipartFormData`, `MediaMIME.type(for:)`),
  poll if the API is async, map results to `TranscriptSegment`s with
  timestamps. When `options.diarize` and the model supports it, request
  speaker labels and set `segment.speaker` (e.g. "S1"). Set
  `.diarization` in capabilities only if supported.
- **Errors**: throw a concise `RambleError` with provider and HTTP status;
  avoid retaining raw response bodies that may echo user content or credentials.
  Missing key → throw in `prepare()`.
- Language mode is Swift 5 (no strict concurrency); mark stream classes
  `@unchecked Sendable`. Follow `AppleStream` in
  `Sources/RambleTranscribe/AppleTranscriber.swift` for shape.
- Keep provider implementation in its target; update registry/capabilities and
  tests when enabling it. Build with
  `swift build --scratch-path .build-<name> --target RambleSTT<Name>` to avoid
  lock contention with parallel builds.
- No API keys are available locally. Verify: it compiles; message parsing
  is exercised against sample payloads from the vendor docs (embed a
  `#if DEBUG` self-test or a static `parse` function you call from a
  comment-documented example); the batch path is tried with
  `.build-<name>/debug/ramble` only if a key appears in the environment.
