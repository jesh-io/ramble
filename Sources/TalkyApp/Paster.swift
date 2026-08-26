import AppKit
import Carbon.HIToolbox

/// Delivers finished text into the frontmost app: clipboard + synthesized
/// ⌘V, then restores the previous clipboard. Falls back to clipboard-only
/// when Accessibility permission is missing.
enum Paster {
    static var canPaste: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user for Accessibility permission (once).
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Returns true if the text was pasted, false if only copied.
    @discardableResult
    static func deliver(_ text: String, restoreClipboard: Bool) -> Bool {
        let pasteboard = NSPasteboard.general
        let previous = restoreClipboard ? pasteboard.string(forType: .string) : nil

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard canPaste else { return false }

        // Small delay so the pasteboard write settles before ⌘V lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            sendCmdV()
            if let previous {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    let pb = NSPasteboard.general
                    // Only restore if our text is still there (don't stomp
                    // something the user copied in the meantime).
                    if pb.string(forType: .string) == text {
                        pb.clearContents()
                        pb.setString(previous, forType: .string)
                    }
                }
            }
        }
        return true
    }

    private static func sendCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(kVK_ANSI_V)
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
