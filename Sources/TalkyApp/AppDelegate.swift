import AppKit
import TalkyCore
import TalkyKit
import TalkyProviders
#if canImport(TalkyGestures)
import TalkyGestures
#endif

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private let panel = LivePanel()
    private let historyPanel = HistoryPanel()

    private var config = TalkyConfig.load()
    private var session: DictationSession?
    private var busy = false
    private var recordingStart: Date?
    private var recordingTimer: Timer?
    private var settingsController: SettingsWindowController?
    #if canImport(TalkyGestures)
    private var gestureRecognizer: GestureRecognizer?
    #endif

    // "Send" flow: an extra tap queues Return for the upcoming paste; a
    // lone tap shortly after a paste presses Return immediately.
    private var sendPending = false
    private var lastPasteAt: Date?
    private let sendWindow: TimeInterval = 10
    private var commandReturn: Bool { config.output.sendKey == "cmd-return" }

    private var captions: String { config.output.captions }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setIdleIcon()
        rebuildMenu()
        registerHotkey()
        applyGestureConfig()
        observeCLICommands()
        panel.onSkip = { [weak self] in self?.session?.skipCleanup() }

        if config.output.paste && !Paster.canPaste {
            Paster.requestAccessibility()
        }

        // Warm up the speech model in the background so the first dictation
        // starts instantly.
        let cfg = config
        Task.detached {
            try? await TalkyKit.makeDefaultTranscriber(config: cfg).prepare()
        }
    }

    /// Starts/stops the trackpad gesture recognizer per config. No-op in
    /// builds without the TalkyGestures add-on.
    private func applyGestureConfig() {
        #if canImport(TalkyGestures)
        gestureRecognizer?.stop()
        gestureRecognizer = nil
        guard config.gesture.enabled else { return }
        let recognizer = GestureRecognizer(
            fingers: config.gesture.fingers, taps: config.gesture.taps)
        recognizer.onGesture = { [weak self] in
            Task { @MainActor in self?.toggle() }
        }
        recognizer.onTapSequence = { [weak self] count in
            Task { @MainActor in self?.handleTapSequence(count) }
        }
        recognizer.start()
        gestureRecognizer = recognizer
        #endif
    }

    /// Extra/lone taps mean "send": while cleanup runs, arm Return for the
    /// paste; within the window after a paste, press it now.
    private func handleTapSequence(_ count: Int) {
        guard config.gesture.tapToEnter, count != config.gesture.taps else { return }
        if session?.state == .processing {
            sendPending = true
            if captions != "off" {
                panel.showProcessing(message: "Cleaning up… will send ↩")
            }
        } else if let pasted = lastPasteAt, Date().timeIntervalSince(pasted) <= sendWindow {
            lastPasteAt = nil
            Paster.sendReturn(command: commandReturn)
            if captions != "off" {
                panel.setStatus("✓", message: "Sent ↩")
                hidePanelSoon(after: 1)
            }
        }
    }

    private func registerHotkey() {
        hotKey = HotKey(spec: config.hotkey) { [weak self] in
            Task { @MainActor in self?.toggle() }
        }
        if hotKey == nil {
            NSLog("Talky: could not register hotkey '\(config.hotkey)'")
        }
    }

    private func observeCLICommands() {
        let center = DistributedNotificationCenter.default()
        let cases: [(String, () -> Void)] = [
            ("io.talky.toggle", { [weak self] in self?.toggle() }),
            ("io.talky.start", { [weak self] in self?.startDictation() }),
            ("io.talky.stop", { [weak self] in self?.stopDictation() }),
            ("io.talky.reload", { [weak self] in self?.reloadConfig() }),
        ]
        for (name, action) in cases {
            center.addObserver(
                forName: Notification.Name(name), object: nil, queue: .main
            ) { _ in
                MainActor.assumeIsolated { action() }
            }
        }
    }

    // MARK: - Status item

    private func setIdleIcon() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Talky")
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = nil
    }

    private func setRecordingIcon() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Talky recording")
        button.image = image?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
        button.image?.isTemplate = false
    }

    private func setProcessingIcon() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Talky processing")
        button.image = image?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(paletteColors: [.systemOrange]))
        button.image?.isTemplate = false
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let toggleItem = item(
            session?.state == .recording ? "Stop Dictation" : "Start Dictation",
            #selector(menuToggle))
        toggleItem.keyEquivalent = ""
        menu.addItem(toggleItem)

        if session?.state == .processing {
            menu.addItem(item("Paste Raw Now (skip cleanup)", #selector(skipCleanupAction)))
        }

        let hotkeyItem = NSMenuItem(title: "Hotkey: \(config.hotkey)", action: nil, keyEquivalent: "")
        hotkeyItem.isEnabled = false
        menu.addItem(hotkeyItem)
        menu.addItem(.separator())

        // Quick settings
        let cleanupItem = item("Clean Up With AI", #selector(toggleCleanup))
        cleanupItem.state = config.cleanup.enabled ? .on : .off
        menu.addItem(cleanupItem)

        let modelsMenu = NSMenu()
        for provider in ProviderRegistry.allCleanupProviders(config) {
            let entry = item("\(provider.id)  (\(provider.model))", #selector(selectProvider(_:)))
            entry.representedObject = provider.id
            entry.state = provider.id == config.cleanup.provider ? .on : .off
            modelsMenu.addItem(entry)
        }
        let modelsItem = NSMenuItem(title: "Cleanup Model", action: nil, keyEquivalent: "")
        modelsItem.submenu = modelsMenu
        menu.addItem(modelsItem)

        let captionsMenu = NSMenu()
        for (title, value) in [("Off", "off"), ("Minimal (dot + timer)", "minimal"), ("Full (live text)", "full")] {
            let entry = item(title, #selector(selectCaptions(_:)))
            entry.representedObject = value
            entry.state = captions == value ? .on : .off
            captionsMenu.addItem(entry)
        }
        let captionsItem = NSMenuItem(title: "Live Captions", action: nil, keyEquivalent: "")
        captionsItem.submenu = captionsMenu
        menu.addItem(captionsItem)
        menu.addItem(.separator())

        menu.addItem(item("History…", #selector(showHistory), key: "h"))
        menu.addItem(item("Fix Last Dictation…", #selector(fixLastDictation)))
        menu.addItem(item("Add to Vocabulary…", #selector(addVocabularyAction)))
        menu.addItem(item("Transcribe File…", #selector(transcribeFile)))
        menu.addItem(item("Open Recordings Folder", #selector(openRecordings)))
        menu.addItem(.separator())

        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Open Config", #selector(openConfig)))
        menu.addItem(item("Reload Config", #selector(reloadConfigAction)))
        if config.output.paste && !Paster.canPaste {
            menu.addItem(item("⚠️ Grant Accessibility (for auto-paste)…", #selector(grantAccessibility)))
        }
        menu.addItem(.separator())
        menu.addItem(item("Quit Talky", #selector(quit), key: "q"))

        statusItem.menu = menu
    }

    @objc private func skipCleanupAction() {
        session?.skipCleanup()
    }

    @objc private func selectCaptions(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        config.output.captions = value
        try? config.save()
        syncSettingsStore()
        rebuildMenu()
    }

    // MARK: - Dictation

    private func toggle() {
        if session?.state == .recording {
            stopDictation()
        } else {
            startDictation()
        }
    }

    private func startDictation() {
        guard session == nil || session?.state == .idle, !busy else { return }
        busy = true

        sendPending = false
        lastPasteAt = nil
        let session = DictationSession(config: config)
        self.session = session
        session.onEvent = { [weak self] event in
            self?.handle(event)
        }

        playSound(.start)
        setRecordingIcon()
        if captions != "off" {
            panel.show(status: "●")
        }
        recordingStart = Date()
        recordingTimer?.invalidate()
        if captions == "minimal" {
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.session?.state == .recording,
                          let start = self.recordingStart else { return }
                    let s = Int(Date().timeIntervalSince(start))
                    self.panel.updateElapsed(String(format: "%d:%02d", s / 60, s % 60))
                }
            }
        }
        rebuildMenu()

        Task {
            await session.start()
            busy = false
            if session.state != .recording {
                // start failed; error event already shown
                self.session = nil
                setIdleIcon()
                rebuildMenu()
            }
        }
    }

    private func stopDictation() {
        guard let session, session.state == .recording, !busy else { return }
        busy = true
        playSound(.stop)
        setProcessingIcon()
        recordingTimer?.invalidate()
        recordingTimer = nil
        if captions != "off" {
            panel.setStatus("◐", message: "Finalizing…")
        }

        Task {
            await session.stop()
            busy = false
        }
    }

    private func handle(_ event: DictationSession.Event) {
        switch event {
        case .stateChanged:
            rebuildMenu()

        case .liveText(let finalized, let volatile):
            guard session?.state == .recording, captions == "full" else { return }
            panel.update(finalized: finalized, volatile: volatile)

        case .audioLevel(let level):
            guard captions != "off" else { return }
            panel.pushLevel(level)

        case .cleaningStarted:
            rebuildMenu() // adds "Paste Raw Now"
            if captions != "off" {
                panel.showProcessing(message: "Cleaning up…")
            }

        case .result(let text, _):
            session = nil
            setIdleIcon()
            rebuildMenu()
            defer { playSound(.done) }

            guard !text.isEmpty else {
                panel.setStatus("○", message: "Heard nothing.")
                hidePanelSoon(after: 1.2)
                return
            }
            if config.output.paste {
                let sendNow = config.output.autoEnter || sendPending
                sendPending = false
                let pasted = Paster.deliver(
                    text, restoreClipboard: config.output.restoreClipboard,
                    thenReturn: sendNow, commandReturn: commandReturn)
                if pasted {
                    lastPasteAt = Date()
                    let offerSend = config.gesture.enabled && config.gesture.tapToEnter && !sendNow
                    panel.setStatus("✓", message: sendNow ? "Sent ↩" : offerSend ? "↩ tap to send" : snippet(text))
                    hidePanelSoon(after: offerSend ? sendWindow : 1.5)
                } else {
                    panel.setStatus("✓", message: "Copied — grant Accessibility for auto-paste")
                    hidePanelSoon(after: 1.5)
                }
            } else {
                Paster.deliver(text, restoreClipboard: false)
                panel.setStatus("✓", message: "Copied: " + snippet(text))
                hidePanelSoon(after: 1.5)
            }

        case .error(let message):
            NSLog("Talky: \(message)")
            if session?.state != .recording {
                session = nil
                setIdleIcon()
                rebuildMenu()
                panel.setStatus("✕", message: message)
                hidePanelSoon(after: 3)
            }
        }
    }

    private func snippet(_ text: String) -> String {
        text.count > 80 ? String(text.prefix(80)) + "…" : text
    }

    private var hideGeneration = 0
    private func hidePanelSoon(after seconds: TimeInterval) {
        hideGeneration += 1
        let generation = hideGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.hideGeneration == generation,
                  self.session?.state != .recording else { return }
            self.panel.hide()
        }
    }

    private enum ChimeKind { case start, stop, done }
    private func playSound(_ kind: ChimeKind) {
        guard config.output.sounds else { return }
        switch kind {
        case .start: Chime.shared.start()
        case .stop: Chime.shared.stop()
        case .done: Chime.shared.done()
        }
    }

    // MARK: - Menu actions

    @objc private func menuToggle() { toggle() }

    @objc private func toggleCleanup() {
        config.cleanup.enabled.toggle()
        try? config.save()
        syncSettingsStore()
        rebuildMenu()
    }

    @objc private func selectProvider(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        config.cleanup.provider = id
        try? config.save()
        syncSettingsStore()
        rebuildMenu()
    }

    @objc private func transcribeFile() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.audio, .movie, .mpeg4Movie, .quickTimeMovie, .mp3, .wav]
        openPanel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard openPanel.runModal() == .OK, let url = openPanel.url else { return }

        panel.show(status: "◐")
        panel.setStatus("◐", message: "Transcribing \(url.lastPathComponent)…")
        setProcessingIcon()

        let cfg = config
        Task {
            do {
                let result = try await FileTranscription.transcribe(url: url, config: cfg, clean: true)
                let text = result.bestText
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
                panel.setStatus("✓", message: "Copied transcript (\(text.count) chars): " + snippet(text))
            } catch {
                panel.setStatus("✕", message: "Failed: \(error.localizedDescription)")
            }
            setIdleIcon()
            hidePanelSoon(after: 3)
        }
    }

    @objc private func showHistory() {
        historyPanel.toggle()
    }

    @objc private func addVocabularyAction() {
        let alert = NSAlert()
        alert.messageText = "Add to Vocabulary"
        alert.informativeText = "A term, optionally with its mishearings:\n\"Claude Cowork = cloud cork, cloud cowork\""
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn,
              let entry = TalkyConfig.vocabularyEntry(from: field.stringValue) else { return }
        config.addVocabulary([entry])
        try? config.save()
        panel.setStatus("✓", message: "Learned: \(entry)")
        hidePanelSoon(after: 2)
    }

    /// Edit the last dictation; a local model diffs your edits against the
    /// original and learns any name/term corrections automatically.
    @objc private func fixLastDictation() {
        guard let last = DictationHistory.last(1).first else { NSSound.beep(); return }
        let original = last.cleaned

        let alert = NSAlert()
        alert.messageText = "Fix Last Dictation"
        alert.informativeText = "Correct the text; Talky learns misheard names/terms from your edits and copies the fixed text."
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 140))
        let textView = NSTextView(frame: scroll.bounds)
        textView.string = original
        textView.font = .systemFont(ofSize: 13)
        textView.isRichText = false
        textView.autoresizingMask = [.width]
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        alert.accessoryView = scroll
        alert.addButton(withTitle: "Save & Learn")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = textView
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let corrected = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !corrected.isEmpty else { return }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(corrected, forType: .string)

        guard corrected != original else { return }
        if let dir = RecordingStore.sessions(limit: 1).first?.dir {
            RecordingStore.saveRevision(corrected, in: dir)
        }
        panel.setStatus("◐", message: "Learning from your edits…")
        let cfg = config
        Task {
            let entries = (try? await TalkyKit.extractVocabulary(
                original: original, corrected: corrected, config: cfg)) ?? []
            if !entries.isEmpty {
                config.addVocabulary(entries)
                try? config.save()
                panel.setStatus("✓", message: "Learned: " + entries.joined(separator: "; "))
            } else {
                panel.setStatus("✓", message: "Corrected text copied (no new terms)")
            }
            hidePanelSoon(after: 3)
        }
    }

    @objc private func openRecordings() {
        try? FileManager.default.createDirectory(
            at: RecordingStore.baseDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(RecordingStore.baseDir)
    }

    @objc private func openSettings() {
        if settingsController == nil {
            let store = ConfigStore(config: config)
            store.onChange = { [weak self] newConfig in
                guard let self, self.config != newConfig else { return }
                let gestureChanged = self.config.gesture != newConfig.gesture
                self.config = newConfig
                self.hotKey = nil
                self.registerHotkey()
                if gestureChanged { self.applyGestureConfig() }
                self.rebuildMenu()
            }
            settingsController = SettingsWindowController(store: store)
        }
        syncSettingsStore()
        settingsController?.show()
    }

    /// Keeps the settings window's model current after menu-driven changes.
    private func syncSettingsStore() {
        if let controller = settingsController, controller.store.config != config {
            controller.store.config = config
        }
    }

    @objc private func openConfig() {
        _ = TalkyConfig.load() // ensure file exists
        NSWorkspace.shared.open(TalkyConfig.fileURL)
    }

    @objc private func reloadConfigAction() { reloadConfig() }

    private func reloadConfig() {
        config = TalkyConfig.load()
        hotKey = nil
        registerHotkey()
        applyGestureConfig()
        rebuildMenu()
    }

    @objc private func grantAccessibility() {
        Paster.requestAccessibility()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
