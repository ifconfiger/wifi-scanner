import AppKit
import Foundation
import SwiftUI

/// BSSID 前 3 字节（OUI）对应的设备厂商
struct Vendor: Hashable {
    let oui: String
    /// IEEE 注册的机构全名
    let organization: String
    /// 简短品牌名，用于排序和悬浮提示
    let brand: String
    /// 拉取 logo 用的域名；未收录的品牌为 nil，显示首字母
    let domain: String?
    /// BSSID 是本地管理地址（虚拟 BSSID），厂商由清掉 LA 位后的 OUI 推测
    let isGuess: Bool

    var tooltip: String {
        var lines = [brand]
        if organization != brand { lines.append(organization) }
        lines.append("OUI \(oui)\(isGuess ? "（虚拟 BSSID，推测）" : "")")
        return lines.joined(separator: "\n")
    }
}

enum VendorDB {
    /// OUI → IEEE 机构名，来自 Resources/oui.tsv（tools/update_oui.py 生成）
    private static let table: [String: String] = load()

    static func lookup(bssid: String) -> Vendor? {
        let hex = bssid.uppercased().filter(\.isHexDigit)
        guard hex.count >= 6, let first = UInt8(hex.prefix(2), radix: 16) else { return nil }
        let oui = String(hex.prefix(6))
        if let org = table[oui] {
            return make(oui: oui, org: org, guess: false)
        }
        // 多 SSID 的 AP 常拿基础 MAC 改首字节低位当虚拟 BSSID：
        // 有的只置 LA 位(0x02)，有的连 0x04/0x08 一起改（实测 小米 50→5a、Ubiquiti 60→66），依次清掉再查
        if first & 0x02 != 0 {
            for mask: UInt8 in [0x02, 0x0E] {
                let base = String(format: "%02X", first & ~mask) + oui.dropFirst(2)
                if let org = table[base] { return make(oui: base, org: org, guess: true) }
            }
        }
        return nil
    }

    private static func make(oui: String, org: String, guess: Bool) -> Vendor {
        let key = " " + normalize(org) + " "
        if let b = brands.first(where: { b in b.keys.contains { key.contains(" \($0) ") } }) {
            return Vendor(oui: oui, organization: org, brand: b.name, domain: b.domain, isGuess: guess)
        }
        return Vendor(oui: oui, organization: org, brand: shortName(org), domain: nil, isGuess: guess)
    }

