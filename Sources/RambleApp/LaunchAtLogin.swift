import SwiftUI
import ServiceManagement
import RambleAnalytics

/// The system is the source of truth; do not persist a second preference.
struct LaunchAtLoginToggle: View {
    @State private var status = SMAppService.mainApp.status
    @State private var errorMessage: String?

    var body: some View {
        Section("Startup") {
            Toggle("Launch Ramble at login", isOn: Binding(
                get: { status == .enabled || status == .requiresApproval },
                set: { enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                        Analytics.featureChanged(.launchAtLogin, enabled: enabled)
                        errorMessage = nil
                    } catch { errorMessage = error.localizedDescription }
                    status = SMAppService.mainApp.status
                }))
            if status == .requiresApproval {
                Text("Allow Ramble in System Settings → General → Login Items.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear { status = SMAppService.mainApp.status }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            status = SMAppService.mainApp.status
        }
    }
}
