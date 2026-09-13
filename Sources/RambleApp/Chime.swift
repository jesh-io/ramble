import AVFoundation
import AppKit

/// Synthesized UI sounds (no asset files) in selectable themes.
@MainActor
final class Chime {
    static let shared = Chime()

    enum Theme: String, CaseIterable {
        case tap, knock, click, chime, system
        var label: String {
            switch self {
            case .tap: "Tap (soft wood)"
            case .knock: "Knock"
            case .click: "Click"
            case .chime: "Chime"
            case .system: "System (Pop / Bottle)"
            }
        }
    }

    enum Kind { case start, stop, done }

    private struct Hit {
        var freq: Double
        var sweep: Double = 1       // pitch settles toward freq*sweep
        var tau: Double = 0.006     // amplitude decay (s)
        var noise: Double = 0.35    // onset noise transient
        var partial: Double = 2.41  // overtone ratio (2.41 = woody, 2.0 = musical)
        var partialAmount: Double = 0.35
        var gap: Double = 0.06
        var gain: Double = 1
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    private init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func play(_ kind: Kind, theme: Theme, volume: Double) {
        if theme == .system {
            switch kind {
            case .start: NSSound(named: "Pop")?.play()
            case .stop: NSSound(named: "Tink")?.play()
            case .done: NSSound(named: "Bottle")?.play()
            }
            return
        }
        guard let buffer = render(hits(kind, theme)) else { return }
        engine.mainMixerNode.outputVolume = Float(max(0, min(1, volume)))
        if !engine.isRunning {
            try? engine.start()
        }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    private func hits(_ kind: Kind, _ theme: Theme) -> [Hit] {
        switch theme {
        case .tap:
            // Between knock and click: a light wooden tap — mid pitch, short
            // decay, gentle pitch drop, little noise.
            let lo = Hit(freq: 520, sweep: 0.8, tau: 0.014, noise: 0.14, partialAmount: 0.3, gap: 0.1)
            let hi = Hit(freq: 640, sweep: 0.8, tau: 0.014, noise: 0.14, partialAmount: 0.3, gap: 0.1)
            switch kind {
            case .start: return [lo, hi]
            case .stop: return [hi, lo]
            case .done: return [Hit(freq: 470, sweep: 0.75, tau: 0.018, noise: 0.1, partialAmount: 0.25, gain: 0.7)]
            }
        case .knock:
            let lo = Hit(freq: 185, sweep: 0.72, tau: 0.032, noise: 0.28, gap: 0.12)
            let hi = Hit(freq: 215, sweep: 0.72, tau: 0.032, noise: 0.28, gap: 0.12)
            switch kind {
            case .start: return [lo, hi]
            case .stop: return [hi, lo]
            case .done: return [Hit(freq: 170, sweep: 0.7, tau: 0.036, noise: 0.18, gain: 0.75)]
            }
        case .click:
            let lo = Hit(freq: 1150, tau: 0.008)
            let hi = Hit(freq: 1450, tau: 0.008)
            switch kind {
            case .start: return [lo, hi]
            case .stop: return [hi, lo]
            case .done: return [Hit(freq: 750, sweep: 0.5, tau: 0.016, noise: 0.12, gain: 0.7)]
            }
        case .chime:
            let lo = Hit(freq: 659.25, tau: 0.045, noise: 0, partial: 2, partialAmount: 0.2, gap: 0.13, gain: 0.6)
            let hi = Hit(freq: 880, tau: 0.055, noise: 0, partial: 2, partialAmount: 0.2, gap: 0.13, gain: 0.6)
            switch kind {
            case .start: return [lo, hi]
            case .stop: return [hi, lo]
            case .done: return [Hit(freq: 1046.5, tau: 0.03, noise: 0, partial: 2, partialAmount: 0.15, gain: 0.4)]
            }
        case .system:
            return []
        }
    }

    private func render(_ hits: [Hit]) -> AVAudioPCMBuffer? {
        let sr = format.sampleRate
        let total = hits.reduce(0) { $0 + $1.gap } + 0.3
        let frames = AVAudioFrameCount(total * sr)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let out = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) { out[i] = 0 }

        var cursor = 0.0
        var rng = SystemRandomNumberGenerator()
        for hit in hits {
            let startFrame = Int(cursor * sr)
            let n = Int(min(0.28, hit.tau * 7) * sr)
            var phase = 0.0
            for i in 0..<n where startFrame + i < Int(frames) {
                let t = Double(i) / sr
                let env = exp(-t / hit.tau) * min(1, t / 0.0006)
                let f = hit.freq * (hit.sweep + (1 - hit.sweep) * exp(-t / (hit.tau * 1.5)))
                phase += 2 * .pi * f / sr
                let tone = sin(phase) + hit.partialAmount * sin(phase * hit.partial) * exp(-t / (hit.tau * 0.6))
                let noise = Double.random(in: -1...1, using: &rng) * hit.noise * exp(-t / 0.0015)
                out[startFrame + i] += Float((tone * env + noise) * 0.7 * hit.gain)
            }
            cursor += hit.gap
        }
        return buffer
    }
}