    /// 小写、非字母数字转空格：“TP-LINK TECHNOLOGIES CO.,LTD.” → “tp link technologies co ltd”
    private static func normalize(_ s: String) -> String {
        String(s.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " })
            .split(separator: " ")
            .joined(separator: " ")
    }

    /// 去掉公司后缀，作为未收录厂商的显示名
    private static func shortName(_ org: String) -> String {
        let suffixes = [
            "co., ltd.", "co.,ltd.", "co.,ltd", "co., ltd", "co ltd", "co.,", "ltd.", "ltd", "inc.", "inc",
            "corporation", "corp.", "corp", "limited", "llc", "gmbh", "s.a.", "sas", "ag", "b.v.", ",",
        ]
        var s = org.trimmingCharacters(in: .whitespaces)
        var changed = true
        while changed {
            changed = false
            for suf in suffixes where s.lowercased().hasSuffix(suf) && s.count > suf.count + 2 {
                s = String(s.dropLast(suf.count)).trimmingCharacters(in: .whitespaces)
                changed = true
            }
        }
        return s
    }

    private static func load() -> [String: String] {
        let url = Bundle.main.url(forResource: "oui", withExtension: "tsv")
            // swift run / Xcode 调试时不在 .app 里，回退到仓库内的文件
            ?? URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Resources/oui.tsv")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var dict: [String: String] = [:]
        dict.reserveCapacity(41_000)
        for line in text.split(separator: "\n") {
            guard let tab = line.firstIndex(of: "\t") else { continue }
            dict[String(line[..<tab])] = String(line[line.index(after: tab)...])
        }
        return dict
    }

    private struct Brand {
        let keys: [String]  // normalize 后的整词匹配
        let name: String
        let domain: String
    }

    /// 常见网络设备/终端品牌。顺序有意义：更具体的放前面（如 Meraki 在 Cisco 前）
    private static let brands: [Brand] = [
        Brand(keys: ["tp link"], name: "TP-Link", domain: "tp-link.com"),
        Brand(keys: ["mercury communication"], name: "水星 Mercury", domain: "mercurycom.com.cn"),
        Brand(keys: ["huawei"], name: "华为 Huawei", domain: "huawei.com"),
        Brand(keys: ["honor device"], name: "荣耀 Honor", domain: "honor.com"),
        Brand(keys: ["xiaomi"], name: "小米 Xiaomi", domain: "mi.com"),
        Brand(keys: ["new h3c", "h3c"], name: "新华三 H3C", domain: "h3c.com"),
        Brand(keys: ["ruijie"], name: "锐捷 Ruijie", domain: "ruijienetworks.com"),
        Brand(keys: ["zte"], name: "中兴 ZTE", domain: "zte.com.cn"),
        Brand(keys: ["tenda"], name: "腾达 Tenda", domain: "tenda.com.cn"),
        Brand(keys: ["fiberhome"], name: "烽火 FiberHome", domain: "fiberhome.com"),
        Brand(keys: ["china mobile"], name: "中国移动", domain: "10086.cn"),
        Brand(keys: ["skyworth"], name: "创维 Skyworth", domain: "skyworth.com"),
        Brand(keys: ["tianyi comheart"], name: "天邑 Comheart", domain: "tianyisc.com"),
        Brand(keys: ["netcore", "netis"], name: "磊科 Netcore", domain: "netcoretec.com"),
        Brand(keys: ["phicomm"], name: "斐讯 Phicomm", domain: "phicomm.com"),
        Brand(keys: ["comfast"], name: "COMFAST", domain: "comfast.cn"),
        Brand(keys: ["hikvision"], name: "海康威视 Hikvision", domain: "hikvision.com"),
        Brand(keys: ["dahua"], name: "大华 Dahua", domain: "dahuasecurity.com"),
        Brand(keys: ["oppo"], name: "OPPO", domain: "oppo.com"),
        Brand(keys: ["vivo mobile"], name: "vivo", domain: "vivo.com"),
        Brand(keys: ["realme"], name: "realme", domain: "realme.com"),
        Brand(keys: ["oneplus"], name: "OnePlus", domain: "oneplus.com"),
        Brand(keys: ["lenovo"], name: "Lenovo", domain: "lenovo.com"),
        Brand(keys: ["midea"], name: "美的 Midea", domain: "midea.com"),
        Brand(keys: ["gree electric"], name: "格力 Gree", domain: "gree.com"),
        Brand(keys: ["hisense"], name: "海信 Hisense", domain: "hisense.com"),
        Brand(keys: ["tcl"], name: "TCL", domain: "tcl.com"),
        Brand(keys: ["espressif"], name: "Espressif（IoT）", domain: "espressif.com"),
        Brand(keys: ["tuya"], name: "涂鸦 Tuya", domain: "tuya.com"),
        Brand(keys: ["apple"], name: "Apple", domain: "apple.com"),
        Brand(keys: ["samsung"], name: "Samsung", domain: "samsung.com"),
        Brand(keys: ["google"], name: "Google", domain: "google.com"),
        Brand(keys: ["eero"], name: "eero", domain: "eero.com"),
        Brand(keys: ["amazon technologies"], name: "Amazon", domain: "amazon.com"),
        Brand(keys: ["microsoft"], name: "Microsoft", domain: "microsoft.com"),
        Brand(keys: ["sony"], name: "Sony", domain: "sony.com"),
        Brand(keys: ["nintendo"], name: "Nintendo", domain: "nintendo.com"),
        Brand(keys: ["lg electronics"], name: "LG", domain: "lg.com"),
        Brand(keys: ["intel corporate", "intel corporation"], name: "Intel", domain: "intel.com"),
        Brand(keys: ["asustek"], name: "ASUS", domain: "asus.com"),
        Brand(keys: ["netgear"], name: "NETGEAR", domain: "netgear.com"),
        Brand(keys: ["d link"], name: "D-Link", domain: "dlink.com"),
        Brand(keys: ["linksys"], name: "Linksys", domain: "linksys.com"),
        Brand(keys: ["belkin"], name: "Belkin", domain: "belkin.com"),
        Brand(keys: ["cisco meraki"], name: "Cisco Meraki", domain: "meraki.com"),
        Brand(keys: ["cisco"], name: "Cisco", domain: "cisco.com"),
        Brand(keys: ["aruba"], name: "Aruba", domain: "arubanetworks.com"),
        Brand(keys: ["hewlett packard enterprise"], name: "HPE Aruba", domain: "hpe.com"),
        Brand(keys: ["ubiquiti"], name: "Ubiquiti", domain: "ui.com"),
        Brand(keys: ["juniper", "mist systems"], name: "Juniper Mist", domain: "juniper.net"),
        Brand(keys: ["ruckus"], name: "Ruckus", domain: "ruckusnetworks.com"),
        Brand(keys: ["commscope", "arris"], name: "CommScope", domain: "commscope.com"),
        Brand(keys: ["extreme networks", "aerohive"], name: "Extreme Networks", domain: "extremenetworks.com"),
        Brand(keys: ["fortinet"], name: "Fortinet", domain: "fortinet.com"),
        Brand(keys: ["cambium"], name: "Cambium", domain: "cambiumnetworks.com"),
        Brand(keys: ["routerboard", "mikrotik"], name: "MikroTik", domain: "mikrotik.com"),
        Brand(keys: ["synology"], name: "Synology", domain: "synology.com"),
        Brand(keys: ["zyxel"], name: "Zyxel", domain: "zyxel.com"),
        Brand(keys: ["gl technologies"], name: "GL.iNet", domain: "gl-inet.com"),
        Brand(keys: ["sagemcom"], name: "Sagemcom", domain: "sagemcom.com"),
        Brand(keys: ["technicolor", "vantiva"], name: "Vantiva (Technicolor)", domain: "vantiva.com"),
        Brand(keys: ["avm audiovisuelles"], name: "AVM FRITZ!", domain: "fritz.com"),
        Brand(keys: ["sercomm"], name: "Sercomm", domain: "sercomm.com"),
        Brand(keys: ["arcadyan"], name: "Arcadyan", domain: "arcadyan.com"),
        Brand(keys: ["askey"], name: "Askey", domain: "askey.com.tw"),
        Brand(keys: ["nokia"], name: "Nokia", domain: "nokia.com"),
        Brand(keys: ["edimax"], name: "Edimax", domain: "edimax.com"),
        Brand(keys: ["buffalo"], name: "Buffalo", domain: "buffalotech.com"),
        Brand(keys: ["cudy"], name: "Cudy", domain: "cudy.com"),
        Brand(keys: ["wavlink"], name: "Wavlink", domain: "wavlink.com"),
    ]
}

/// 厂商 logo：按域名抓 favicon，内存 + 磁盘缓存，失败本次运行内不再重试
@MainActor
final class LogoStore {
    static let shared = LogoStore()

