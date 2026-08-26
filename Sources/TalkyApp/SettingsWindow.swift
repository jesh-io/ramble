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

// MARK: - Accounts (bespoke design)

/// Wraps chips onto lines, like tag layouts.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Warm identity tile for an integration.
private struct ProviderTile: View {
    let pluginID: String
    var size: CGFloat = 34

    private var style: (symbol: String, tint: Color) {
        switch pluginID {
        case "anthropic":  ("sparkle", Color(red: 0.80, green: 0.42, blue: 0.25))   // clay
        case "openai":     ("brain", Color(red: 0.16, green: 0.55, blue: 0.51))
        case "groq":       ("bolt.fill", Color(red: 0.85, green: 0.33, blue: 0.31))
        case "openrouter": ("arrow.triangle.branch", Color(red: 0.35, green: 0.42, blue: 0.75))
        case "mistral":    ("wind", Color(red: 0.90, green: 0.55, blue: 0.15))
        case "together":   ("person.2.fill", Color(red: 0.30, green: 0.45, blue: 0.85))
        case "deepseek":   ("magnifyingglass", Color(red: 0.30, green: 0.35, blue: 0.80))
        case "xai":        ("x.circle", Color(white: 0.25))
        case "ollama":     ("shippingbox.fill", Color(red: 0.45, green: 0.40, blue: 0.75))
        case "lmstudio":   ("desktopcomputer", Color(red: 0.40, green: 0.50, blue: 0.70))
        case "vllm":       ("server.rack", Color(red: 0.55, green: 0.45, blue: 0.40))
        case "apple":      ("apple.logo", Color(white: 0.30))
        case "mlx":        ("cpu.fill", Color(red: 0.50, green: 0.55, blue: 0.60))
        default:           ("key.fill", .accentColor)
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(style.tint.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: style.symbol)
                    .font(.system(size: size * 0.44, weight: .medium))
                    .foregroundStyle(.white)
            }
            .shadow(color: style.tint.opacity(0.3), radius: 3, y: 1)
    }
}

/// Named API keys per integration. Each account exposes its allowed models
/// as selectable cleanup providers ("account-id/model").
private struct AccountsTab: View {
    @ObservedObject var store: ConfigStore
    @State private var expanded: String?
    @State private var customModel = ""

