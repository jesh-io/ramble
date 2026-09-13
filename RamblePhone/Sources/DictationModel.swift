import Foundation
import SwiftUI
import RambleCore
import RambleKit

/// Bridges DictationSession to SwiftUI, and lets the App Intent
/// (action button) start/stop dictation from outside the view.
@MainActor
final class DictationModel: ObservableObject {
    static let shared = DictationModel()

    @Published var state: DictationSession.State = .idle
    @Published var liveText = ""
    @Published var result = ""
    @Published var errorMessage: String?
    @Published var copied = false

    private var session: DictationSession?
    private(set) var config = RambleConfig.load()

    var activeProviderID: String { config.cleanup.activeProvider?.id ?? "none" }

    func setAnalyticsEnabled(_ enabled: Bool) {
        config.analyticsEnabled = enabled
        ProductAnalytics.configure(config)
        do { try config.save() }
        catch { errorMessage = error.localizedDescription }
        objectWillChange.send()
    }

    func selectProvider(_ id: String) {
        config.cleanup.provider = id
        try? config.save()
        objectWillChange.send()
    }

    func toggle() {
        state == .recording ? stop() : start()
    }

    func start() {
        guard state == .idle else { return }
        config = RambleConfig.load()
        errorMessage = nil
        result = ""
        liveText = ""
        copied = false

        let session = DictationSession(config: config)
        self.session = session
        session.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .stateChanged(let state):
                self.state = state
            case .liveText(let finalized, let volatile):
                self.liveText = finalized + (volatile.isEmpty ? "" : " " + volatile)
            case .result(let text, _):
                self.result = text
                self.session = nil
                if !text.isEmpty {
                    UIPasteboard.general.string = text
                    self.copied = true
                }
            case .error(let message):
                self.errorMessage = message
                if self.state != .recording { self.session = nil }
            }
        }
        Task { await session.start() }
    }

    func stop() {
        guard let session, state == .recording else { return }
        Task { await session.stop() }
    }
}
