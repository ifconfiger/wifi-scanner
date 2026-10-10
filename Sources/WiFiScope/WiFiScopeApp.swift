import SwiftUI

@main
struct WiFiScopeApp: App {
    @StateObject private var updater = UpdateChecker.shared
    @State private var language = AppLanguage.current

    init() {
        AppLanguage.applyAtLaunch()
    }

    var body: some Scene {
        WindowGroup("WiFiScope") {
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
                .disabled(updater.isChecking || updater.isDownloading)
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
