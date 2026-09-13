import AppKit
import RambleCore

/// Lightweight floating history browser: recent dictation sessions with
/// their cleaned/raw text and audio, straight from the recordings folder.
final class HistoryPanel: NSObject {
    private let panel: NSPanel
    private let stack = NSStackView()
    private var sessions: [RecordingStore.Session] = []

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
            styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow, .resizable],
            backing: .buffered,
            defer: true
        )
        panel.title = "Ramble History"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = stack
        panel.contentView = scroll

        super.init()

        stack.translatesAutoresizingMaskIntoConstraints = false
        if let clip = scroll.contentView as NSClipView? {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
                stack.topAnchor.constraint(equalTo: clip.topAnchor),
            ])
        }
    }

    func toggle() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            refresh()
            panel.center()
            panel.orderFrontRegardless()
        }
    }

    private func refresh() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        sessions = RecordingStore.sessions(limit: 20)

        guard !sessions.isEmpty else {
            let empty = NSTextField(labelWithString: "No dictations yet.")
            empty.textColor = .secondaryLabelColor
            stack.addArrangedSubview(pad(empty))
            return
        }
        for (index, session) in sessions.enumerated() {
            stack.addArrangedSubview(row(for: session, index: index))
            let divider = NSBox()
            divider.boxType = .separator
            stack.addArrangedSubview(divider)
            divider.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func row(for session: RecordingStore.Session, index: Int) -> NSView {
        let record = session.record

        var headerText = session.date.map { Self.timeFormat.string(from: $0) }
            ?? session.dir.lastPathComponent
        if let provider = record?.provider {
            headerText += "  ·  \(provider)"
        } else if record?.cleaned == nil {
            headerText += "  ·  raw"
        }
        if let error = record?.error {
            headerText += "  ·  ⚠️ \(error)"
        }
        let header = NSTextField(labelWithString: headerText)
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .secondaryLabelColor

        let bodyText = record.map { $0.cleaned ?? $0.raw } ?? "(no transcript)"
        let body = NSTextField(wrappingLabelWithString: bodyText)
        body.font = .systemFont(ofSize: 12.5)
        body.maximumNumberOfLines = 4
        body.cell?.truncatesLastVisibleLine = true
        body.isSelectable = true

        let copy = button("Copy", index: index, action: #selector(copyCleaned(_:)))
        let copyRaw = button("Raw", index: index, action: #selector(copyRaw(_:)))
        let audio = button("Audio", index: index, action: #selector(revealAudio(_:)))
        audio.isEnabled = session.audioURL != nil
        copyRaw.isEnabled = record != nil
        copy.isEnabled = record != nil

        let buttons = NSStackView(views: [copy, copyRaw, audio])
        buttons.orientation = .horizontal
        buttons.spacing = 6

        let column = NSStackView(views: [header, body, buttons])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 5
        return pad(column)
    }

    private func pad(_ view: NSView) -> NSView {
        let wrapper = NSStackView(views: [view])
        wrapper.orientation = .vertical
        wrapper.alignment = .leading
        wrapper.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        return wrapper
    }

    private func button(_ title: String, index: Int, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .accessoryBarAction
        b.controlSize = .small
        b.tag = index
        return b
    }

    private func session(for sender: NSButton) -> RecordingStore.Session? {
        sessions.indices.contains(sender.tag) ? sessions[sender.tag] : nil
    }

    private func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    @objc private func copyCleaned(_ sender: NSButton) {
        guard let record = session(for: sender)?.record else { return }
        copyToClipboard(record.cleaned ?? record.raw)
    }

    @objc private func copyRaw(_ sender: NSButton) {
        guard let record = session(for: sender)?.record else { return }
        copyToClipboard(record.raw)
    }

    @objc private func revealAudio(_ sender: NSButton) {
        guard let audio = session(for: sender)?.audioURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([audio])
    }
}
