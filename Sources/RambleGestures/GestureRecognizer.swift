import Foundation
import OpenMultitouchSupport
import RambleCore

/// Trackpad gesture recognition (optional add-on — uses the private
/// MultitouchSupport framework via OpenMultitouchSupport).
///
/// Detects "N-finger M-tap" gestures from raw contact frames: N fingers
/// touch down and lift within the tap window without drifting, M times in
/// quick succession. The default matches the classic BetterTouchTool
/// setup: 3-finger double tap.
public final class GestureRecognizer: @unchecked Sendable {
    /// Fires immediately when the configured tap count is reached.
    public var onGesture: (@Sendable () -> Void)?
    /// Fires once a tap sequence ends (no further tap within the gap) with
    /// the total count — e.g. 1 for a lone tap, 3 for a triple. Lets the app
    /// give extra/single taps meaning without slowing the main gesture.
    public var onTapSequence: (@Sendable (Int) -> Void)?

    private let fingers: Int
    private let taps: Int

    // Tuning
    private let tapMaxDuration: TimeInterval = 0.5   // staggered 3-finger landings need room
    private let tapMaxDrift: Float = 0.08            // normalized trackpad units
    private let interTapGap: TimeInterval = 0.6

    private let debug = ProcessInfo.processInfo.environment["RAMBLE_GESTURE_DEBUG"] != nil

    private var task: Task<Void, Never>?

    // State machine
    private var touchStart: Date?
    private var startCentroid: (x: Float, y: Float)?
    private var peakCount = 0
    private var drifted = false
    private var tapCount = 0
    private var lastTapEnd: Date?
    private var sequenceTimer: DispatchWorkItem?

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
                if debug {
                    NSLog("Ramble gesture: lift after %.0fms peak=%d drifted=%@ -> %@",
                          duration * 1000, peakCount, drifted ? "yes" : "no", clean ? "TAP" : "reject")
                }
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
        }
        peakCount = max(peakCount, active.count)

        // Too many fingers ever = not our gesture.
        if peakCount > fingers {
            drifted = true
        }

        // Fingers land in different frames, so the centroid legitimately
        // jumps as each one arrives. Only measure travel once the full
        // finger set is down, against where it was when it first completed.
        if active.count == fingers {
            let current = centroid(active)
            if let start = startCentroid {
                if abs(current.x - start.x) > tapMaxDrift || abs(current.y - start.y) > tapMaxDrift {
                    drifted = true
                }
            } else {
                startCentroid = current
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

        if debug {
            NSLog("Ramble gesture: tap %d/%d", tapCount, taps)
        }
        if tapCount == taps, let onGesture {
            DispatchQueue.main.async { onGesture() }
        }

        // Report the final count once the sequence goes quiet.
        sequenceTimer?.cancel()
        let count = tapCount
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.tapCount = 0
            self.lastTapEnd = nil
            if let onTapSequence = self.onTapSequence {
                DispatchQueue.main.async { onTapSequence(count) }
            }
        }
        sequenceTimer = work
        DispatchQueue.global().asyncAfter(deadline: .now() + interTapGap, execute: work)
    }

    private func centroid(_ touches: [OMSTouchData]) -> (x: Float, y: Float) {
        let n = Float(touches.count)
        let x = touches.reduce(Float(0)) { $0 + $1.position.x } / n
        let y = touches.reduce(Float(0)) { $0 + $1.position.y } / n
        return (x, y)
    }
}
