import Foundation
import OpenMultitouchSupport
import TalkyCore

/// Trackpad gesture recognition (optional add-on — uses the private
/// MultitouchSupport framework via OpenMultitouchSupport).
///
/// Detects "N-finger M-tap" gestures from raw contact frames: N fingers
/// touch down and lift within the tap window without drifting, M times in
/// quick succession. The default matches the classic BetterTouchTool
/// setup: 3-finger double tap.
public final class GestureRecognizer: @unchecked Sendable {
    public var onGesture: (@Sendable () -> Void)?

    private let fingers: Int
    private let taps: Int

    // Tuning
    private let tapMaxDuration: TimeInterval = 0.35
    private let tapMaxDrift: Float = 0.06        // normalized trackpad units
    private let interTapGap: TimeInterval = 0.45

    private var task: Task<Void, Never>?

    // State machine
    private var touchStart: Date?
    private var startCentroid: (x: Float, y: Float)?
    private var peakCount = 0
    private var drifted = false
    private var tapCount = 0
    private var lastTapEnd: Date?

    public init(fingers: Int = 3, taps: Int = 2) {
        self.fingers = max(1, min(fingers, 5))
        self.taps = max(1, min(taps, 3))
    }

    public func start() {
        guard task == nil else { return }
        let manager = OMSManager.shared
        task = Task { [weak self] in
            for await frame in manager.touchDataStream {
                self?.process(frame)
            }
        }
        _ = manager.startListening()
    }

    public func stop() {
        _ = OMSManager.shared.stopListening()
        task?.cancel()
        task = nil
        reset()
    }

    private func reset() {
        touchStart = nil
        startCentroid = nil
        peakCount = 0
        drifted = false
    }

    private func process(_ frame: [OMSTouchData]) {
        let active = frame.filter {
            $0.state == .making || $0.state == .touching || $0.state == .starting
        }
        let now = Date()

        if active.isEmpty {
            // All fingers lifted — was that a clean N-finger tap?
            if let began = touchStart {
                let duration = now.timeIntervalSince(began)
                let clean = duration <= tapMaxDuration && peakCount == fingers && !drifted
                reset()
                if clean {
                    registerTap(at: now)
                } else {
                    tapCount = 0
                    lastTapEnd = nil
                }
            }
            return
        }

        if touchStart == nil {
            touchStart = now
            startCentroid = centroid(active)
        }
        peakCount = max(peakCount, active.count)

        // Too many fingers ever = not our gesture.
        if peakCount > fingers {
            drifted = true
        }
        // A tap doesn't travel; swipes and drags do.
        if let start = startCentroid, active.count == peakCount {
            let current = centroid(active)
            if abs(current.x - start.x) > tapMaxDrift || abs(current.y - start.y) > tapMaxDrift {
                drifted = true
            }
        }
        // Held too long = a press/drag, not a tap.
        if let began = touchStart, now.timeIntervalSince(began) > tapMaxDuration {
            drifted = true
        }
    }

    private func registerTap(at time: Date) {
        if let last = lastTapEnd, time.timeIntervalSince(last) <= interTapGap {
            tapCount += 1
        } else {
            tapCount = 1
        }
        lastTapEnd = time

        if tapCount >= taps {
            tapCount = 0
            lastTapEnd = nil
            if let onGesture {
                DispatchQueue.main.async { onGesture() }
            }
        }
    }

    private func centroid(_ touches: [OMSTouchData]) -> (x: Float, y: Float) {
        let n = Float(touches.count)
        let x = touches.reduce(Float(0)) { $0 + $1.position.x } / n
        let y = touches.reduce(Float(0)) { $0 + $1.position.y } / n
        return (x, y)
    }
}
