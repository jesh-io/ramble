import SwiftUI
import TalkyClean

@main
struct TalkyPhoneApp: App {
    init() {
        // Make on-device MLX models available as a cleanup engine
        // ("engine": "mlx" in config providers).
        MLXQwenCleaner.register()
    }

    var body: some Scene {
        WindowGroup {
            DictationView()
        }
    }
}
