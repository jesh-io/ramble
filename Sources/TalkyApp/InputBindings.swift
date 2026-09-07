import AppKit
import Carbon.HIToolbox
import TalkyCore

/// Turns the config's `bindings` into live triggers: keyboard shortcuts
/// (with press/release for hold mode), mouse buttons via a CGEvent tap
/// (so bound clicks can be swallowed), and modifier-key taps/holds via a
/// global flagsChanged monitor.
@MainActor
final class BindingManager {
    var onToggle: (() -> Void)?
    var onStart: (() -> Void)?
    var onStop: (() -> Void)?

    private var hotKeys: [HotKey] = []
    private var mouseTap: MouseButtonTap?
    private var modifierMonitor: ModifierTapMonitor?

    func apply(_ bindings: [InputBinding]) {
        hotKeys = []
        mouseTap?.stop()
        mouseTap = nil
        modifierMonitor?.stop()
        modifierMonitor = nil

        for binding in bindings where binding.type == "hotkey" {
            guard let spec = binding.keys, !spec.isEmpty else { continue }
            let hold = binding.mode == "hold"
            if let hk = HotKey(
                spec: spec,
                onPress: { [weak self] in
                    Task { @MainActor in hold ? self?.onStart?() : self?.onToggle?() }
                },
                onRelease: hold ? { [weak self] in Task { @MainActor in self?.onStop?() } } : nil
            ) {
                hotKeys.append(hk)
            } else {
                NSLog("Talky: could not register hotkey '\(spec)'")
            }
        }

        let mouse = bindings.filter { $0.type == "mouse" && $0.button != nil }
        if !mouse.isEmpty {
            mouseTap = MouseButtonTap(bindings: mouse) { [weak self] binding, down in
                Task { @MainActor in
                    guard let self else { return }
                    if binding.mode == "hold" {
                        down ? self.onStart?() : self.onStop?()
                    } else if down {
                        self.onToggle?()
                    }
                }
            }
            mouseTap?.start()
        }

        let mods = bindings.filter { $0.type == "modifier" && $0.modifierKey != nil }
        if !mods.isEmpty {
            modifierMonitor = ModifierTapMonitor(bindings: mods) { [weak self] binding, event in
                Task { @MainActor in
                    guard let self else { return }
                    switch event {
                    case .tapped: self.onToggle?()
                    case .holdBegan: self.onStart?()
                    case .holdEnded: self.onStop?()
                    }
                }
            }
            modifierMonitor?.start()
        }
    }

    /// Human summary for the menu bar.
    static func summary(_ bindings: [InputBinding]) -> String {
        bindings.map { $0.label }.joined(separator: " · ")
    }
}

// MARK: - Mouse buttons (CGEvent tap)

final class MouseButtonTap {
    typealias Handler = (InputBinding, _ down: Bool) -> Void
    private let bindings: [InputBinding]
    private let handler: Handler
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    init(bindings: [InputBinding], handler: @escaping Handler) {
        self.bindings = bindings
        self.handler = handler
    }

    func start() {
        let mask: CGEventMask = (1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.otherMouseUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<MouseButtonTap>.fromOpaque(refcon).takeUnretainedValue()
                return tap.handle(type: type, event: event)
            },
            userInfo: refcon
        ) else {
            NSLog("Talky: could not create mouse event tap (Accessibility permission?)")
            return
        }
        self.port = port
        source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        source = nil
        port = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        let clicks = Int(event.getIntegerValueField(.mouseEventClickState))
        let flags = event.flags
        let down = type == .otherMouseDown

        for binding in bindings where binding.button == button {
            guard Self.modifiersMatch(binding.modifiers, flags) else { continue }
            let wantClicks = max(1, binding.taps)
            // For double-click bindings, only the 2nd click (and its release) count.
            if wantClicks > 1 && clicks < wantClicks { 
                return binding.swallow ? nil : Unmanaged.passUnretained(event)
            }
            handler(binding, down)
            return binding.swallow ? nil : Unmanaged.passUnretained(event)
        }
        return Unmanaged.passUnretained(event)
    }

    private static func modifiersMatch(_ required: [String], _ flags: CGEventFlags) -> Bool {
        let want: [(String, CGEventFlags)] = [
            ("cmd", .maskCommand), ("alt", .maskAlternate), ("ctrl", .maskControl), ("shift", .maskShift),
        ]
        for (name, flag) in want {
            let has = flags.contains(flag)
            if required.contains(name) != has { return false }
        }
        return true
    }
}

// MARK: - Modifier key taps / holds (flagsChanged)

final class ModifierTapMonitor {
    enum Event { case tapped, holdBegan, holdEnded }
    typealias Handler = (InputBinding, Event) -> Void

    private let bindings: [InputBinding]
    private let handler: Handler
    private var monitor: Any?

    // per-binding state
    private var downSince: [String: Date] = [:]
    private var lastTapAt: [String: Date] = [:]
    private var tapCount: [String: Int] = [:]
    private var holding: Set<String> = []
    private var holdTimers: [String: DispatchWorkItem] = [:]

    private let holdThreshold: TimeInterval = 0.35
    private let doubleTapWindow: TimeInterval = 0.4

    init(bindings: [InputBinding], handler: @escaping Handler) {
        self.bindings = bindings
        self.handler = handler
    }

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// keyCode → (name, flag) for physical modifier keys.
    private static let keyMap: [UInt16: (String, NSEvent.ModifierFlags)] = [
        55: ("cmd", .command), 54: ("rightcmd", .command),
        58: ("alt", .option), 61: ("rightalt", .option),
        59: ("ctrl", .control), 62: ("rightctrl", .control),
        56: ("shift", .shift), 60: ("rightshift", .shift),
        63: ("fn", .function),
    ]

    private func handle(_ event: NSEvent) {
        guard let (name, flag) = Self.keyMap[event.keyCode] else { return }
        let isDown = event.modifierFlags.contains(flag)
        // Only this modifier may be active — chords are someone else's shortcut.
        let others = event.modifierFlags.intersection([.command, .option, .control, .shift, .function]).subtracting(flag)
        for binding in bindings where binding.modifierKey == name || binding.modifierKey == name.replacingOccurrences(of: "right", with: "") {
            let id = binding.id
            if isDown {
                guard others.isEmpty else { continue }
                downSince[id] = Date()
                if binding.mode == "hold" {
                    let work = DispatchWorkItem { [weak self] in
                        guard let self, self.downSince[id] != nil else { return }
                        self.holding.insert(id)
                        DispatchQueue.main.async { self.handler(binding, .holdBegan) }
                    }
                    holdTimers[id]?.cancel()
                    holdTimers[id] = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + holdThreshold, execute: work)
                }
            } else {
                holdTimers[id]?.cancel()
                let began = downSince.removeValue(forKey: id)
                if holding.contains(id) {
                    holding.remove(id)
                    handler(binding, .holdEnded)
                    continue
                }
                guard let began, Date().timeIntervalSince(began) < holdThreshold else { continue }
                // A quick tap; count toward the configured tap count.
                let now = Date()
                if let last = lastTapAt[id], now.timeIntervalSince(last) <= doubleTapWindow {
                    tapCount[id, default: 0] += 1
                } else {
                    tapCount[id] = 1
                }
                lastTapAt[id] = now
                if tapCount[id, default: 0] >= max(1, binding.taps) {
                    tapCount[id] = 0
                    lastTapAt[id] = nil
                    handler(binding, .tapped)
                }
            }
        }
    }
}
