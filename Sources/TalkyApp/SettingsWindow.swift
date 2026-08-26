import SwiftUI
import TalkyCore

/// Observable wrapper around TalkyConfig: every mutation persists to disk
/// and notifies the app so hotkey/menu/state stay current.
@MainActor
final class ConfigStore: ObservableObject {
    @Published var config: TalkyConfig {
        didSet {
            try? config.save()
            onChange?(config)
        }
    }
    var onChange: ((TalkyConfig) -> Void)?

    init(config: TalkyConfig) {
        self.config = config
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    let store: ConfigStore

    init(store: ConfigStore) {
        self.store = store
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(store: store))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Talky Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 640, height: 520))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var store: ConfigStore

    var body: some View {
        TabView {
            GeneralTab(store: store)
                .tabItem { Label("General", systemImage: "gearshape") }
            CleanupTab(store: store)
                .tabItem { Label("Cleanup", systemImage: "sparkles") }
            VocabularyTab(store: store)
                .tabItem { Label("Vocabulary", systemImage: "character.book.closed") }
            StorageTab(store: store)
                .tabItem { Label("Storage", systemImage: "internaldrive") }
        }
        .frame(width: 640, height: 520)
    }
}

private struct GeneralTab: View {
    @ObservedObject var store: ConfigStore

    var body: some View {
        Form {
            Section("Dictation") {
                TextField("Global hotkey", text: $store.config.hotkey)
                Text("e.g. ctrl+alt+cmd+d · cmd+shift+space · f13 — applied immediately")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Speech locale", text: $store.config.locale)
                Picker("Live captions", selection: $store.config.output.captions) {
                    Text("Off — menu bar icon only").tag("off")
                    Text("Minimal — dot, voice meter, timer").tag("minimal")
                    Text("Full — streaming text").tag("full")
                }
            }
            Section("Output") {
                Toggle("Paste into the frontmost app", isOn: $store.config.output.paste)
                Toggle("Restore previous clipboard after pasting", isOn: $store.config.output.restoreClipboard)
                Toggle("Start/stop sounds", isOn: $store.config.output.sounds)
            }
        }
        .formStyle(.grouped)
    }
}

private struct CleanupTab: View {
    @ObservedObject var store: ConfigStore

    var body: some View {
        Form {
            Section {
                Toggle("Clean up transcripts with AI", isOn: $store.config.cleanup.enabled)
                Picker("Active model", selection: $store.config.cleanup.provider) {
                    ForEach(store.config.cleanup.providers, id: \.id) { provider in
                        Text("\(provider.id) — \(provider.model)").tag(provider.id)
                    }
                }
                HStack {
                    Text("Timeout")
                    Spacer()
                    TextField("", value: $store.config.cleanup.timeoutSeconds, format: .number)
                        .frame(width: 70).multilineTextAlignment(.trailing)
                    Text("s").foregroundStyle(.secondary)
                }
            }
            Section("Providers") {
                ForEach($store.config.cleanup.providers, id: \.id) { $provider in
                    DisclosureGroup("\(provider.id)") {
                        TextField("Model", text: $provider.model)
                        TextField("Base URL", text: $provider.baseURL)
                        TextField("API key env var (optional)", text: Binding(
                            get: { provider.apiKeyEnv ?? "" },
                            set: { provider.apiKeyEnv = $0.isEmpty ? nil : $0 }))
                        HStack {
                            Text("Cost $/M tokens")
                            Spacer()
                            TextField("in", value: Binding(
                                get: { provider.inputCostPerMTok ?? 0 },
                                set: { provider.inputCostPerMTok = $0 == 0 ? nil : $0 }),
                                format: .number)
                                .frame(width: 64)
                            TextField("out", value: Binding(
                                get: { provider.outputCostPerMTok ?? 0 },
                                set: { provider.outputCostPerMTok = $0 == 0 ? nil : $0 }),
                                format: .number)
                                .frame(width: 64)
                        }
                    }
                }
                Text("Any OpenAI-compatible endpoint works (Ollama, LM Studio, OpenAI, Groq, …). Add providers by editing the config file for now.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("System Prompt") {
                TextEditor(text: $store.config.cleanup.systemPrompt)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minHeight: 130)
            }
        }
        .formStyle(.grouped)
    }
}

private struct VocabularyTab: View {
    @ObservedObject var store: ConfigStore
    @State private var newEntry = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Claude Cowork = cloud cork, cloud cowork", text: $newEntry)
                        .onSubmit(add)
                    Button("Add", action: add).disabled(newEntry.isEmpty)
                }
                Text("Term, optionally with mishearings after \"=\". Listed mishearings are fixed deterministically; the term itself also biases speech recognition and the cleanup model.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Entries (\(store.config.vocabulary.count))") {
                ForEach(store.config.vocabulary, id: \.self) { entry in
                    HStack {
                        Text(entry).lineLimit(2)
                        Spacer()
                        Button {
                            store.config.vocabulary.removeAll { $0 == entry }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func add() {
        guard let entry = TalkyConfig.vocabularyEntry(from: newEntry) else { return }
        store.config.addVocabulary([entry])
        newEntry = ""
    }
}

private struct StorageTab: View {
    @ObservedObject var store: ConfigStore

    var body: some View {
        Form {
            Section("Recordings") {
                Toggle("Save audio + transcript for every dictation", isOn: $store.config.recordings.enabled)
                HStack {
                    Text("Keep audio for")
                    Spacer()
                    TextField("", value: $store.config.recordings.retentionHours, format: .number)
                        .frame(width: 70).multilineTextAlignment(.trailing)
                    Text("hours (0 = forever)").foregroundStyle(.secondary)
                }
                Button("Open Recordings Folder") {
                    try? FileManager.default.createDirectory(
                        at: RecordingStore.baseDir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(RecordingStore.baseDir)
                }
            }
            Section("Files") {
                LabeledContent("Config", value: TalkyConfig.fileURL.path)
                LabeledContent("Usage ledger", value: UsageLog.fileURL.path)
                LabeledContent("History", value: DictationHistory.fileURL.path)
                Button("Reveal Config in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([TalkyConfig.fileURL])
                }
            }
        }
        .formStyle(.grouped)
    }
}
