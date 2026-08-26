import AppKit

/// Tiny Wispr-style hover badge shown while dictating: a dark pill at the
/// bottom-center of the screen with a status dot and a single line of live
/// text. Non-activating, so focus stays in the app you're dictating into.
final class LivePanel: NSObject {
    private let panel: NSPanel
    private let pill: NSView
    private let dot: NSTextField
    private let label: NSTextField
    private let skipButton: NSButton

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
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
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
        pill.addSubview(label)
        pill.addSubview(skipButton)

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

    func show(status: String) {
        stickyWidth = 0
        setDot(status)
        setSkipVisible(false)
        render(NSAttributedString(
            string: "Listening…",
            attributes: [.font: Self.font, .foregroundColor: NSColor.white.withAlphaComponent(0.55), .paragraphStyle: Self.truncateHead]))
        panel.orderFrontRegardless()
    }

    /// Minimal mode: dot + elapsed time, nothing else.
    func updateElapsed(_ elapsed: String) {
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
        // NSTextField draws a couple of points wider than the attributed
        // string measures; without slack, head-truncation kicks in and eats
        // the first characters ("Listening…" -> "…tening…").
        let textWidth = ceil(text.size().width) + 8
        let labelMax = Self.maxWidth - Self.hPad * 2 - dotSize.width - Self.dotGap - skipSpan
        let labelWidth = min(textWidth, labelMax)
        var pillWidth = max(Self.minWidth, Self.hPad * 2 + dotSize.width + Self.dotGap + labelWidth + skipSpan)
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
        let labelHeight = ceil(text.size().height)
        // Right-align the label in the available space so the newest words
        // hug the pill's right edge (or the Skip button) and flow leftward.
        label.frame = NSRect(
            x: pillWidth - Self.hPad - skipSpan - labelWidth,
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
