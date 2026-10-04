import CoreWLAN
import Foundation

enum Band: String, CaseIterable, Identifiable {
    case ghz24 = "2.4 GHz"
    case ghz5 = "5 GHz"
    case ghz6 = "6 GHz"
    case unknown = "未知"

    var id: String { rawValue }

    static let scannable: [Band] = [.ghz24, .ghz5, .ghz6]

    /// CWChannelBand 原始值：0 未知 / 1 2.4G / 2 5G / 3 6G。用 rawValue 避免依赖较新 SDK 的枚举名。
    init(_ band: CWChannelBand?) {
        switch band?.rawValue ?? 0 {
        case 1: self = .ghz24
        case 2: self = .ghz5
        case 3: self = .ghz6
        default: self = .unknown
        }
    }

    /// 频谱图横轴（信道号）范围
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

    /// 信道号 → 中心频率 (MHz)
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
    case all = "全部"
    case ghz24 = "2.4 GHz"
    case ghz5 = "5 GHz"
    case ghz6 = "6 GHz"

    var id: String { rawValue }

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

    var snr: Int { rssi - noise }
    var bandLabel: String { band.rawValue }
    var displaySSID: String { ssid.isEmpty ? "(隐藏/无权限)" : ssid }

    init(network n: CWNetwork, currentBSSID: String?, fallbackIndex: Int) {
        let ch = n.wlanChannel
        ssid = n.ssid ?? ""
        bssid = n.bssid ?? ""
        rssi = n.rssiValue
        noise = n.noiseMeasurement
        channel = ch?.channelNumber ?? 0
        band = Band(ch?.channelBand)
        widthMHz = WiFiNetwork.width(ch?.channelWidth)
        security = WiFiNetwork.security(of: n)
        countryCode = n.countryCode ?? ""
        beaconInterval = n.beaconInterval
        isIBSS = n.ibss
        let ie = IEParser.parse(n.informationElementData, band: band)
        phyMode = ie.phyMode
        stationCount = ie.stationCount
        channelUtilization = ie.channelUtilization
        isCurrent = !bssid.isEmpty && bssid == currentBSSID
        // 无定位权限时 BSSID 为空，只能拼一个临时 id
        id = bssid.isEmpty ? "\(ssid)#\(channel)#\(fallbackIndex)" : bssid
    }

    /// CWChannelWidth 原始值：1=20 / 2=40 / 3=80 / 4=160
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
            (.wpa3Enterprise, "WPA3 企业"),
            (.wpa3Transition, "WPA2/WPA3"),
            (.wpa3Personal, "WPA3 个人"),
            (.wpa2Enterprise, "WPA2 企业"),
            (.wpa2Personal, "WPA2 个人"),
            (.wpaEnterprise, "WPA 企业"),
            (.wpaPersonal, "WPA 个人"),
            (.dynamicWEP, "动态 WEP"),
            (.WEP, "WEP"),
        ]
        for (sec, label) in ordered where n.supportsSecurity(sec) {
            return label
        }
        return n.supportsSecurity(.none) ? "开放" : "未知"
    }

    /// 频谱图里的中心信道。CoreWLAN 给的是主信道，宽频时需要换算到绑定后的中心。
    var centerChannel: Double {
        let ch = channel
        switch band {
        case .ghz24:
            // 2.4G 的 40MHz 拿不到扩展方向，按常见配置近似
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

    /// 占用频谱的半宽（单位：信道号，1 信道 = 5 MHz）
    var halfSpan: Double { Double(widthMHz) / 10 }

    var frequencyMHz: Int { Int(band.frequency(ofChannel: Double(channel))) }
    var centerFrequencyMHz: Int { Int(band.frequency(ofChannel: centerChannel)) }

    /// 同频段、主信道相同的其他 AP
    func isCoChannel(with o: WiFiNetwork) -> Bool {
        o.id != id && o.band == band && o.channel == channel
    }

    /// 同频段、占用频谱有交叠的其他 AP（含同信道）
    func overlaps(_ o: WiFiNetwork) -> Bool {
        guard o.id != id, o.band == band else { return false }
        return centerChannel - halfSpan < o.centerChannel + o.halfSpan
            && o.centerChannel - o.halfSpan < centerChannel + halfSpan
    }

    var quality: String {
        switch rssi {
        case (-50)...: return "优秀"
        case (-60)...: return "良好"
        case (-70)...: return "一般"
        case (-80)...: return "较弱"
        default: return "很差"
        }
    }

    /// 梯形频谱轮廓
    func spectrumShape(floor: Double = -100) -> [SpectrumPoint] {
        let half = halfSpan
        let ramp = min(1.0, half / 3)
        let c = centerChannel
        let top = Double(rssi)
        return [
            SpectrumPoint(x: c - half, y: floor),
            SpectrumPoint(x: c - half + ramp, y: top),
            SpectrumPoint(x: c + half - ramp, y: top),
            SpectrumPoint(x: c + half, y: floor),
        ]
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

/// 解析 802.11 Information Elements
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
            case 11 where len >= 3:  // BSS Load：连接数(2B LE) + 信道利用率(1B, /255)
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
