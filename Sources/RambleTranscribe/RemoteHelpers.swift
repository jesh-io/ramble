import Foundation
@preconcurrency import AVFAudio
import RambleCore

// Shared plumbing for remote speech-to-text plugins.

/// Converts microphone buffers (any format) to 16 kHz mono 16-bit little
/// endian PCM — what nearly every streaming STT API wants.
public final class PCM16Converter: @unchecked Sendable {
    public let outputFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private let inputFormat: AVAudioFormat

    public init(inputFormat: AVAudioFormat, sampleRate: Double = 16_000) {
        self.inputFormat = inputFormat
        self.outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true)!
        self.converter = AVAudioConverter(from: inputFormat, to: outputFormat)
    }

    /// Raw little-endian Int16 bytes.
    public func convert(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let converter else { return nil }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up) + 32)
        guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: max(capacity, 256)) else { return nil }
        var fed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if fed { outStatus.pointee = .noDataNow; return nil }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, out.frameLength > 0, let ch = out.int16ChannelData else { return nil }
        return Data(bytes: ch[0], count: Int(out.frameLength) * MemoryLayout<Int16>.size)
    }
}

/// Minimal WebSocket client over URLSession: connect with headers, send
/// text/binary, consume messages as an async stream.
public final class WebSocketClient: @unchecked Sendable {
    public enum Message: Sendable {
        case text(String)
        case data(Data)
    }

    private let task: URLSessionWebSocketTask
    private let session: URLSession
    public let messages: AsyncThrowingStream<Message, Error>
    private let continuation: AsyncThrowingStream<Message, Error>.Continuation

    public init(url: URL, headers: [String: String] = [:], timeout: TimeInterval = 30) {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
        task = session.webSocketTask(with: request)
        (messages, continuation) = AsyncThrowingStream<Message, Error>.makeStream()
    }

    public func connect() {
        task.resume()
        receiveLoop()
    }

    private func receiveLoop() {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let s): self.continuation.yield(.text(s))
                case .data(let d): self.continuation.yield(.data(d))
                @unknown default: break
                }
                self.receiveLoop()
            case .failure(let error):
                self.continuation.finish(throwing: error)
            }
        }
    }

    public func send(text: String) async throws {
        try await task.send(.string(text))
    }

    public func send(json: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: json)
        try await task.send(.string(String(decoding: data, as: UTF8.self)))
    }

    public func send(data: Data) async throws {
        try await task.send(.data(data))
    }

    public func close() {
        task.cancel(with: .normalClosure, reason: nil)
        continuation.finish()
        session.finishTasksAndInvalidate()
    }
}

/// multipart/form-data body builder for file uploads.
public struct MultipartFormData {
    public let boundary = "RambleBoundary-\(UUID().uuidString)"
    private var body = Data()

    public init() {}

    public mutating func addField(_ name: String, value: String) {
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
    }

    public mutating func addFile(_ name: String, filename: String, mimeType: String, data: Data) {
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
    }

    public func finalize() -> (body: Data, contentType: String) {
        var d = body
        d.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return (d, "multipart/form-data; boundary=\(boundary)")
    }
}

public enum MediaMIME {
    public static func type(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "wav": "audio/wav"
        case "m4a", "mp4": "audio/mp4"
        case "mp3": "audio/mpeg"
        case "aiff", "aif": "audio/aiff"
        case "flac": "audio/flac"
        case "ogg": "audio/ogg"
        case "webm": "audio/webm"
        default: "application/octet-stream"
        }
    }
}

/// Gives batch-only engines a streaming interface: mic buffers are written
/// to a temporary 16 kHz WAV, and `finish()` transcribes the file. No
/// partials are emitted (the UI shows recording state only).
public final class BatchFallbackStream: TranscriptionStream, @unchecked Sendable {
    public let events: AsyncThrowingStream<TranscriberEvent, Error>
    private let continuation: AsyncThrowingStream<TranscriberEvent, Error>.Continuation
    private let file: AVAudioFile
    private let url: URL
    private let converter: PCM16Converter
    private let transcribe: @Sendable (URL) async throws -> Transcript
    private var cancelled = false

