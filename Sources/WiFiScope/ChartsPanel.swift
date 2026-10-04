import Charts
import SwiftUI

enum ChartMode: String, CaseIterable, Identifiable {
    case spectrum = "信道分布"
    case ranking = "信号排行"
    case congestion = "信道拥挤度"
    case history = "信号历史"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .spectrum: return "waveform.path.ecg"
        case .ranking: return "chart.bar.xaxis"
        case .congestion: return "chart.bar.fill"
        case .history: return "chart.xyaxis.line"
        }
    }
}

/// 下半区图表。频段由工具栏的筛选控制；选“全部”时按频段分块展示。
struct ChartsPanel: View {
    let networks: [WiFiNetwork]
    let history: [String: [SignalSample]]
    let bandFilter: BandFilter
    @Binding var selection: Set<String>
    @State private var mode: ChartMode = .spectrum

    private var bands: [Band] {
        if let b = bandFilter.band { return [b] }
        let present = Band.scannable.filter { b in networks.contains { $0.band == b } }
        return present.isEmpty ? Band.scannable : present
    }

    private func select(_ id: String?) {
        selection = id.map { [$0] } ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $mode) {
                ForEach(ChartMode.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 520)

            switch mode {
            case .spectrum:
                perBand { band in
                    SpectrumChart(
                        networks: networks.filter { $0.band == band },
                        band: band,
                        selection: selection,
                        onSelect: select
                    )
                }
            case .congestion:
                perBand { band in
                    CongestionChart(networks: networks.filter { $0.band == band })
                }
            case .ranking:
                RankingChart(networks: networks, selection: selection, onSelect: select)
            case .history:
                HistoryChart(networks: networks, history: history, selection: selection)
            }
        }
        .padding(10)
    }

    /// 单频段时铺满；多频段时每个频段一块，可滚动
    @ViewBuilder
    private func perBand<C: View>(@ViewBuilder _ chart: @escaping (Band) -> C) -> some View {
        if bands.count == 1, let b = bands.first {
            VStack(alignment: .leading, spacing: 4) {
                bandHeader(b)
                chart(b)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(bands) { b in
                        VStack(alignment: .leading, spacing: 4) {
                            bandHeader(b)
                            chart(b).frame(height: 210)
                        }
                    }
                }
                .padding(.trailing, 8)
            }
        }
    }

    private func bandHeader(_ b: Band) -> some View {
        HStack(spacing: 6) {
            Circle().fill(b.color).frame(width: 8, height: 8)
            Text(b.rawValue).font(.subheadline.weight(.semibold))
            Text("\(networks.filter { $0.band == b }.count) 个网络")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 信道分布：每个 AP 一条梯形，横轴信道、纵轴信号强度、顶部标注 SSID

struct SpectrumChart: View {
    let networks: [WiFiNetwork]
    let band: Band
    let selection: Set<String>
    let onSelect: (String?) -> Void

    var body: some View {
        Chart {
            ForEach(networks) { n in
                let dimmed = !selection.isEmpty && !selection.contains(n.id)
                ForEach(Array(n.spectrumShape().enumerated()), id: \.offset) { _, p in
                    LineMark(
                        x: .value("信道", p.x),
                        y: .value("dBm", p.y),
                        series: .value("BSSID", n.id)
                    )
                    .foregroundStyle(by: .value("SSID", n.displaySSID))
                    .lineStyle(StrokeStyle(lineWidth: selection.contains(n.id) ? 3 : 1.4))
                    .opacity(dimmed ? 0.2 : 1)
                }
                // 只用来挂 SSID 标注：点本身不画（用 symbolSize(0)，避免 opacity 把标注也隐藏）
                PointMark(x: .value("信道", n.centerChannel), y: .value("dBm", Double(n.rssi)))
                    .symbolSize(0)
                    .annotation(position: .top, spacing: 1) {
                        Text(n.displaySSID)
                            .font(.system(size: 9, weight: selection.contains(n.id) ? .bold : .regular))
                            .foregroundStyle(.secondary)
                            .opacity(dimmed ? 0.3 : 1)
                    }
            }
        }
        .chartXScale(domain: band.channelDomain)
        .chartYScale(domain: -100 ... -20)
        .chartXAxis { AxisMarks(values: band.axisTicks) }
        .chartXAxisLabel("信道")
        .chartYAxisLabel("dBm")
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            // 点击曲线选中网络；点空白处取消选择
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { loc in
                        let origin = geo[proxy.plotAreaFrame].origin
                        guard let ch: Double = proxy.value(atX: loc.x - origin.x),
                              let db: Double = proxy.value(atY: loc.y - origin.y)
                        else { return }
                        let hit = networks
                            .filter { abs($0.centerChannel - ch) <= $0.halfSpan && Double($0.rssi) >= db }
                            .min { $0.rssi < $1.rssi }
                        onSelect(hit?.id)
                    }
            }
        }
        .overlay {
            if networks.isEmpty {
                Text("该频段没有扫描到网络").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 信号排行：横向条形图，按频段着色

struct RankingChart: View {
    let networks: [WiFiNetwork]
    let selection: Set<String>
    let onSelect: (String?) -> Void

    private struct Item: Identifiable {
        let n: WiFiNetwork
        let label: String
        var id: String { n.id }
    }

    private var items: [Item] {
        networks.sorted { $0.rssi > $1.rssi }.prefix(60).enumerated().map { i, n in
            let tail = n.bssid.isEmpty ? "#\(i + 1)" : String(n.bssid.suffix(5))
            return Item(n: n, label: "\(n.displaySSID) · ch\(n.channel) · \(tail)")
        }
    }

    var body: some View {
        let rows = items
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                ForEach(Band.scannable) { b in
                    HStack(spacing: 4) {
                        Circle().fill(b.color).frame(width: 8, height: 8)
                        Text(b.rawValue).font(.caption)
                    }
                }
                Spacer()
                Text("按信号强度排序，最多显示 60 个").font(.caption).foregroundStyle(.secondary)
            }
            if rows.isEmpty {
                Spacer()
                Text("没有网络").foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    Chart(rows) { item in
                        BarMark(
                            xStart: .value("dBm", -100),
                            xEnd: .value("dBm", item.n.rssi),
                            y: .value("网络", item.label)
                        )
                        .foregroundStyle(by: .value("频段", item.n.band.rawValue))
                        .opacity(selection.isEmpty || selection.contains(item.id) ? 1 : 0.3)
                        .annotation(position: .trailing, spacing: 4) {
                            Text("\(item.n.rssi)").font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    .chartXScale(domain: -100 ... -20)
                    .chartForegroundStyleScale(
                        domain: Band.allCases.map(\.rawValue),
                        range: Band.allCases.map(\.color)
                    )
                    .chartLegend(.hidden)
                    .chartOverlay { proxy in
                        GeometryReader { geo in
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .onTapGesture { loc in
                                    let origin = geo[proxy.plotAreaFrame].origin
                                    let label: String? = proxy.value(atY: loc.y - origin.y)
                                    onSelect(rows.first { $0.label == label }?.id)
                                }
                        }
                    }
                    .frame(height: CGFloat(rows.count) * 22 + 40)
                    .padding(.trailing, 8)
                }
            }
        }
    }
}

// MARK: - 信道拥挤度：每个主信道上的 AP 数，按信号强弱堆叠

struct CongestionChart: View {
    let networks: [WiFiNetwork]

    private static let levels = ["强 (≥ -60)", "中 (-75 ~ -60)", "弱 (< -75)"]

    private struct Bucket: Identifiable {
        let channel: Int
        let level: String
        let count: Int
        var id: String { "\(channel)-\(level)" }
    }

    private var buckets: [Bucket] {
        let byChannel = Dictionary(grouping: networks, by: \.channel)
        return byChannel.keys.sorted().flatMap { ch -> [Bucket] in
            let list = byChannel[ch] ?? []
            let counts = [
                list.filter { $0.rssi >= -60 }.count,
                list.filter { $0.rssi < -60 && $0.rssi >= -75 }.count,
                list.filter { $0.rssi < -75 }.count,
            ]
            return zip(Self.levels, counts).compactMap { level, c in
                c > 0 ? Bucket(channel: ch, level: level, count: c) : nil
            }
        }
    }

    var body: some View {
        let channels = Set(networks.map(\.channel)).sorted().map(String.init)
        Chart(buckets) { b in
            BarMark(
                x: .value("信道", String(b.channel)),
                y: .value("AP 数", b.count)
            )
            .foregroundStyle(by: .value("强度", b.level))
        }
        .chartXScale(domain: channels)
        .chartForegroundStyleScale(domain: Self.levels, range: [Color.green, .yellow, .red])
        .chartLegend(position: .top, alignment: .trailing)
        .chartXAxisLabel("主信道")
        .chartYAxisLabel("AP 数")
        .overlay {
            if networks.isEmpty {
                Text("该频段没有扫描到网络").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 信号历史

struct HistorySeries: Identifiable {
    let id: String
    let label: String
    let samples: [SignalSample]
}

struct HistoryChart: View {
    let networks: [WiFiNetwork]
    let history: [String: [SignalSample]]
    let selection: Set<String>

    var body: some View {
        let ids: [String] = selection.isEmpty
            ? networks.sorted { $0.rssi > $1.rssi }.prefix(5).map(\.bssid)
            : Array(selection)
        let series = ids.compactMap { id -> HistorySeries? in
            guard let samples = history[id] else { return nil }
            let name = networks.first { $0.bssid == id }?.displaySSID ?? id
            return HistorySeries(id: id, label: "\(name) (\(id.suffix(5)))", samples: samples)
        }
        VStack(alignment: .leading, spacing: 4) {
            Text(selection.isEmpty ? "最近 5 分钟（信号最强的 5 个）" : "最近 5 分钟（已选 \(selection.count) 个）")
                .font(.caption)
                .foregroundStyle(.secondary)
            if series.isEmpty {
                Spacer()
                Text("暂无数据（需要定位权限才能按 BSSID 记录历史）")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                Chart {
                    ForEach(series) { s in
                        ForEach(s.samples) { sample in
                            LineMark(
                                x: .value("时间", sample.date),
                                y: .value("dBm", sample.rssi),
                                series: .value("BSSID", s.id)
                            )
                            .foregroundStyle(by: .value("网络", s.label))
                            .interpolationMethod(.monotone)
                        }
                    }
                }
                .chartYScale(domain: -100 ... -20)
                .chartLegend(position: .bottom, alignment: .leading)
            }
        }
    }
}
