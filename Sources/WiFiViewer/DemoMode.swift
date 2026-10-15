#if DEMO
import AppKit

/// Store screenshots only (build with SWIFT_FLAGS="-Xswiftc -DDEMO"): swaps real SSIDs and the
/// device part of each BSSID for fictional ones, keeping radio data and the vendor OUI intact
enum DemoMode {
    private static let names = [
        "Maple Street Cafe", "Bluebird Studio", "Harbor Books", "Linden-Guest", "Orchard Office",
        "Cedar Lane", "Pixel Lab", "Northwind", "Sunny Apartment", "Juniper Hall",
        "Copperfield", "Lighthouse", "Willow Home", "Studio 42", "Garden View",
        "Riverside", "Atlas-IoT", "Hummingbird", "Granite Works", "Moonbeam",
    ]
    private static let homeName = "Home Network"
    /// Names are handed out on first sight and kept for the whole run, so they never shift between scans
    nonisolated(unsafe) private static var assigned: [String: String] = [:]
    private static let lock = NSLock()

    static func anonymize(_ list: [WiFiNetwork]) -> [WiFiNetwork] {
        lock.lock(); defer { lock.unlock() }
        // The connected network's other bands share its SSID, so they all become the home network
        if let home = list.first(where: \.isCurrent)?.ssid, !home.isEmpty { assigned[home] = homeName }
        for s in Set(list.map(\.ssid)).sorted() where !s.isEmpty && assigned[s] == nil {
            let used = assigned.count
            assigned[s] = names[used % names.count] + (used >= names.count ? " \(used / names.count + 1)" : "")
        }
        return list.map { n in
            let bssid = fakeBSSID(n.bssid)
            return WiFiNetwork(copy: n, ssid: assigned[n.ssid] ?? "", bssid: bssid, id: n.bssid.isEmpty ? n.id : bssid)
        }
    }

    static func ssid(_ real: String) -> String { homeName }

    /// 1440×900 pt = 2880×1800 px on Retina, the largest Mac App Store screenshot size
    @MainActor static func sizeWindow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard let w = NSApp.windows.first(where: { $0.isVisible && $0.title == "WiFi-Viewer" }) else { return }
            // DEMO_DARK=1 forces dark mode without touching the system setting
            if ProcessInfo.processInfo.environment["DEMO_DARK"] == "1" { NSApp.appearance = NSAppearance(named: .darkAqua) }
            w.setFrame(NSRect(x: 240, y: 75, width: 1440, height: 900), display: true)
        }
    }

    /// DEMO_CHART=spectrum|ranking|congestion|history picks the chart tab shown at launch
    static var chart: ChartMode {
        ProcessInfo.processInfo.environment["DEMO_CHART"].flatMap(ChartMode.init(rawValue:)) ?? .spectrum
    }

    /// Re-applied whenever fewer networks are selected than asked for: the launch cache may hold only a few,
    /// and a BSS briefly missing from a scan drops out of the selection
    /// DEMO_SELECT is "current", "spread:<k>", or "<band>:<k>" for the k strongest networks on a band ("2.4", "5", "6" or "all")
    static func pick(from list: [WiFiNetwork]) -> Set<String>? {
        guard let spec = ProcessInfo.processInfo.environment["DEMO_SELECT"] else { return nil }
        var ids: [String]
        if spec == "current" {
            ids = list.filter(\.isCurrent).map(\.id)
        } else if spec.hasPrefix("spread:"), let k = Int(spec.dropFirst(7)) {
            // One network per signal level, evenly spaced from strongest to weakest, so history lines don't overlap
            var seen = Set<Int>()
            let levels = list.filter { !$0.ssid.isEmpty }.sorted { $0.rssi > $1.rssi }
                .filter { seen.insert($0.rssi / 4).inserted }
            guard levels.count >= k else { return nil }
            ids = (0..<k).map { levels[$0 * (levels.count - 1) / max(k - 1, 1)].id }
        } else {
            let parts = spec.split(separator: ":")
            let band = String(parts.first ?? "all"), k = Int(parts.last ?? "1") ?? 1
            ids = list.filter { band == "all" || $0.band.rawValue == "\(band) GHz" }
                .filter { !$0.ssid.isEmpty }
                .sorted { $0.rssi > $1.rssi }.prefix(k).map(\.id)
        }
        guard !ids.isEmpty else { return nil }
        return Set(ids)
    }

    private static func fakeBSSID(_ b: String) -> String {
        let parts = b.split(separator: ":")
        guard parts.count == 6 else { return b }
        let h = fnv(b)
        let tail = (0..<3).map { String(format: "%02x", (h >> (8 * $0)) & 0xff) }
        return (parts.prefix(3).map(String.init) + tail).joined(separator: ":")
    }

    private static func fnv(_ s: String) -> UInt64 {
        s.utf8.reduce(0xcbf2_9ce4_8422_2325) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
    }
}

extension WiFiNetwork {
    init(copy n: WiFiNetwork, ssid: String, bssid: String, id: String) {
        self.id = id
        self.ssid = ssid
        self.bssid = bssid
        rssi = n.rssi
        noise = n.noise
        channel = n.channel
        band = n.band
        widthMHz = n.widthMHz
        security = n.security
        phyMode = n.phyMode
        countryCode = n.countryCode
        beaconInterval = n.beaconInterval
        isIBSS = n.isIBSS
        stationCount = n.stationCount
        channelUtilization = n.channelUtilization
        isCurrent = n.isCurrent
        vendor = n.vendor
    }
}
#endif
