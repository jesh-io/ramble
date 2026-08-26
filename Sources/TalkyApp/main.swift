import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Keep the delegate alive for the app's lifetime.
    objc_setAssociatedObject(app, "talkyDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
    app.run()
}
