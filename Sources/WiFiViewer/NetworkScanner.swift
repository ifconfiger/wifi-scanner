import Combine
import CoreWLAN
import Foundation
import SwiftUI

/// Passive scanner built on CoreWLAN.
/// scanForNetworks lets the system Wi-Fi driver do off-channel scans while staying associated, so the
/// current connection is not dropped, but latency jitters briefly during a scan — keep the interval reasonable.
@MainActor
final class NetworkScanner: ObservableObject {
    @Published private(set) var networks: [WiFiNetwork] = []
    @Published private(set) var history: [String: [SignalSample]] = [:]
    @Published private(set) var firstSeen: [String: Date] = [:]
    @Published private(set) var isScanning = false
    @Published private(set) var lastScan: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var currentLink: String = ""

    @Published var autoRefresh = true { didSet { scheduleTimer() } }
    @Published var interval: Double = 10 { didSet { scheduleTimer() } }

    private let client = CWWiFiClient.shared()
    private var timer: Timer?
    private let historyWindow: TimeInterval = 300

    func start() {
        showCached()
        scan()
        scheduleTimer()
    }

    /// The system's most recent scan cache is nearly free; show it at launch instead of waiting for the first full scan (~3–5 s)
    private func showCached() {
        guard let iface = client.interface(), iface.powerOn() else { return }
        Task {
            let list = await Task.detached(priority: .userInitiated) {
                Self.build(iface.cachedScanResults() ?? [], current: iface.bssid())
            }.value
            // Skip the cache if a real scan already came back
            if networks.isEmpty { insertNew(list) }
        }
    }

    func scan() {
        guard !isScanning else { return }
        guard let iface = client.interface() else {
            lastError = String(localized: "No Wi-Fi interface found")
            return
        }
        guard iface.powerOn() else {
            lastError = String(localized: "Wi-Fi is off. Turn on Wi-Fi first.")
            return
        }
        isScanning = true

        // CoreWLAN scanning is a blocking call that returns everything at once; there is no public per-network callback.
        // Poll the system cache while scanning, insert newly seen networks early, then reconcile with the full result.
        let poller = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                let partial = await Task.detached(priority: .utility) {
                    Self.build(iface.cachedScanResults() ?? [], current: iface.bssid())
                }.value
                guard !Task.isCancelled else { break }
                insertNew(partial)
            }
        }

        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<[WiFiNetwork], Error> in
                do {
                    // ssid=nil scans everything; includeHidden also returns hidden networks
                    let found = try iface.scanForNetworks(withSSID: nil, includeHidden: true)
                    return .success(Self.build(found, current: iface.bssid()))
                } catch {
                    return .failure(error)
                }
            }.value
            poller.cancel()

            switch result {
            case .success(let list):
                apply(list)
                lastError = nil
            case .failure(let error):
                lastError = String(localized: "Scan failed: \(error.localizedDescription)")
            }
            updateCurrentLink(iface)
            isScanning = false
        }
    }

    private nonisolated static func build(_ found: Set<CWNetwork>, current: String?) -> [WiFiNetwork] {
        // Scan results are an unordered Set; sort first, then number same-name/same-channel networks so ids stay stable without BSSIDs
        let sorted = found.sorted {
            ($0.ssid ?? "", $0.wlanChannel?.channelNumber ?? 0, -$0.rssiValue)
                < ($1.ssid ?? "", $1.wlanChannel?.channelNumber ?? 0, -$1.rssiValue)
        }
        var seen: [String: Int] = [:]
        let list = sorted.map { net -> WiFiNetwork in
            let key = "\(net.ssid ?? "")#\(net.wlanChannel?.channelNumber ?? 0)"
            let idx = seen[key, default: 0]
            seen[key] = idx + 1
            return WiFiNetwork(network: net, currentBSSID: current, fallbackIndex: idx)
        }
        // CoreWLAN occasionally returns the same BSS several times (usually a router's hidden SSID) with identical fields.
        // BSSID is the row id and duplicates make the table select them all together, so merge by BSSID, preferring the named one
        var index: [String: Int] = [:]
        var out: [WiFiNetwork] = []
        for n in list {
            guard !n.bssid.isEmpty else { out.append(n); continue }
            if let i = index[n.bssid] {
                if out[i].ssid.isEmpty && !n.ssid.isEmpty { out[i] = n }
            } else {
                index[n.bssid] = out.count
                out.append(n)
            }
        }
        #if DEMO
        return DemoMode.anonymize(out)
        #else
        return out
        #endif
    }

    /// Only append networks not yet listed; leave existing rows alone so stale cached signal values don't roll numbers back
    private func insertNew(_ list: [WiFiNetwork]) {
        let known = Set(networks.map(\.id))
        // The system cache often mixes in entries without a BSSID whose ids don't match the same network with one, causing duplicate rows.
        // When BSSIDs are available (location permission granted), only accept entries that have one
        let hasBSSID = (networks + list).contains { !$0.bssid.isEmpty }
        let fresh = list.filter { !known.contains($0.id) && (!hasBSSID || !$0.bssid.isEmpty) }
        guard !fresh.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.25)) { networks.append(contentsOf: fresh) }
    }

    private func apply(_ list: [WiFiNetwork]) {
        let now = Date()
        withAnimation(.easeOut(duration: 0.25)) { networks = list }
        lastScan = now
        for n in list where !n.bssid.isEmpty {
            history[n.bssid, default: []].append(SignalSample(date: now, rssi: n.rssi))
            if firstSeen[n.bssid] == nil { firstSeen[n.bssid] = now }
        }
        let cutoff = now.addingTimeInterval(-historyWindow)
        history = history.compactMapValues { samples in
            let kept = samples.filter { $0.date >= cutoff }
            return kept.isEmpty ? nil : kept
        }
    }

    private func updateCurrentLink(_ iface: CWInterface) {
        let name = iface.interfaceName ?? "en0"
        guard let ch = iface.wlanChannel() else {
            currentLink = String(localized: "\(name): not connected")
            return
        }
        #if DEMO
        let ssid = DemoMode.ssid(iface.ssid() ?? "")
        #else
        let ssid = iface.ssid() ?? String(localized: "(no permission to read SSID)")
        #endif
        currentLink = String(localized: "\(name): \(ssid) · Channel \(ch.channelNumber) · \(iface.rssiValue()) dBm · \(Int(iface.transmitRate())) Mbps")
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = nil
        guard autoRefresh else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
    }
}
