import CoreWLAN
import Foundation

enum Band: String, CaseIterable, Identifiable {
    case ghz24 = "2.4 GHz"
    case ghz5 = "5 GHz"
    case ghz6 = "6 GHz"
    case unknown = "Unknown"

    var id: String { rawValue }

    /// Display name; only "Unknown" needs translating
    var label: String { self == .unknown ? String(localized: "Unknown") : rawValue }

    static let scannable: [Band] = [.ghz24, .ghz5, .ghz6]

    /// CWChannelBand raw values: 0 unknown / 1 2.4G / 2 5G / 3 6G. Uses rawValue to avoid depending on newer SDK enum names.
    init(_ band: CWChannelBand?) {
        switch band?.rawValue ?? 0 {
        case 1: self = .ghz24
        case 2: self = .ghz5
        case 3: self = .ghz6
        default: self = .unknown
        }
    }

    /// X-axis (channel number) range of the spectrum chart
    var channelDomain: ClosedRange<Double> {
        switch self {
        case .ghz24: return -1...16
        case .ghz5: return 28...181
        case .ghz6, .unknown: return -10...243
        }
    }

    var axisTicks: [Double] {
        switch self {
        case .ghz24: return (1...14).map(Double.init)
        case .ghz5: return [36, 52, 100, 116, 132, 149, 165, 177]
        case .ghz6, .unknown: return stride(from: 1, through: 233, by: 32).map(Double.init)
        }
    }

    /// Channel number → center frequency (MHz)
    func frequency(ofChannel ch: Double) -> Double {
        switch self {
        case .ghz24: return ch == 14 ? 2484 : 2407 + 5 * ch
        case .ghz5: return 5000 + 5 * ch
        case .ghz6: return 5950 + 5 * ch
        case .unknown: return 0
        }
    }
}

enum BandFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case ghz24 = "2.4 GHz"
    case ghz5 = "5 GHz"
    case ghz6 = "6 GHz"

    var id: String { rawValue }

    var label: String { self == .all ? String(localized: "All") : rawValue }

    var band: Band? {
        switch self {
        case .all: return nil
        case .ghz24: return .ghz24
        case .ghz5: return .ghz5
        case .ghz6: return .ghz6
        }
    }

    func matches(_ b: Band) -> Bool { band == nil || band == b }
}

struct WiFiNetwork: Identifiable, Hashable {
    let id: String
    let ssid: String
    let bssid: String
    let rssi: Int
    let noise: Int
    let channel: Int
    let band: Band
    let widthMHz: Int
    let security: String
    let phyMode: String
    let countryCode: String
    let beaconInterval: Int
    let isIBSS: Bool
    let stationCount: Int?
    let channelUtilization: Double?
    let isCurrent: Bool
    let vendor: Vendor?

    /// CoreWLAN only measures noise for the connected network; others report 0
    var hasNoise: Bool { noise != 0 }
    var snr: Int? { hasNoise ? rssi - noise : nil }
    /// Table sort key: networks without noise data sort last
    var snrSortKey: Int { snr ?? Int.min }
    var bandLabel: String { band.label }
    var displaySSID: String { ssid.isEmpty ? String(localized: "(hidden / no permission)") : ssid }
    var vendorName: String { vendor.map { "\($0.brand) \($0.searchText)" } ?? "" }

