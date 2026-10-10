import AppKit
import Foundation

/// In-app language choice. English is the default regardless of the system language;
/// the choice is applied through the app's own `AppleLanguages` default and takes effect after a restart.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case chinese = "zh-Hans"
    case system

    var id: String { rawValue }

    /// Shown in each language's own script so it is recognizable from either UI
    var title: String {
        switch self {
        case .english: return "English"
        case .chinese: return "简体中文"
        case .system: return String(localized: "Follow System")
        }
    }

    private static let key = "appLanguage"

    static var current: AppLanguage {
        UserDefaults.standard.string(forKey: key).flatMap(AppLanguage.init) ?? .english
    }

    /// Must run before any localized string is looked up (called from the App initializer)
    static func applyAtLaunch() {
        apply(current)
    }

    private static func apply(_ lang: AppLanguage) {
        let d = UserDefaults.standard
        switch lang {
        case .system: d.removeObject(forKey: "AppleLanguages")
        default: d.set([lang.rawValue], forKey: "AppleLanguages")
        }
    }

    @MainActor
    static func select(_ lang: AppLanguage) {
        guard lang != current else { return }
        UserDefaults.standard.set(lang.rawValue, forKey: key)
        apply(lang)
        let a = NSAlert()
        a.messageText = String(localized: "Restart WiFiScope to change the language?")
        a.informativeText = String(localized: "The new language will be used after the app restarts.")
        a.addButton(withTitle: String(localized: "Restart Now"))
        a.addButton(withTitle: String(localized: "Later"))
        if a.runModal() == .alertFirstButtonReturn { relaunch() }
    }

    @MainActor
    private static func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