    private var images: [String: NSImage] = [:]
    private var failed: Set<String> = []
    private var inflight: [String: Task<Data?, Never>] = [:]

    func cached(_ domain: String) -> NSImage? { images[domain] }

    func load(_ domain: String) async -> NSImage? {
        if let img = images[domain] { return img }
        if failed.contains(domain) { return nil }
        // 后台只传 Data：NSImage 在 macOS 14 以前不是 Sendable
        let t = inflight[domain] ?? Task.detached(priority: .utility) { await Self.fetch(domain) }
        inflight[domain] = t
        let data = await t.value
        inflight[domain] = nil
        if let img = images[domain] { return img }
        guard let data, let img = NSImage(data: data) else {
            failed.insert(domain)
            return nil
        }
        images[domain] = img
        return img
    }

    private nonisolated static let cacheDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("WiFiScope/logos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private nonisolated static func fetch(_ domain: String) async -> Data? {
        let file = cacheDir.appendingPathComponent(domain)
        if let data = try? Data(contentsOf: file), NSImage(data: data) != nil { return data }
        // DuckDuckGo 和厂商官网在国内一般能直连；Google 放中间兜底
        let sources = [
            "https://icons.duckduckgo.com/ip3/\(domain).ico",
            "https://www.google.com/s2/favicons?domain=\(domain)&sz=64",
            "https://\(domain)/favicon.ico",
        ]
        for s in sources {
            guard let url = URL(string: s) else { continue }
            var req = URLRequest(url: url, timeoutInterval: 6)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let img = NSImage(data: data), img.isValid, img.size.width >= 8
            else { continue }
            try? data.write(to: file)
            return data
        }
        return nil
    }
}

/// 表格/详情里的小 logo；拿不到图时显示品牌首字母，悬浮显示厂商名
struct VendorLogo: View {
    let vendor: Vendor?
    var size: CGFloat = 16

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let v = vendor {
                ZStack {
                    if let img = image ?? v.domain.flatMap({ LogoStore.shared.cached($0) }) {
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                    } else {
                        RoundedRectangle(cornerRadius: size * 0.22)
                            .fill(Palette.color(for: v.brand))
                        Text(monogram(v.brand))
                            .font(.system(size: size * 0.6, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: size, height: size)
                .opacity(v.isGuess ? 0.75 : 1)
                .help(v.tooltip)
                .task(id: v.domain) {
                    guard let d = v.domain else { return }
                    image = await LogoStore.shared.load(d)
                }
            } else {
                Image(systemName: "questionmark.square.dashed")
                    .resizable()
                    .frame(width: size, height: size)
                    .foregroundStyle(.tertiary)
                    .help("未知厂商（OUI 未登记或 BSSID 为随机地址）")
            }
        }
    }

    /// 中文品牌取第一个字，英文取首字母
    private func monogram(_ s: String) -> String {
        guard let c = s.first(where: { $0.isLetter }) else { return "?" }
        return String(c).uppercased()
    }
}
