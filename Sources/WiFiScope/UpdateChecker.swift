import AppKit
import Foundation
import SwiftUI

/// Checks GitHub Releases for a newer version. Releases are tagged `main-vX.Y.Z`.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    static let repo = "ifconfiger/wifi-scanner"
    private static let autoCheckKey = "autoCheckForUpdates"
    private static let lastCheckKey = "lastUpdateCheck"

    @Published private(set) var isChecking = false
    @Published var autoCheck: Bool {
        didSet { UserDefaults.standard.set(autoCheck, forKey: Self.autoCheckKey) }
    }

    private init() {
        autoCheck = UserDefaults.standard.object(forKey: Self.autoCheckKey) as? Bool ?? true
    }

    /// Version from Info.plist; nil under `swift run`, where there is no bundle to compare against
    static var currentVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// Silent check at launch, at most once a day; only speaks up when an update exists
    func checkOnLaunch() {
        guard autoCheck, Self.currentVersion != nil else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 24 * 3600 else { return }
        Task { await check(userInitiated: false) }
    }

    func check(userInitiated: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            let release = try await Self.fetchLatest()
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
            let current = Self.currentVersion ?? "0"
            if Self.isNewer(release.version, than: current) {
                showUpdateAlert(release, current: current)
            } else if userInitiated {
                alert(String(localized: "You're up to date"),
                      String(localized: "WiFiScope \(current) is the latest version."))
            }
        } catch {
            if userInitiated {
                alert(String(localized: "Couldn't check for updates"), error.localizedDescription)
            }
        }
    }

    // MARK: - GitHub

    struct Release: Decodable {
        let tagName: String
        let htmlURL: URL
        let body: String?
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case body, assets
        }

        var version: String {
            tagName.replacingOccurrences(of: "main-v", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        }

        var zipURL: URL? {
            assets.first { $0.name.hasSuffix(".zip") }?.browserDownloadURL
        }
    }

    private static func fetchLatest() async throws -> Release {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!,
                             timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("WiFiScope/\(currentVersion ?? "dev")", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            throw URLError(.badServerResponse, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "GitHub returned HTTP \(code).")
            ])
        }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    /// Numeric comparison of dotted versions: 0.10.0 > 0.9.1
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - Alerts

    private func showUpdateAlert(_ release: Release, current: String) {
        let a = NSAlert()
        a.messageText = String(localized: "WiFiScope \(release.version) is available")
        var info = String(localized: "You have version \(current).")
        if let notes = release.body?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            info += "\n\n" + String(notes.prefix(1200))
        }
        a.informativeText = info
        a.addButton(withTitle: String(localized: "Download"))
        a.addButton(withTitle: String(localized: "View Release"))
        a.addButton(withTitle: String(localized: "Later"))
        switch a.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(release.zipURL ?? release.htmlURL)
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(release.htmlURL)
        default:
            break
        }
    }

    private func alert(_ title: String, _ message: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.runModal()
    }
}
