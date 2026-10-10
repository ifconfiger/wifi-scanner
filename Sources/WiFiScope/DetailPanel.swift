import AppKit
import Charts
import SwiftUI

/// 右侧详情面板：选中单个网络时展示全部字段、信道环境与信号历史
struct DetailPanel: View {
    let network: WiFiNetwork?
    let allNetworks: [WiFiNetwork]
    let samples: [SignalSample]
    let firstSeen: Date?
    let selectionCount: Int

    var body: some View {
        Group {
            if let n = network {
                ScrollView {
                    content(n).padding(14)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "wifi").font(.system(size: 40)).foregroundStyle(.tertiary)
                    Text(selectionCount > 1 ? "已选择 \(selectionCount) 个网络" : "选择一个网络查看详情")
                        .foregroundStyle(.secondary)
                    Text("可在列表或图表里点选").font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func content(_ n: WiFiNetwork) -> some View {
        let coChannel = allNetworks.filter { n.isCoChannel(with: $0) }
        let overlapping = allNetworks.filter { n.overlaps($0) }
        let rssis = samples.map(\.rssi)

        VStack(alignment: .leading, spacing: 14) {
            header(n)

            section("基本信息", [
                ("SSID", n.displaySSID),
                ("BSSID", n.bssid.isEmpty ? "—（需定位权限）" : n.bssid),
                ("厂商", n.vendor.map { "\($0.brand)\($0.isGuess ? "（推测）" : "")" } ?? (n.bssid.isEmpty ? "—" : "未知")),
                ("安全", n.security),
                ("协议", n.phyMode.isEmpty ? "—" : n.phyMode),
                ("国家/地区", n.countryCode.isEmpty ? "—" : n.countryCode),
                ("网络类型", n.isIBSS ? "点对点 (IBSS)" : "基础设施"),
            ])

            section("射频", [
                ("频段", n.band.rawValue),
                ("主信道", "\(n.channel)"),
                ("中心信道", "\(Int(n.centerChannel))\(n.band == .ghz24 && n.widthMHz >= 40 ? "（估算）" : "")"),
                ("主信道频率", "\(n.frequencyMHz) MHz"),
                ("占用频率", "\(n.centerFrequencyMHz - n.widthMHz / 2) – \(n.centerFrequencyMHz + n.widthMHz / 2) MHz"),
                ("信道带宽", "\(n.widthMHz) MHz"),
                ("信标间隔", "\(n.beaconInterval) TU（≈ \(Int(Double(n.beaconInterval) * 1.024)) ms）"),
            ])

            section("信号", [
                ("信号强度", "\(n.rssi) dBm（\(n.quality)）"),
                ("噪声", n.hasNoise ? "\(n.noise) dBm" : "—（仅当前连接可测）"),
                ("信噪比", n.snr.map { "\($0) dB" } ?? "—"),
                ("最近 5 分钟", rssis.isEmpty ? "—" :
                    "最低 \(rssis.min()!) / 平均 \(rssis.reduce(0, +) / rssis.count) / 最高 \(rssis.max()!) dBm"),
                ("首次发现", firstSeen.map { $0.formatted(date: .omitted, time: .standard) } ?? "—"),
            ])

            section("信道环境", [
                ("同信道 AP", "\(coChannel.count) 个"),
                ("频谱重叠 AP", "\(overlapping.count) 个"),
                ("已连接设备", n.stationCount.map { "\($0) 台（AP 广播）" } ?? "AP 未广播"),
                ("信道利用率", n.channelUtilization.map { "\(Int($0 * 100))%（AP 广播）" } ?? "AP 未广播"),
            ])

            if !overlapping.isEmpty {
                GroupBox("重叠的网络") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(overlapping.sorted { $0.rssi > $1.rssi }.prefix(10)) { o in
                            HStack {
                                Text(o.displaySSID).lineLimit(1)
                                Spacer()
                                Text("ch\(o.channel) · \(o.rssi) dBm")
                                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if samples.count >= 2 {
                GroupBox("信号历史") {
                    Chart(samples) { s in
                        AreaMark(x: .value("时间", s.date), y: .value("dBm", s.rssi + 100))
                            .foregroundStyle(n.band.color.opacity(0.18))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("时间", s.date), y: .value("dBm", s.rssi + 100))
                            .foregroundStyle(n.band.color)
                            .interpolationMethod(.monotone)
                    }
                    // 面积图从 0 起画，所以整体平移 +100，轴标签再还原成 dBm
                    .chartYScale(domain: 0...80)
                    .chartYAxis {
                        AxisMarks(values: [0, 20, 40, 60, 80]) { v in
                            AxisGridLine()
                            AxisValueLabel { Text("\((v.as(Int.self) ?? 0) - 100)") }
                        }
                    }
                    .frame(height: 120)
                }
            }
        }
    }

    private func header(_ n: WiFiNetwork) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(n.displaySSID)
                    .font(.title2.bold())
                    .lineLimit(2)
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    if !n.bssid.isEmpty {
                        VendorLogo(vendor: n.vendor, size: 18)
                    }
                    BandBadge(band: n.band)
                    Text("信道 \(n.channel)").font(.caption).foregroundStyle(.secondary)
                    if n.isCurrent {
                        Label("已连接", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                if !n.bssid.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(n.bssid, forType: .string)
                    } label: {
                        Label("复制 BSSID", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            Spacer()
            SignalRing(rssi: n.rssi)
        }
    }

    private func section(_ title: String, _ rows: [(String, String)]) -> some View {
        GroupBox(title) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                ForEach(rows.indices, id: \.self) { i in
                    GridRow {
                        HStack(spacing: 3) {
                            Text(rows[i].0).foregroundStyle(.secondary)
                            if let tip = InfoTips.all[rows[i].0] {
                                InfoTipButton(title: rows[i].0, tip: tip)
                            }
                        }
                        .gridColumnAlignment(.trailing)
                        Text(rows[i].1)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        }
    }
}

/// 环形信号强度指示
struct SignalRing: View {
    let rssi: Int

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 7)
            Circle()
                .trim(from: 0, to: signalFraction(rssi))
                .stroke(signalColor(rssi), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(rssi)").font(.title3.bold()).monospacedDigit()
                Text("dBm").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 70, height: 70)
    }
}
