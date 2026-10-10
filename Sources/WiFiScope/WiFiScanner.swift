import Combine
import CoreWLAN
import Foundation
import SwiftUI

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
        showCached()
        scan()
        scheduleTimer()
    }

    /// 系统最近一次扫描的缓存，几乎零耗时；启动时先展示，不用干等第一轮完整扫描（约 3~5 秒）
    private func showCached() {
        guard let iface = client.interface(), iface.powerOn() else { return }
        Task {
            let list = await Task.detached(priority: .userInitiated) {
                Self.build(iface.cachedScanResults() ?? [], current: iface.bssid())
            }.value
            // 真实扫描已经先回来就不用缓存了
            if networks.isEmpty { insertNew(list) }
        }
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

        // CoreWLAN 的扫描是阻塞调用、一次性返回全部结果，没有逐个回调的公开 API。
        // 扫描期间轮询系统缓存，缓存里出现的新网络先插进列表，扫完再用完整结果校正。
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
                    // ssid=nil 表示扫描全部；includeHidden 带上隐藏网络
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
                lastError = "扫描失败：\(error.localizedDescription)"
            }
            updateCurrentLink(iface)
            isScanning = false
        }
    }

    private nonisolated static func build(_ found: Set<CWNetwork>, current: String?) -> [WiFiNetwork] {
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
        // CoreWLAN 偶尔把同一个 BSS 返回多次（常见于路由器的隐藏 SSID），字段完全相同。
        // BSSID 是行 id，重复会让表格选中一个就选中全部，按 BSSID 合并，优先保留有名字的那条
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
        return out
    }

    /// 只追加列表里还没有的网络，已有的不动，避免缓存里的旧信号值把数字往回拉
    private func insertNew(_ list: [WiFiNetwork]) {
        let known = Set(networks.map(\.id))
        // 系统缓存里常混着没有 BSSID 的条目，和带 BSSID 的同一个网络对不上 id，会变成重复行。
        // 能拿到 BSSID（有定位权限）时就只收带 BSSID 的
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
