import AppKit

/// Tiny Wispr-style hover badge shown while dictating: a dark pill at the
/// bottom-center of the screen with a status dot and a single line of live
/// text. Non-activating, so focus stays in the app you're dictating into.
/// Scrolling voice level meter: newest sample enters on the right, history
/// slides left. Layer frame changes animate implicitly, so it reads smooth.
final class LevelBarsView: NSView {
    private let barCount = 14
    private let barWidth: CGFloat = 2.5
    private let gap: CGFloat = 2
    private var bars: [CALayer] = []
    private var levels: [Float]

    var meterWidth: CGFloat { CGFloat(barCount) * (barWidth + gap) - gap }

    override init(frame: NSRect) {
        levels = Array(repeating: 0, count: barCount)
        super.init(frame: frame)
        wantsLayer = true
        for _ in 0..<barCount {
            let bar = CALayer()
            bar.backgroundColor = NSColor.white.withAlphaComponent(0.85).cgColor
            bar.cornerRadius = barWidth / 2
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func push(_ level: Float) {
        levels.removeFirst()
        levels.append(level)
        layoutBars()
    }

    func reset() {
        levels = Array(repeating: 0, count: barCount)
        layoutBars()
    }

    override func layout() {
        super.layout()
        layoutBars()
    }

    private func layoutBars() {
        let h = bounds.height
        for (i, bar) in bars.enumerated() {
            let barHeight = max(2.5, CGFloat(levels[i]) * h)
            bar.frame = CGRect(
                x: CGFloat(i) * (barWidth + gap),
                y: (h - barHeight) / 2,
                width: barWidth,
                height: barHeight)
            bar.opacity = 0.35 + 0.65 * Float(i) / Float(barCount) // older = dimmer
        }
    }
}

final class LivePanel: NSObject {
    private let panel: NSPanel
    private let pill: NSView
    private let dot: NSTextField
    private let label: NSTextField
    private let skipButton: NSButton
    private let levelBars = LevelBarsView(frame: NSRect(x: 0, y: 0, width: 60, height: 16))

    /// Called when the user clicks Skip during cleanup.
    var onSkip: (() -> Void)?

    private static let height: CGFloat = 30
    private static let minWidth: CGFloat = 96
    private static let maxWidth: CGFloat = 440
    private static let hPad: CGFloat = 12
    private static let dotGap: CGFloat = 7
    private static let font = NSFont.systemFont(ofSize: 12, weight: .medium)

    /// Attributed strings carry their own paragraph style, which overrides
    /// the field's lineBreakMode — without this the pill clips the END of
    /// long text instead of truncating the head (you'd see your first words,
    /// not the ones you're currently speaking).
    private static let truncateHead: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.lineBreakMode = .byTruncatingHead
        return p
    }()

    override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.minWidth, height: Self.height),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        // .statusBar sits below a fullscreen app's space; a shielding-level
        // window with fullScreenAuxiliary shows over fullscreen apps too.
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false

        pill = NSView()
        pill.wantsLayer = true
        if let layer = pill.layer {
            layer.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
            layer.cornerRadius = Self.height / 2
            layer.cornerCurve = .continuous
            layer.borderWidth = 1
            layer.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        }

        dot = NSTextField(labelWithString: "●")
        dot.font = .systemFont(ofSize: 9)
        dot.textColor = .systemRed

        label = NSTextField(labelWithString: "")
        label.font = Self.font
        label.textColor = .white
        label.lineBreakMode = .byTruncatingHead
        label.maximumNumberOfLines = 1
        label.wantsLayer = true

        skipButton = NSButton(title: "Skip", target: nil, action: nil)
        skipButton.bezelStyle = .accessoryBarAction
        skipButton.controlSize = .mini
        skipButton.font = .systemFont(ofSize: 10, weight: .semibold)
        skipButton.isHidden = true

        pill.addSubview(dot)
        pill.addSubview(levelBars)
        pill.addSubview(label)
        pill.addSubview(skipButton)
        levelBars.isHidden = true

        let content = NSView()
        content.addSubview(pill)
        panel.contentView = content

