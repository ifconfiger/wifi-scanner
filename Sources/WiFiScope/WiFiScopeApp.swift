import SwiftUI

@main
struct WiFiScopeApp: App {
    var body: some Scene {
        WindowGroup("WiFiScope") {
            ContentView()
                .frame(minWidth: 1200, minHeight: 760)
        }
        .windowToolbarStyle(.unified)
    }
}
