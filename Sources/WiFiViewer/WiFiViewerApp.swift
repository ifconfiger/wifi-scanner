import SwiftUI

@main
struct WiFiViewerApp: App {
    #if !APPSTORE
    @StateObject private var updater = UpdateChecker.shared
    #endif
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
        WindowGroup("WiFi-Viewer") {
            ContentView()
                .frame(minWidth: 1200, minHeight: 760)
                #if !APPSTORE
                .onAppear { updater.checkOnLaunch() }
                #endif
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                #if !APPSTORE
                Button("Check for Updates…") {
                    Task { await updater.check(userInitiated: true) }
                }
                .disabled(updater.isChecking || updater.isInstalling)
                Toggle("Automatically Check for Updates", isOn: $updater.autoCheck)
                Divider()
                #endif
                Picker("Language", selection: $language) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: language) { AppLanguage.select($0) }
            }
        }
    }
}
