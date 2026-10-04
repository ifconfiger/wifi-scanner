import Combine
import CoreWLAN
import Foundation

/// 基于 CoreWLAN 的被动扫描器。
/// scanForNetworks 由系统 Wi-Fi 驱动在保持关联的前提下做离信道扫描，不会断开当前连接，
/// 但扫描期间会有短暂的延迟抖动，所以默认间隔不要设太短。
@MainActor
final class WiFiScanner: ObservableObject {
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
        scan()
        scheduleTimer()
    }

    func scan() {
        guard !isScanning else { return }
        guard let iface = client.interface() else {
            lastError = "未找到 Wi-Fi 接口"
            return
        }
        guard iface.powerOn() else {
            lastError = "Wi-Fi 已关闭，请先打开 Wi-Fi"
            return
        }
        isScanning = true

        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<[WiFiNetwork], Error> in
                do {
                    // ssid=nil 表示扫描全部；includeHidden 带上隐藏网络
                    let found = try iface.scanForNetworks(withSSID: nil, includeHidden: true)
                    let current = iface.bssid()
                    // 扫描结果是无序 Set；先排序再给同名同信道的网络编号，没有 BSSID 时 id 才不会每轮乱跳
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
                    return .success(list)
                } catch {
                    return .failure(error)
                }
            }.value

            switch result {
            case .success(let list):
                apply(list)
                lastError = nil
            case .failure(let error):
                lastError = "扫描失败：\(error.localizedDescription)"
            }
            updateCurrentLink(iface)
            isScanning = false
        }
    }

    private func apply(_ list: [WiFiNetwork]) {
        let now = Date()
        networks = list
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
            currentLink = "\(name)：未连接"
            return
        }
        let ssid = iface.ssid() ?? "(无权限读取 SSID)"
        currentLink = "\(name)：\(ssid) · 信道 \(ch.channelNumber) · \(iface.rssiValue()) dBm · \(Int(iface.transmitRate())) Mbps"
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