    private var cleanupPlugins: [ProviderPlugin] {
        ProviderRegistry.all.filter { $0.kind == .cleanup && $0.available }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if store.config.accounts.isEmpty {
                    emptyState
                } else {
                    ForEach(store.config.accounts.indices, id: \.self) { index in
                        accountCard(index)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("API Accounts")
                    .font(.title3.weight(.semibold))
                Text("Name your keys per integration — work, personal, a proxy. Every enabled account's models join the Cleanup Model menus.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Menu {
                ForEach(cleanupPlugins, id: \.id) { plugin in
                    Button {
                        addAccount(plugin)
                    } label: {
                        Text(plugin.name)
                    }
                }
            } label: {
                Label("Add Account", systemImage: "plus")
            }
            .fixedSize()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "key.radiowaves.forward")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text("No accounts yet")
                .font(.headline)
            Text("Local models (Ollama, Apple Intelligence) work without one.\nAdd an account to unlock remote models like Claude or GPT.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07))
            }
    }

    // MARK: Card

    @ViewBuilder
    private func accountCard(_ index: Int) -> some View {
        if store.config.accounts.indices.contains(index) {
            let account = store.config.accounts[index]
            let plugin = ProviderRegistry.plugin(id: account.provider)
            let isOpen = expanded == account.id

            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 11) {
                    ProviderTile(pluginID: account.provider)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.id)
                            .font(.body.weight(.semibold))
                        Text(plugin?.name ?? account.provider)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    keyPill(account, plugin: plugin)
                    Toggle("", isOn: $store.config.accounts[index].enabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(14)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.snappy(duration: 0.22)) {
                        expanded = isOpen ? nil : account.id
                    }
                }

                if isOpen {
                    Divider().padding(.horizontal, 14)
                    cardBody(index, plugin: plugin)
                        .padding(14)
                        .transition(.opacity)
                }
            }
            .background(cardBackground)
            .opacity(account.enabled ? 1 : 0.6)
        }
    }

    private func cardBody(_ index: Int, plugin: ProviderPlugin?) -> some View {
        let binding = $store.config.accounts[index]
        return Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 12) {
            GridRow {
                fieldLabel("Name")
                TextField("account name", text: binding.id)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                    .gridCellAnchor(.leading)
            }
            if plugin?.apiKeyRequired ?? true {
                GridRow {
                    fieldLabel("API key")
                    HStack(spacing: 8) {
                        TextField(plugin?.keyEnvSuggestion ?? "ENV_VAR_NAME", text: optionalBinding(binding.apiKeyEnv))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 240)
                        Text("env var")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .gridCellAnchor(.leading)
                }
            }
            GridRow {
                fieldLabel("Endpoint")
                TextField(plugin?.defaultBaseURL ?? "https://…", text: optionalBinding(binding.baseURL))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 340)
                    .gridCellAnchor(.leading)
            }
            GridRow {
                fieldLabel("Models")
                modelChips(index, plugin: plugin)
                    .gridCellAnchor(.leading)
            }
            GridRow {
                fieldLabel("Temperature")
                HStack(spacing: 8) {
                    TextField("auto", value: binding.temperature, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .monospacedDigit()
                        .frame(width: 68)
                    Text("blank = model default")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .gridCellAnchor(.leading)
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Button(role: .destructive) {
                    withAnimation(.snappy) {
                        let id = store.config.accounts[index].id
                        store.config.accounts.remove(at: index)
                        if expanded == id { expanded = nil }
                    }
                } label: {
                    Label("Remove Account", systemImage: "trash")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .gridCellAnchor(.leading)
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    /// Catalog models as tappable chips. No selection = full catalog.
    private func modelChips(_ index: Int, plugin: ProviderPlugin?) -> some View {
        let account = store.config.accounts[index]
        let catalog = plugin?.models.map(\.id) ?? []
        let extras = account.models.filter { !catalog.contains($0) }

        return VStack(alignment: .leading, spacing: 8) {
            if !catalog.isEmpty || !extras.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(catalog + extras, id: \.self) { model in
                        chip(model, index: index, isCustom: !catalog.contains(model))
                    }
                }
            }
            HStack(spacing: 6) {
                TextField("add a model id…", text: $customModel)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                    .onSubmit { addCustomModel(index) }
                Button {
                    addCustomModel(index)
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(customModel.isEmpty)
            }
            Text(account.models.isEmpty
                 ? "Using the full catalog — tap models to restrict."
                 : "\(account.models.count) selected.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func chip(_ model: String, index: Int, isCustom: Bool) -> some View {
        let account = store.config.accounts[index]
        let selected = account.models.contains(model)
        let fullCatalog = account.models.isEmpty

        return Button {
            withAnimation(.snappy(duration: 0.15)) {
                if selected {
                    store.config.accounts[index].models.removeAll { $0 == model }
                } else {
                    store.config.accounts[index].models.append(model)
                }
            }
        } label: {
            HStack(spacing: 4) {
                if selected || fullCatalog {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                }
                Text(model)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background {
                Capsule()
                    .fill(selected ? Color.accentColor
                          : fullCatalog ? Color.accentColor.opacity(0.14)
                          : Color.primary.opacity(0.06))
            }
            .foregroundStyle(selected ? .white : fullCatalog ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .help(isCustom ? "Custom model" : "Catalog model")
    }

    private func addCustomModel(_ index: Int) {
        let model = customModel.trimmingCharacters(in: .whitespaces)
        guard !model.isEmpty else { return }
        if !store.config.accounts[index].models.contains(model) {
            store.config.accounts[index].models.append(model)
        }
        customModel = ""
    }

    private func keyPill(_ account: APIAccount, plugin: ProviderPlugin?) -> some View {
        Group {
            if let plugin, plugin.apiKeyRequired {
                let env = account.apiKeyEnv ?? plugin.keyEnvSuggestion ?? ""
                let present = !env.isEmpty && ProcessInfo.processInfo.environment[env]?.isEmpty == false
                Label(present ? "key found" : "no key", systemImage: present ? "checkmark" : "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(present ? Color.green.opacity(0.15) : Color.orange.opacity(0.15)))
                    .foregroundStyle(present ? .green : .orange)
            }
        }
    }

    private func optionalBinding(_ source: Binding<String?>) -> Binding<String> {
        Binding(
            get: { source.wrappedValue ?? "" },
            set: { source.wrappedValue = $0.isEmpty ? nil : $0 })
    }

    private func addAccount(_ plugin: ProviderPlugin) {
        var id = plugin.id
        var n = 2
        while store.config.accounts.contains(where: { $0.id == id }) {
            id = "\(plugin.id)-\(n)"
            n += 1
        }
        withAnimation(.snappy) {
            store.config.accounts.append(APIAccount(
                id: id, provider: plugin.id, apiKeyEnv: plugin.keyEnvSuggestion))
            expanded = id
        }
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
