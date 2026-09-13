import Carbon.HIToolbox
import AppKit

/// Global hotkey via Carbon RegisterEventHotKey — works system-wide and,
/// unlike CGEvent taps, needs no Accessibility permission. Reports press
/// and (optionally) release so hold-to-talk works.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private let onPress: () -> Void
    private let onRelease: (() -> Void)?
    private let id: UInt32

    // One shared Carbon handler dispatches to registered hotkeys by id.
    private static var registry: [UInt32: HotKey] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerRef: EventHandlerRef?

    private static func installSharedHandler() {
        guard handlerRef == nil else { return }
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                var hkID = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
                guard let hk = HotKey.registry[hkID.id] else { return noErr }
                if GetEventKind(event) == UInt32(kEventHotKeyPressed) {
                    hk.onPress()
                } else {
                    hk.onRelease?()
                }
                return noErr
            },
            types.count, &types, nil, &handlerRef)
    }

    /// Parses specs like "ctrl+alt+cmd+d", "cmd+shift+space", "f13".
    static func parse(_ spec: String) -> (keyCode: UInt32, modifiers: UInt32)? {
        var modifiers: UInt32 = 0
        var key: String?
        for part in spec.lowercased().split(separator: "+").map(String.init) {
            switch part {
            case "cmd", "command": modifiers |= UInt32(cmdKey)
            case "ctrl", "control": modifiers |= UInt32(controlKey)
            case "alt", "opt", "option": modifiers |= UInt32(optionKey)
            case "shift": modifiers |= UInt32(shiftKey)
            default: key = part
            }
        }
        guard let key, let code = keyCodes[key] else { return nil }
        return (code, modifiers)
    }

    init?(spec: String, onPress: @escaping () -> Void, onRelease: (() -> Void)? = nil) {
        guard let (keyCode, modifiers) = Self.parse(spec) else { return nil }
        self.onPress = onPress
        self.onRelease = onRelease
        self.id = Self.nextID
        Self.nextID += 1
        Self.installSharedHandler()

        let hotKeyID = EventHotKeyID(signature: OSType(0x544C4B59) /* 'TLKY' */, id: id)
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr { return nil }
        Self.registry[id] = self
    }

    convenience init?(spec: String, handler: @escaping () -> Void) {
        self.init(spec: spec, onPress: handler, onRelease: nil)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        HotKey.registry[id] = nil
    }

    private static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37,
        "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, "`": 50,
        "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51,
        "escape": 53, "esc": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "f13": 105, "f14": 107, "f15": 113, "f16": 106, "f17": 64,
        "f18": 79, "f19": 80,
    ]
}
