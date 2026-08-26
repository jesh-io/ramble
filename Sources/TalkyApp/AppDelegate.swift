import AppKit
import TalkyCore
import TalkyKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private let panel = LivePanel()
    private let historyPanel = HistoryPanel()

    private var config = TalkyConfig.load()
    private var session: DictationSession?
    private var busy = false

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setIdleIcon()
        rebuildMenu()
        registerHotkey()
        observeCLICommands()

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

    private func rebuildMenu() {
        let menu = NSMenu()

        let toggleItem = NSMenuItem(
            title: "Start Dictation", action: #selector(menuToggle), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.title = session?.state == .recording ? "Stop Dictation" : "Start Dictation"
        menu.addItem(toggleItem)
        menu.addItem(NSMenuItem(title: "Hotkey: \(config.hotkey)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        let cleanupItem = NSMenuItem(
            title: "Clean Up With AI", action: #selector(toggleCleanup), keyEquivalent: "")
        cleanupItem.target = self
        cleanupItem.state = config.cleanup.enabled ? .on : .off
        menu.addItem(cleanupItem)

        let modelsMenu = NSMenu()
        for provider in config.cleanup.providers {
            let item = NSMenuItem(
                title: "\(provider.id)  (\(provider.model))",
                action: #selector(selectProvider(_:)),
                keyEquivalent: "")
            item.target = self
            item.representedObject = provider.id
            item.state = provider.id == config.cleanup.provider ? .on : .off
            modelsMenu.addItem(item)
        }
        let modelsItem = NSMenuItem(title: "Cleanup Model", action: nil, keyEquivalent: "")
        modelsItem.submenu = modelsMenu
        menu.addItem(modelsItem)
        menu.addItem(.separator())

        let fileItem = NSMenuItem(
            title: "Transcribe File…", action: #selector(transcribeFile), keyEquivalent: "")
        fileItem.target = self
        menu.addItem(fileItem)
        menu.addItem(.separator())

        let historyItem = NSMenuItem(
            title: "History…", action: #selector(showHistory), keyEquivalent: "h")
        historyItem.target = self
        menu.addItem(historyItem)

        let recordingsItem = NSMenuItem(
            title: "Open Recordings Folder", action: #selector(openRecordings), keyEquivalent: "")
        recordingsItem.target = self
        menu.addItem(recordingsItem)

        let configItem = NSMenuItem(
            title: "Open Config", action: #selector(openConfig), keyEquivalent: "")
        configItem.target = self
        menu.addItem(configItem)

        let reloadItem = NSMenuItem(
            title: "Reload Config", action: #selector(reloadConfigAction), keyEquivalent: "")
        reloadItem.target = self
        menu.addItem(reloadItem)

        if config.output.paste && !Paster.canPaste {
            let axItem = NSMenuItem(
                title: "⚠️ Grant Accessibility (for auto-paste)…",
                action: #selector(grantAccessibility), keyEquivalent: "")
            axItem.target = self
            menu.addItem(axItem)
        }

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Talky", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
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

        let session = DictationSession(config: config)
        self.session = session
        session.onEvent = { [weak self] event in
            self?.handle(event)
        }

        playSound("Pop")
        setRecordingIcon()
        panel.show(status: "●")
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
        setProcessingIcon()
        panel.setStatus("◐", message: config.cleanup.enabled ? "Cleaning up…" : "Finalizing…")

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
            guard session?.state == .recording else { return }
            panel.update(finalized: finalized, volatile: volatile)

        case .result(let text, _):
            session = nil
            setIdleIcon()
            rebuildMenu()
            defer { playSound("Bottle") }

            guard !text.isEmpty else {
                panel.setStatus("○", message: "Heard nothing.")
                hidePanelSoon(after: 1.2)
                return
            }
            if config.output.paste {
                let pasted = Paster.deliver(text, restoreClipboard: config.output.restoreClipboard)
                panel.setStatus("✓", message: pasted ? snippet(text) : "Copied — grant Accessibility for auto-paste")
            } else {
                Paster.deliver(text, restoreClipboard: false)
                panel.setStatus("✓", message: "Copied: " + snippet(text))
            }
            hidePanelSoon(after: 1.5)

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

    private func playSound(_ name: String) {
        guard config.output.sounds else { return }
        NSSound(named: name)?.play()
    }

    // MARK: - Menu actions

    @objc private func menuToggle() { toggle() }

    @objc private func toggleCleanup() {
        config.cleanup.enabled.toggle()
        try? config.save()
        rebuildMenu()
    }

    @objc private func selectProvider(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        config.cleanup.provider = id
        try? config.save()
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

    @objc private func openRecordings() {
        try? FileManager.default.createDirectory(
            at: RecordingStore.baseDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(RecordingStore.baseDir)
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
        rebuildMenu()
    }

    @objc private func grantAccessibility() {
        Paster.requestAccessibility()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
