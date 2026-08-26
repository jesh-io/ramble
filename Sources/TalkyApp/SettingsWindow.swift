import SwiftUI
import TalkyCore
import TalkyProviders

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

/// Native preferences window: toolbar-style tabs (à la Safari/Xcode
/// settings), window title tracks the selected tab, window animates to
/// each tab's natural size.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    let store: ConfigStore

    init(store: ConfigStore) {
        self.store = store
    }

    private func makeWindow() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.canPropagateSelectedChildViewControllerTitle = true

        func add(_ title: String, _ symbol: String, _ view: some View) {
            let hosting = NSHostingController(rootView: view)
            hosting.title = title
            hosting.sizingOptions = .preferredContentSize
            let item = NSTabViewItem(viewController: hosting)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }

        add("General", "gearshape", GeneralTab(store: store).frame(width: 620))
        add("Cleanup", "sparkles", CleanupTab(store: store).frame(width: 620, height: 640))
        add("Accounts", "key", AccountsTab(store: store).frame(width: 620, height: 560))
        add("Vocabulary", "character.book.closed", VocabularyTab(store: store).frame(width: 620, height: 480))
        add("Storage", "internaldrive", StorageTab(store: store).frame(width: 620))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.titlebarSeparatorStyle = .automatic
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    func show() {
        if window == nil {
            window = makeWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
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
                    ForEach(ProviderRegistry.allCleanupProviders(store.config), id: \.id) { provider in
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

/// Named API keys per integration. Each account exposes its allowed models
/// as selectable cleanup providers ("account-id/model").
private struct AccountsTab: View {
    @ObservedObject var store: ConfigStore
    @State private var newProvider = "anthropic"

    private var cleanupPlugins: [ProviderPlugin] {
        ProviderRegistry.all.filter { $0.kind == .cleanup && $0.available }
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Picker("Integration", selection: $newProvider) {
                        ForEach(cleanupPlugins, id: \.id) { plugin in
                            Text(plugin.name).tag(plugin.id)
                        }
                    }
                    Button("Add Account") { addAccount() }
                }
                Text("One integration can have many keys — work, personal, a proxy — each with its own models, parameters, and cost rates. Enabled accounts' models appear in the Cleanup Model menus.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Accounts (\(store.config.accounts.count))") {
                ForEach($store.config.accounts, id: \.id) { $account in
                    DisclosureGroup {
                        TextField("Name", text: $account.id)
                        Toggle("Enabled", isOn: $account.enabled)
                        TextField("API key env var", text: Binding(
                            get: { account.apiKeyEnv ?? "" },
                            set: { account.apiKeyEnv = $0.isEmpty ? nil : $0 }))
                        keyStatus(account)
                        TextField("Base URL override (optional)", text: Binding(
                            get: { account.baseURL ?? "" },
                            set: { account.baseURL = $0.isEmpty ? nil : $0 }))
                        TextField("Models (comma-separated; empty = full catalog)", text: Binding(
                            get: { account.models.joined(separator: ", ") },
                            set: { account.models = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }))
                        if let plugin = ProviderRegistry.plugin(id: account.provider), !plugin.models.isEmpty {
                            Text("Catalog: " + plugin.models.map(\.id).joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Temperature")
                            Spacer()
                            TextField("default", value: $account.temperature, format: .number)
                                .frame(width: 70)
                        }
                        Button("Remove Account", role: .destructive) {
                            store.config.accounts.removeAll { $0.id == account.id }
                        }
                    } label: {
                        HStack {
                            Text(account.id)
                            Text(ProviderRegistry.plugin(id: account.provider)?.name ?? account.provider)
                                .foregroundStyle(.secondary)
                            if !account.enabled {
                                Text("disabled").font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                }
                if store.config.accounts.isEmpty {
                    Text("No accounts yet. Local integrations (Ollama, Apple Intelligence) work without one.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func keyStatus(_ account: APIAccount) -> some View {
        if let plugin = ProviderRegistry.plugin(id: account.provider), plugin.apiKeyRequired {
            let env = account.apiKeyEnv ?? plugin.keyEnvSuggestion ?? ""
            let present = !env.isEmpty && ProcessInfo.processInfo.environment[env]?.isEmpty == false
            Label(
                present ? "Key found in $\(env)" : "No key in $\(env) — export it or launch Talky from a shell that has it",
                systemImage: present ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(present ? .green : .orange)
        }
    }

    private func addAccount() {
        guard let plugin = ProviderRegistry.plugin(id: newProvider) else { return }
        var id = plugin.id
        var n = 2
        while store.config.accounts.contains(where: { $0.id == id }) {
            id = "\(plugin.id)-\(n)"
            n += 1
        }
        store.config.accounts.append(APIAccount(
            id: id, provider: plugin.id, apiKeyEnv: plugin.keyEnvSuggestion))
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