    public init(inputFormat: AVAudioFormat, transcribe: @escaping @Sendable (URL) async throws -> Transcript) throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("ramble-batch-\(UUID().uuidString).wav")
        converter = PCM16Converter(inputFormat: inputFormat)
        file = try AVAudioFile(forWriting: url, settings: converter.outputFormat.settings)
        self.transcribe = transcribe
        (events, continuation) = AsyncThrowingStream<TranscriberEvent, Error>.makeStream()
    }

    public func feed(_ buffer: AVAudioPCMBuffer) {
        guard let data = converter.convert(buffer) else { return }
        let frames = AVAudioFrameCount(data.count / 2)
        guard let pcm = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: frames),
              let ch = pcm.int16ChannelData else { return }
        pcm.frameLength = frames
        data.withUnsafeBytes { raw in
            _ = memcpy(ch[0], raw.baseAddress!, data.count)
        }
        try? file.write(from: pcm)
    }

    public func finish() async throws -> Transcript {
        continuation.finish()
        defer { try? FileManager.default.removeItem(at: url) }
        guard !cancelled else { return Transcript() }
        return try await transcribe(url)
    }

    public func cancel() {
        cancelled = true
        continuation.finish()
        try? FileManager.default.removeItem(at: url)
    }
}

/// Batch transcription through the OpenAI-compatible
/// `POST {baseURL}/audio/transcriptions` endpoint (OpenAI, Groq, Mistral,
/// and any compatible server). Requests `verbose_json` for segments when
/// available and falls back to plain text.
public struct OpenAICompatBatchTranscriber: Transcriber {
    public let id: String
    public let capabilities: TranscriberCapabilities = [.timestamps]
    private let provider: STTProvider
    private let options: STTOptions
    /// Some servers reject `verbose_json` for certain models; set false to
    /// request `json` only.
    private let verbose: Bool

    public init(provider: STTProvider, options: STTOptions, verbose: Bool = true) {
        self.id = provider.id
        self.provider = provider
        self.options = options
        self.verbose = verbose
    }

    public func prepare() async throws {
        guard provider.resolvedAPIKey != nil else {
            throw RambleError("No API key for '\(provider.id)' (set \(provider.apiKeyEnv ?? "its apiKeyEnv"))")
        }
    }

    public func makeStream(inputFormat: AVAudioFormat) async throws -> TranscriptionStream {
        try await prepare()
        let me = self
        return try BatchFallbackStream(inputFormat: inputFormat) { url in
            try await me.transcribeFile(url, onSegment: nil)
        }
    }

    public func transcribeFile(_ url: URL, onSegment: (@Sendable (TranscriptSegment) -> Void)?) async throws -> Transcript {
        try await prepare()
        guard let endpoint = URL(string: provider.baseURL)?.appending(path: "audio/transcriptions") else {
            throw RambleError("Bad baseURL for '\(provider.id)'")
        }
        let data = try Data(contentsOf: url)
        var form = MultipartFormData()
        form.addField("model", value: provider.model)
        form.addField("response_format", value: verbose ? "verbose_json" : "json")
        if let lang = options.locale.language.languageCode?.identifier {
            form.addField("language", value: lang)
        }
        if !options.vocabulary.isEmpty {
            form.addField("prompt", value: options.vocabulary.joined(separator: ", "))
        }
        form.addFile("file", filename: url.lastPathComponent, mimeType: MediaMIME.type(for: url), data: data)
        let (body, contentType) = form.finalize()

        var request = URLRequest(url: endpoint, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(provider.resolvedAPIKey ?? "")", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let (respData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw RambleError("'\(provider.id)' transcription HTTP \(status): \(String(data: respData.prefix(300), encoding: .utf8) ?? "")")
        }
        guard let json = try JSONSerialization.jsonObject(with: respData) as? [String: Any] else {
            throw RambleError("'\(provider.id)' returned non-JSON")
        }
        var segments: [TranscriptSegment] = []
        if let segs = json["segments"] as? [[String: Any]] {
            for seg in segs {
                guard let text = seg["text"] as? String else { continue }
                let s = TranscriptSegment(text: text.trimmingCharacters(in: .whitespaces),
                                          start: seg["start"] as? Double, end: seg["end"] as? Double)
                segments.append(s)
                onSegment?(s)
            }
        }
        if segments.isEmpty, let text = json["text"] as? String, !text.isEmpty {
            let s = TranscriptSegment(text: text)
            segments = [s]
            onSegment?(s)
        }
        return Transcript(segments: segments)
    }
}
