import SwiftUI

@main
struct WiFiScannerApp: App {
    @StateObject private var updater = UpdateChecker.shared
    @State private var language = AppLanguage.current

    init() {
        Self.migrateLegacyDefaults()
        AppLanguage.applyAtLaunch()
    }

    /// Versions up to 0.3.0 used the bundle id com.local.wifiscope; carry their settings over once
    private static func migrateLegacyDefaults() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "migratedLegacyDefaults") else { return }
        d.set(true, forKey: "migratedLegacyDefaults")
        guard let old = UserDefaults(suiteName: "com.local.wifiscope") else { return }
        for key in ["appLanguage", "autoCheckForUpdates"] where d.object(forKey: key) == nil {
            if let v = old.object(forKey: key) { d.set(v, forKey: key) }
        }
    }

    var body: some Scene {
        WindowGroup("WiFi-Scanner") {
            ContentView()
                .frame(minWidth: 1200, minHeight: 760)
                .onAppear { updater.checkOnLaunch() }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await updater.check(userInitiated: true) }
                }
                .disabled(updater.isChecking || updater.isInstalling)
                Toggle("Automatically Check for Updates", isOn: $updater.autoCheck)
                Divider()
                Picker("Language", selection: $language) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: language) { AppLanguage.select($0) }
            }
        }
    }
}