    init(network n: CWNetwork, currentBSSID: String?, fallbackIndex: Int) {
        let ch = n.wlanChannel
        let b = n.bssid ?? ""
        ssid = n.ssid ?? ""
        bssid = b
        rssi = n.rssiValue
        noise = n.noiseMeasurement
        channel = ch?.channelNumber ?? 0
        band = Band(ch?.channelBand)
        widthMHz = WiFiNetwork.width(ch?.channelWidth)
        security = WiFiNetwork.security(of: n)
        countryCode = n.countryCode ?? ""
        beaconInterval = n.beaconInterval
        isIBSS = n.ibss
        vendor = VendorDB.lookup(bssid: b)
        let ie = IEParser.parse(n.informationElementData, band: band)
        phyMode = ie.phyMode
        stationCount = ie.stationCount
        channelUtilization = ie.channelUtilization
        // Use a local: the right side of && is an autoclosure and cannot capture self before init completes
        isCurrent = !b.isEmpty && b == currentBSSID
        // Without location permission the BSSID is empty; build a reasonably stable id from SSID + channel + duplicate index
        id = b.isEmpty ? "\(n.ssid ?? "")#\(ch?.channelNumber ?? 0)#\(fallbackIndex)" : b
    }

    /// CWChannelWidth raw values: 1=20 / 2=40 / 3=80 / 4=160
    private static func width(_ w: CWChannelWidth?) -> Int {
        switch w?.rawValue ?? 0 {
        case 1: return 20
        case 2: return 40
        case 3: return 80
        case 4: return 160
        default: return 20
        }
    }

    private static func security(of n: CWNetwork) -> String {
        let ordered: [(CWSecurity, String)] = [
            (.wpa3Enterprise, String(localized: "WPA3 Enterprise")),
            (.wpa3Transition, "WPA2/WPA3"),
            (.wpa3Personal, String(localized: "WPA3 Personal")),
            (.wpa2Enterprise, String(localized: "WPA2 Enterprise")),
            (.wpa2Personal, String(localized: "WPA2 Personal")),
            (.wpaEnterprise, String(localized: "WPA Enterprise")),
            (.wpaPersonal, String(localized: "WPA Personal")),
            (.dynamicWEP, String(localized: "Dynamic WEP")),
            (.WEP, "WEP"),
        ]
        for (sec, label) in ordered where n.supportsSecurity(sec) {
            return label
        }
        return n.supportsSecurity(.none) ? String(localized: "Open") : String(localized: "Unknown")
    }

    /// Center channel for the spectrum chart. CoreWLAN reports the primary channel; wide channels need converting to the bonded center.
    var centerChannel: Double {
        let ch = channel
        switch band {
        case .ghz24:
            // 2.4 GHz 40 MHz: the extension direction is unavailable, so approximate with the common layout
            if widthMHz >= 40 { return Double(ch <= 7 ? ch + 2 : ch - 2) }
            return Double(ch)
        case .ghz5:
            let base = ch >= 149 ? 149 : 36
            return Double(Self.bondedCenter(ch, base: base, width: widthMHz))
        case .ghz6:
            return Double(Self.bondedCenter(ch, base: 1, width: widthMHz))
        case .unknown:
            return Double(ch)
        }
    }

    private static func bondedCenter(_ ch: Int, base: Int, width: Int) -> Int {
        let idx = (ch - base) / 4
        switch width {
        case 40: return base + (idx / 2) * 8 + 2
        case 80: return base + (idx / 4) * 16 + 6
        case 160: return base + (idx / 8) * 32 + 14
        default: return ch
        }
    }

    /// Half of the occupied spectrum width (in channel numbers; 1 channel = 5 MHz)
    var halfSpan: Double { Double(widthMHz) / 10 }

    var frequencyMHz: Int { Int(band.frequency(ofChannel: Double(channel))) }
    var centerFrequencyMHz: Int { Int(band.frequency(ofChannel: centerChannel)) }

    /// Other APs in the same band on the same primary channel
    func isCoChannel(with o: WiFiNetwork) -> Bool {
        o.id != id && o.band == band && o.channel == channel
    }

    /// Other APs in the same band whose occupied spectrum overlaps (including co-channel)
    func overlaps(_ o: WiFiNetwork) -> Bool {
        guard o.id != id, o.band == band else { return false }
        return centerChannel - halfSpan < o.centerChannel + o.halfSpan
            && o.centerChannel - o.halfSpan < centerChannel + halfSpan
    }

