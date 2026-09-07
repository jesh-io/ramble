import AVFoundation

/// Soft synthesized UI chimes (no asset files): short sine tones with a
/// gentle attack, exponential decay, and a touch of second harmonic.
@MainActor
final class Chime {
    static let shared = Chime()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    private init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.32
    }

    /// Recording started: two rising notes (E5 → A5).
    func start() { play([(659.25, 0.10), (880.0, 0.14)]) }
    /// Recording stopped: the same notes falling.
    func stop() { play([(880.0, 0.10), (659.25, 0.14)]) }
    /// Text delivered: a single quiet tick.
    func done() { play([(1046.5, 0.08)], gain: 0.6) }

    private func play(_ notes: [(freq: Double, dur: Double)], gain: Float = 1) {
        guard let buffer = render(notes, gain: gain) else { return }
        if !engine.isRunning {
            try? engine.start()
        }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    private func render(_ notes: [(freq: Double, dur: Double)], gain: Float) -> AVAudioPCMBuffer? {
        let sr = format.sampleRate
        let gap = 0.03
        let total = notes.reduce(0) { $0 + $1.dur + gap } + 0.05
        let frames = AVAudioFrameCount(total * sr)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let out = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) { out[i] = 0 }

        var cursor = 0.0
        for note in notes {
            let startFrame = Int(cursor * sr)
            let n = Int(note.dur * sr)
            for i in 0..<n where startFrame + i < Int(frames) {
                let t = Double(i) / sr
                let attack = min(1, t / 0.006)
                let decay = exp(-t / (note.dur * 0.38))
                let env = attack * decay
                let s = sin(2 * .pi * note.freq * t) + 0.25 * sin(4 * .pi * note.freq * t)
                out[startFrame + i] += Float(s * env) * 0.8 * gain
            }
            cursor += note.dur + gap
        }
        return buffer
    }
}
