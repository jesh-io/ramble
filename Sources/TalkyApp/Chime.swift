import AVFoundation

/// Soft synthesized click sounds (no asset files). Each hit is a short
/// damped oscillation with a brief noise transient — a clean, quiet
/// "tk" rather than a musical tone.
@MainActor
final class Chime {
    static let shared = Chime()

    private struct Hit {
        var freq: Double        // Hz at onset
        var sweep: Double = 1   // multiplier the pitch decays toward (1 = no sweep)
        var tau: Double = 0.006 // amplitude decay (s)
        var noise: Double = 0.35 // transient noise amount
        var gap: Double = 0.06  // delay after this hit (s)
        var gain: Double = 1
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    private init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.45
    }

    /// Recording started: two quick clicks, second a touch higher (tk-TK).
    func start() {
        play([Hit(freq: 2100), Hit(freq: 2700)])
    }

    /// Recording stopped: the reverse (TK-tk).
    func stop() {
        play([Hit(freq: 2700), Hit(freq: 2100)])
    }

    /// Text delivered: one softer, rounder pop with a downward sweep.
    func done() {
        play([Hit(freq: 1100, sweep: 0.45, tau: 0.014, noise: 0.15, gain: 0.7)])
    }

    private func play(_ hits: [Hit]) {
        guard let buffer = render(hits) else { return }
        if !engine.isRunning {
            try? engine.start()
        }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    private func render(_ hits: [Hit]) -> AVAudioPCMBuffer? {
        let sr = format.sampleRate
        let total = hits.reduce(0) { $0 + $1.gap } + 0.08
        let frames = AVAudioFrameCount(total * sr)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let out = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) { out[i] = 0 }

        var cursor = 0.0
        var rng = SystemRandomNumberGenerator()
        for hit in hits {
            let startFrame = Int(cursor * sr)
            let n = Int(min(0.06, hit.tau * 7) * sr)
            var phase = 0.0
            for i in 0..<n where startFrame + i < Int(frames) {
                let t = Double(i) / sr
                let env = exp(-t / hit.tau) * min(1, t / 0.0006)
                // pitch glides from freq toward freq*sweep over the decay
                let f = hit.freq * (hit.sweep + (1 - hit.sweep) * exp(-t / (hit.tau * 1.5)))
                phase += 2 * .pi * f / sr
                let tone = sin(phase)
                let noise = (Double.random(in: -1...1, using: &rng)) * hit.noise * exp(-t / 0.0015)
                out[startFrame + i] += Float((tone * env + noise) * 0.7 * hit.gain)
            }
            cursor += hit.gap
        }
        return buffer
    }
}