    var quality: String {
        switch rssi {
        case (-50)...: return String(localized: "Excellent")
        case (-60)...: return String(localized: "Good")
        case (-70)...: return String(localized: "Fair")
        case (-80)...: return String(localized: "Weak")
        default: return String(localized: "Poor")
        }
    }

    /// Trapezoidal spectrum outline with rounded top corners.
    /// cornerX is the rounding along the top edge (channels), cornerY the drop along the ramp (dB).
    func spectrumShape(floor: Double = -100, cornerX: Double = 0, cornerY: Double = 0) -> [SpectrumPoint] {
        let half = halfSpan
        let ramp = min(1.0, half / 3)
        let c = centerChannel
        let top = Double(rssi)
        let left = c - half, right = c + half
        let height = max(top - floor, 1)
        let k = min(0.5, cornerY / height)               // fraction of the ramp used by the curve
        let rx = min(cornerX, max(half - ramp, 0))       // never past the middle of the top edge

        // Quadratic Bézier from a point on the ramp, through the corner, to a point on the top edge
        func corner(start: SpectrumPoint, control: SpectrumPoint, end: SpectrumPoint) -> [SpectrumPoint] {
            let steps = 8
            return (0...steps).map { i in
                let t = Double(i) / Double(steps), u = 1 - t
                return SpectrumPoint(
                    x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                    y: u * u * start.y + 2 * u * t * control.y + t * t * end.y
                )
            }
        }
        let tl = left + ramp, tr = right - ramp
        let leftCorner = corner(
            start: SpectrumPoint(x: tl - k * ramp, y: top - k * height),
            control: SpectrumPoint(x: tl, y: top),
            end: SpectrumPoint(x: tl + rx, y: top)
        )
        let rightCorner = corner(
            start: SpectrumPoint(x: tr - rx, y: top),
            control: SpectrumPoint(x: tr, y: top),
            end: SpectrumPoint(x: tr + k * ramp, y: top - k * height)
        )
        return [SpectrumPoint(x: left, y: floor)] + leftCorner + rightCorner + [SpectrumPoint(x: right, y: floor)]
    }
}

struct SpectrumPoint {
    let x: Double
    let y: Double
}

struct SignalSample: Identifiable {
    let date: Date
    let rssi: Int
    var id: Date { date }
}

struct IEInfo {
    var phyMode = ""
    var stationCount: Int?
    var channelUtilization: Double?
}

/// Parses 802.11 Information Elements
enum IEParser {
    static func parse(_ data: Data?, band: Band) -> IEInfo {
        var info = IEInfo()
        guard let d = data, !d.isEmpty else { return info }
        let bytes = [UInt8](d)
        var ht = false, vht = false, he = false, eht = false
        var i = 0
        while i + 1 < bytes.count {
            let id = bytes[i]
            let len = Int(bytes[i + 1])
            let body = i + 2
            guard body + len <= bytes.count else { break }
            switch id {
            case 11 where len >= 3:  // BSS Load: station count (2B LE) + channel utilization (1B, /255)
                info.stationCount = Int(bytes[body]) | Int(bytes[body + 1]) << 8
                info.channelUtilization = Double(bytes[body + 2]) / 255
            case 45: ht = true      // HT Capabilities
            case 191: vht = true    // VHT Capabilities
            case 255 where len >= 1:
                if bytes[body] == 35 { he = true }        // HE Capabilities
                else if bytes[body] == 108 { eht = true } // EHT Capabilities
            default: break
            }
            i = body + len
        }
        if eht { info.phyMode = "be (Wi-Fi 7)" }
        else if he { info.phyMode = "ax (Wi-Fi 6\(band == .ghz6 ? "E" : ""))" }
        else if vht { info.phyMode = "ac (Wi-Fi 5)" }
        else if ht { info.phyMode = "n (Wi-Fi 4)" }
        else { info.phyMode = band == .ghz24 ? "b/g" : "a" }
        return info
    }
}
