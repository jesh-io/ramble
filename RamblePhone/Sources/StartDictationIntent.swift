import AppIntents
import SwiftUI

/// Exposed to Shortcuts/the Action button: opens Ramble and immediately
/// starts (or stops) dictation. Map the Action button to this via
/// Settings → Action Button → Shortcut → "Toggle Ramble Dictation".
struct StartDictationIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Ramble Dictation"
    static let description = IntentDescription(
        "Starts push-to-talk dictation; if already recording, stops and copies the cleaned text to the clipboard.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DictationModel.shared.toggle()
        return .result()
    }
}

import RambleCore
import RambleKit

/// Runs entirely in the background — no app switch. Chain it in Shortcuts:
/// Action button → "Dictate Text" (Apple's overlay dictation) →
/// "Clean Dictated Text" → "Copy to Clipboard".
struct CleanTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Clean Dictated Text"
    static let description = IntentDescription(
        "Cleans up raw dictated text (removes filler, fixes punctuation, applies your vocabulary) and returns the polished text. Runs in the background.")

    @Parameter(title: "Text") var text: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let config = RambleConfig.load()
        let cleaned = (try? await RambleKit.cleanText(text, config: config))
            ?? SpokenCommands.apply(to: text)
        return .result(value: cleaned)
    }
}

struct RambleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartDictationIntent(),
            phrases: ["Start \(.applicationName) dictation", "\(.applicationName) dictate"],
            shortTitle: "Dictate",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: CleanTextIntent(),
            phrases: ["Clean text with \(.applicationName)"],
            shortTitle: "Clean Text",
            systemImageName: "sparkles"
        )
    }
}
