// The App Store build (-DAPPSTORE) leaves out self-updating; the store delivers updates there
#if !APPSTORE
import AppKit
import Foundation
import Security
import SwiftUI

/// Checks GitHub Releases for a newer version. Releases are tagged `main-vX.Y.Z`.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    static let repo = "ifconfiger/wifi-viewer"
    private static let autoCheckKey = "autoCheckForUpdates"
    private static let lastCheckKey = "lastUpdateCheck"

    @Published private(set) var isChecking = false
    @Published private(set) var isInstalling = false
    /// Progress text shown in the status bar while an update downloads and installs
    @Published private(set) var status: String?
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
        #if DEBUG
        // `open WiFi-Viewer.app --args --debug-install-latest` installs the latest release without prompting
        if CommandLine.arguments.contains("--debug-install-latest") {
            Task { if let r = try? await Self.fetchLatest() { await install(r) } }
            return
        }
        #endif
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
                      String(localized: "WiFi-Viewer \(current) is the latest version."))
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
            case assets
        }

        var version: String {
            tagName.replacingOccurrences(of: "main-v", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        }

        var dmg: Asset? { assets.first { $0.name.hasSuffix(".dmg") } }
        var zip: Asset? { assets.first { $0.name.hasSuffix(".zip") } }
    }

    private static func fetchLatest() async throws -> Release {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!,
                             timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("WiFi-Viewer/\(currentVersion ?? "dev")", forHTTPHeaderField: "User-Agent")
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
        a.messageText = String(localized: "WiFi-Viewer \(release.version) is available")
        a.informativeText = String(localized: "You have version \(current).")
        a.addButton(withTitle: String(localized: "Install and Relaunch"))
        a.addButton(withTitle: String(localized: "View Release"))
        a.addButton(withTitle: String(localized: "Later"))
        switch a.runModal() {
        case .alertFirstButtonReturn:
            Task { await install(release) }
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

    // MARK: - Install

    enum UpdateError: LocalizedError {
        case noPackage, download, extract, invalidBundle, signature, notInstallable(URL)

        var errorDescription: String? {
            switch self {
            case .noPackage: return String(localized: "This release has no app package to install.")
            case .download: return String(localized: "The download failed.")
            case .extract: return String(localized: "The downloaded package couldn't be unpacked.")
            case .invalidBundle: return String(localized: "The downloaded app doesn't match this app's identity or version.")
            case .signature: return String(localized: "The downloaded app isn't signed by the same developer, so it was not installed.")
            case .notInstallable:
                return String(localized: "WiFi-Viewer can't replace itself in its current location. The new version is shown in Finder; move it to Applications to finish.")
            }
        }
    }

    /// Download the release zip, verify the app inside and swap it in place of the running copy, then relaunch
    private func install(_ release: Release) async {
        guard !isInstalling else { return }
        isInstalling = true
        defer {
            isInstalling = false
            status = nil
        }
        do {
            guard let asset = release.zip else { throw UpdateError.noPackage }
            let work = FileManager.default.temporaryDirectory
                .appendingPathComponent("WiFi-Viewer-update-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

            status = String(localized: "Downloading update \(release.version)…")
            let (tmp, resp) = try await URLSession.shared.download(from: asset.browserDownloadURL)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.download }
            let zip = work.appendingPathComponent("update.zip")
            try FileManager.default.moveItem(at: tmp, to: zip)

            status = String(localized: "Installing update \(release.version)…")
            let version = release.version
            let newApp = try await Task.detached { try Self.unpackAndVerify(zip, in: work, version: version) }.value
            try Self.replaceAndRelaunch(with: newApp, work: work)
        } catch UpdateError.notInstallable(let app) {
            NSWorkspace.shared.activateFileViewerSelecting([app])
            alert(String(localized: "Finish installing the update"), UpdateError.notInstallable(app).localizedDescription)
        } catch {
            alert(String(localized: "Couldn't install the update"), error.localizedDescription)
        }
    }

    /// Unzip the package and make sure it holds this app, at the expected version, signed by the same team
    private nonisolated static func unpackAndVerify(_ zip: URL, in work: URL, version: String) throws -> URL {
        let out = work.appendingPathComponent("unpacked", isDirectory: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, out.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0,
              let app = try FileManager.default.contentsOfDirectory(at: out, includingPropertiesForKeys: nil)
                  .first(where: { $0.pathExtension == "app" })
        else { throw UpdateError.extract }

        guard let bundle = Bundle(url: app),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version
        else { throw UpdateError.invalidBundle }

        #if DEBUG
        // Debug builds are ad-hoc signed; trust the update's own team so the flow can be exercised locally
        let expectedTeam = teamIdentifier(of: Bundle.main.bundleURL) ?? teamIdentifier(of: app)
        #else
        // Ad-hoc builds have no team to compare against, so they can't vouch for an update
        let expectedTeam = teamIdentifier(of: Bundle.main.bundleURL)
        #endif
        guard let team = expectedTeam else { throw UpdateError.signature }
        // Valid Developer ID signature from the same team as the running app
        let requirementText = "anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
            + " and certificate leaf[subject.OU] = \"\(team)\""
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate),
                                         requirement) == errSecSuccess
        else { throw UpdateError.signature }
        return app
    }

    private nonisolated static func teamIdentifier(of url: URL) -> String? {
        var code: SecStaticCode?
        var info: CFDictionary?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// A detached shell script waits for this process to exit, swaps the bundles (rolling back on failure)
    /// and opens the result. The new bundle keeps its own name, so an app renamed by an update follows along.
    private static func replaceAndRelaunch(with newApp: URL, work: URL) throws {
        let current = Bundle.main.bundleURL
        let dir = current.deletingLastPathComponent()
        let fm = FileManager.default
        // Translocated (quarantined, run in place) or read-only locations can't be updated in place
        guard !current.path.contains("/AppTranslocation/"),
              fm.isWritableFile(atPath: dir.path), fm.isWritableFile(atPath: current.path)
        else { throw UpdateError.notInstallable(newApp) }

        let script = work.appendingPathComponent("install.sh")
        try """
        #!/bin/sh
        PID="$1"; OLD="$2"; NEW="$3"; DEST="$4"; WORK="$5"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.2; done
        STAGE="$DEST.update-new"; BACKUP="$OLD.update-old"
        rm -rf "$STAGE" "$BACKUP"
        if ! ditto "$NEW" "$STAGE"; then rm -rf "$STAGE"; open "$OLD"; exit 1; fi
        if ! mv "$OLD" "$BACKUP"; then rm -rf "$STAGE"; open "$OLD"; exit 1; fi
        [ "$DEST" != "$OLD" ] && rm -rf "$DEST"
        if mv "$STAGE" "$DEST"; then
          rm -rf "$BACKUP"
        else
          rm -rf "$STAGE"; mv "$BACKUP" "$OLD"; DEST="$OLD"
        fi
        open "$DEST"
        rm -rf "$WORK"
        """.write(to: script, atomically: true, encoding: .utf8)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [
            script.path, String(ProcessInfo.processInfo.processIdentifier),
            current.path, newApp.path, dir.appendingPathComponent(newApp.lastPathComponent).path, work.path,
        ]
        try p.run()
        NSApp.terminate(nil)
    }
}
#endif