        super.init()
        skipButton.target = self
        skipButton.action = #selector(skipTapped)
    }

    @objc private func skipTapped() {
        onSkip?()
    }

    // MARK: - Public API

    /// While recording the pill only grows — jitter from the volatile
    /// hypothesis shrinking/rewriting made the text hard to read.
    private var stickyWidth: CGFloat = 0

    /// Feed live microphone loudness while recording.
    func pushLevel(_ level: Float) {
        guard !levelBars.isHidden else { return }
        levelBars.push(level)
    }

    func show(status: String) {
        stickyWidth = 0
        setDot(status)
        setSkipVisible(false)
        levelBars.isHidden = false
        levelBars.reset()
        render(NSAttributedString(
            string: "Listening…",
            attributes: [.font: Self.font, .foregroundColor: NSColor.white.withAlphaComponent(0.55), .paragraphStyle: Self.truncateHead]))
        panel.orderFrontRegardless()
    }

    /// Minimal mode: dot + elapsed time, nothing else. The timer is
    /// fixed-width, so skip the anti-jitter sticky width — otherwise the
    /// wider "Listening…" first render leaves dead space in the pill.
    func updateElapsed(_ elapsed: String) {
        stickyWidth = 0
        render(NSAttributedString(
            string: elapsed,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.85),
                .paragraphStyle: Self.truncateHead,
            ]))
    }

    /// Cleanup phase: message + a clickable Skip button.
    func showProcessing(message: String) {
        stickyWidth = 0
        setDot("◐")
        levelBars.isHidden = true
        setSkipVisible(true)
        render(NSAttributedString(
            string: message,
            attributes: [.font: Self.font, .foregroundColor: NSColor.white.withAlphaComponent(0.75), .paragraphStyle: Self.truncateHead]))
        panel.orderFrontRegardless()
    }

    private func setSkipVisible(_ visible: Bool) {
        skipButton.isHidden = !visible
        panel.ignoresMouseEvents = !visible
    }

    /// Finalized text renders solid; the volatile hypothesis renders dimmed.
    /// Only the tail fits the pill — that's the part being spoken.
    func update(finalized: String, volatile: String, status: String? = nil) {
        if let status { setDot(status) }
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(
            string: finalized,
            attributes: [.font: Self.font, .foregroundColor: NSColor.white, .paragraphStyle: Self.truncateHead]))
        if !volatile.isEmpty {
            text.append(NSAttributedString(
                string: (finalized.isEmpty ? "" : " ") + volatile,
                attributes: [.font: Self.font, .foregroundColor: NSColor.white.withAlphaComponent(0.55), .paragraphStyle: Self.truncateHead]))
        }
        if text.length == 0 {
            text.append(NSAttributedString(
                string: "Listening…",
                attributes: [.font: Self.font, .foregroundColor: NSColor.white.withAlphaComponent(0.55), .paragraphStyle: Self.truncateHead]))
        }
        render(text)
    }

    func setStatus(_ status: String, message: String) {
        stickyWidth = 0
        setDot(status)
        levelBars.isHidden = true
        setSkipVisible(false)
        render(NSAttributedString(
            string: message,
            attributes: [.font: Self.font, .foregroundColor: NSColor.white.withAlphaComponent(0.75), .paragraphStyle: Self.truncateHead]))
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    // MARK: - Layout

    private func setDot(_ status: String) {
        dot.stringValue = status
        dot.textColor = switch status {
        case "●": .systemRed
        case "◐": .systemOrange
        case "✓": .systemGreen
        case "✕": .systemRed
        default: .tertiaryLabelColor
        }
    }

    private func render(_ text: NSAttributedString) {
        // Cross-fade text updates so streaming reads as a smooth ticker
        // instead of hard jumps.
        let fade = CATransition()
        fade.type = .fade
        fade.duration = 0.12
        label.layer?.add(fade, forKey: "textFade")
        label.attributedStringValue = text

        let dotSize = dot.intrinsicContentSize
        let skipSize = skipButton.isHidden ? .zero : skipButton.intrinsicContentSize
        let skipSpan = skipButton.isHidden ? 0 : skipSize.width + Self.dotGap
        let barsSpan = levelBars.isHidden ? 0 : levelBars.meterWidth + Self.dotGap
        // NSTextField draws a couple of points wider than the attributed
        // string measures; without slack, head-truncation kicks in and eats
        // the first characters ("Listening…" -> "…tening…").
        let textWidth = ceil(text.size().width) + 8
        let labelMax = Self.maxWidth - Self.hPad * 2 - dotSize.width - Self.dotGap - skipSpan - barsSpan
        let labelWidth = min(textWidth, labelMax)
        var pillWidth = max(Self.minWidth, Self.hPad * 2 + dotSize.width + Self.dotGap + labelWidth + skipSpan + barsSpan)
        pillWidth = max(pillWidth, stickyWidth)
        stickyWidth = pillWidth

        pill.frame = NSRect(x: 0, y: 0, width: pillWidth, height: Self.height)
        if !skipButton.isHidden {
            skipButton.frame = NSRect(
                x: pillWidth - Self.hPad - skipSize.width,
                y: (Self.height - skipSize.height) / 2,
                width: skipSize.width,
                height: skipSize.height)
        }
        dot.frame = NSRect(
            x: Self.hPad,
            y: (Self.height - dotSize.height) / 2,
            width: dotSize.width,
            height: dotSize.height)
        if !levelBars.isHidden {
            levelBars.frame = NSRect(
                x: Self.hPad + dotSize.width + Self.dotGap,
                y: (Self.height - 16) / 2,
                width: levelBars.meterWidth,
                height: 16)
        }
        let labelHeight = ceil(text.size().height)
        // Right-align the label in the available space so the newest words
        // hug the pill's right edge (or the Skip button) and flow leftward.
        label.frame = NSRect(
            x: max(Self.hPad + dotSize.width + Self.dotGap + barsSpan,
                   pillWidth - Self.hPad - skipSpan - labelWidth),
            y: (Self.height - labelHeight) / 2,
            width: labelWidth,
            height: labelHeight)

        // Keep the pill bottom-centered, animating growth smoothly.
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let frame = NSRect(
            x: (visible.midX - pillWidth / 2).rounded(),
            y: visible.minY + 16,
            width: pillWidth,
            height: Self.height)
        let animate = panel.isVisible && abs(frame.width - panel.frame.width) > 1
        panel.setFrame(frame, display: true, animate: animate)
    }
}
