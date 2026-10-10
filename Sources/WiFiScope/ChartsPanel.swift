import Charts
import SwiftUI

enum ChartMode: String, CaseIterable, Identifiable {
    case spectrum, ranking, congestion, history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spectrum: return String(localized: "Channels")
        case .ranking: return String(localized: "Signal Ranking")
        case .congestion: return String(localized: "Congestion")
        case .history: return String(localized: "Signal History")
        }
    }

    var icon: String {
        switch self {
        case .spectrum: return "waveform.path.ecg"
        case .ranking: return "chart.bar.xaxis"
        case .congestion: return "chart.bar.fill"
        case .history: return "chart.xyaxis.line"
        }
    }
}

/// Bottom chart area. The band comes from the toolbar filter; "All" shows one block per band.
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
                ForEach(ChartMode.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
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

    /// A single band fills the area; multiple bands get one scrollable block each
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
            Text(b.label).font(.subheadline.weight(.semibold))
            Text("\(networks.filter { $0.band == b }.count) networks")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Channels: one trapezoid per AP; x = channel, y = signal, SSID labeled on top

struct SpectrumChart: View {
    let networks: [WiFiNetwork]
    let band: Band
    let selection: Set<String>
    let onSelect: (String?) -> Void

    var body: some View {
        // Same name, same color; networks without an SSID (hidden / no permission) are colored by id so they don't all share one
        let colorKey = { (n: WiFiNetwork) in n.ssid.isEmpty ? n.id : n.ssid }
        let colors = Palette.assign(networks.map(colorKey))
        // Corner rounding scales with the axis so it looks the same on every band
        let cornerX = (band.channelDomain.upperBound - band.channelDomain.lowerBound) * 0.012
        Chart {
            ForEach(networks) { n in
                let selected = selection.contains(n.id)
                let dimmed = !selection.isEmpty && !selected
                let color = colors[colorKey(n)] ?? .accentColor
                ForEach(Array(n.spectrumShape(cornerX: cornerX, cornerY: 5).enumerated()), id: \.offset) { _, p in
                    // Translucent gradient fill + solid stroke; explicit colors instead of foregroundStyle(by:), whose defaults look washed out
                    AreaMark(
                        x: .value("Channel", p.x),
                        yStart: .value("Floor", -100.0),
                        yEnd: .value("dBm", p.y),
                        series: .value("BSSID", n.id)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [color.opacity(selected ? 0.45 : 0.16), color.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .opacity(dimmed ? 0.15 : 1)
                    LineMark(
                        x: .value("Channel", p.x),
                        y: .value("dBm", p.y),
                        series: .value("BSSID", n.id)
                    )
                    // With many networks the curves crowd together, so strokes are slightly transparent; only the selection is solid
                    .foregroundStyle(color.opacity(selected ? 1 : 0.7))
                    .lineStyle(StrokeStyle(lineWidth: selected ? 3 : 1.6, lineJoin: .round))
                    .opacity(dimmed ? 0.25 : 1)
                }
                // Only carries the SSID annotation: the point itself is invisible (symbolSize(0), since opacity would hide the annotation too)
                PointMark(x: .value("Channel", n.centerChannel), y: .value("dBm", Double(n.rssi)))
                    .symbolSize(0)
                    .annotation(position: .top, spacing: 1) {
                        Text(n.displaySSID)
                            .font(.system(size: 9, weight: selected ? .bold : .medium))
                            .foregroundStyle(color)
                            .opacity(dimmed ? 0.3 : 1)
                    }
            }
        }
        .chartXScale(domain: band.channelDomain)
        .chartYScale(domain: -100 ... -20)
        .chartXAxis { AxisMarks(values: band.axisTicks) }
        .chartXAxisLabel("Channel")
        .chartYAxisLabel("dBm")
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            // Click a curve to select it; click empty space to deselect
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
                Text("No networks found in this band").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Signal ranking: horizontal bars colored by band

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
                        Text(b.label).font(.caption)
                    }
                }
                Spacer()
                Text("Sorted by signal strength, up to 60 shown").font(.caption).foregroundStyle(.secondary)
            }
            if rows.isEmpty {
                Spacer()
                Text("No networks").foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    Chart(rows) { item in
                        BarMark(
                            xStart: .value("dBm", -100),
                            xEnd: .value("dBm", item.n.rssi),
                            y: .value("Network", item.label)
                        )
                        .foregroundStyle(by: .value("Band", item.n.band.rawValue))
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

// MARK: - Congestion: AP count per primary channel, stacked by signal strength

struct CongestionChart: View {
    let networks: [WiFiNetwork]

    private static let levels = [
        String(localized: "Strong (≥ -60)"), String(localized: "Medium (-75 ~ -60)"), String(localized: "Weak (< -75)"),
    ]

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
                x: .value("Channel", String(b.channel)),
                y: .value("APs", b.count)
            )
            .foregroundStyle(by: .value("Strength", b.level))
        }
        .chartXScale(domain: channels)
        .chartForegroundStyleScale(domain: Self.levels, range: [Color.green, .yellow, .red])
        .chartLegend(position: .top, alignment: .trailing)
        .chartXAxisLabel("Primary Channel")
        .chartYAxisLabel("APs")
        .overlay {
            if networks.isEmpty {
                Text("No networks found in this band").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Signal history

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
            Group {
                if selection.isEmpty {
                    Text("Last 5 minutes (5 strongest)")
                } else {
                    Text("Last 5 minutes (\(selection.count) selected)")
                }
            }
                .font(.caption)
                .foregroundStyle(.secondary)
            if series.isEmpty {
                Spacer()
                Text("No data yet (location permission is needed to track history by BSSID)")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                Chart {
                    ForEach(series) { s in
                        ForEach(s.samples) { sample in
                            LineMark(
                                x: .value("Time", sample.date),
                                y: .value("dBm", sample.rssi),
                                series: .value("BSSID", s.id)
                            )
                            .foregroundStyle(by: .value("Network", s.label))
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
