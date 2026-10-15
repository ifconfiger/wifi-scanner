import AppKit
import Foundation

/// In-app language choice. Follows the system language by default (falling back to English);
/// an explicit choice is applied through the app's own `AppleLanguages` default and takes effect after a restart.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case german = "de"
    case french = "fr"
    case spanish = "es"
    case portuguese = "pt-BR"
    case italian = "it"
    case russian = "ru"

    var id: String { rawValue }

    /// Shown in each language's own script so it is recognizable from either UI
    var title: String {
        switch self {
        case .system: return String(localized: "Follow System")
        case .english: return "English"
        case .chineseSimplified: return "简体中文"
        case .chineseTraditional: return "繁體中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .german: return "Deutsch"
        case .french: return "Français"
        case .spanish: return "Español"
        case .portuguese: return "Português (Brasil)"
        case .italian: return "Italiano"
        case .russian: return "Русский"
        }
    }

    private static let key = "appLanguage"

    static var current: AppLanguage {
        UserDefaults.standard.string(forKey: key).flatMap(AppLanguage.init) ?? .system
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
        a.messageText = String(localized: "Restart WiFi-Viewer to change the language?")
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
