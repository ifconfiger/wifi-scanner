import SwiftUI

struct ContentView: View {
    @StateObject private var scanner = WiFiScanner()
    @StateObject private var location = LocationAuth()

    @State private var bandFilter: BandFilter = .all
    @State private var search = ""
    @State private var selection = Set<WiFiNetwork.ID>()
    @State private var sortOrder = [KeyPathComparator(\WiFiNetwork.rssi, order: .reverse)]
    @State private var showDetail = true

    private var filtered: [WiFiNetwork] {
        scanner.networks
            .filter { bandFilter.matches($0.band) }
            .filter {
                search.isEmpty
                    || $0.ssid.localizedCaseInsensitiveContains(search)
                    || $0.bssid.localizedCaseInsensitiveContains(search)
            }
            .sorted(using: sortOrder)
    }

    private var selectedNetwork: WiFiNetwork? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return scanner.networks.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !location.isAuthorized {
                permissionBanner
            }
            HSplitView {
                VSplitView {
                    networkTable
                        .frame(minHeight: 200)
                    ChartsPanel(
                        networks: filtered,
                        history: scanner.history,
                        bandFilter: bandFilter,
                        selection: $selection
                    )
                    .frame(minHeight: 280)
                }
                .frame(minWidth: 680)

                if showDetail {
                    DetailPanel(
                        network: selectedNetwork,
                        allNetworks: scanner.networks,
                        samples: selectedNetwork.flatMap { scanner.history[$0.bssid] } ?? [],
                        firstSeen: selectedNetwork.flatMap { scanner.firstSeen[$0.bssid] },
                        selectionCount: selection.count
                    )
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 460)
                }
            }
            statusBar
        }
        .toolbar { toolbarContent }
        .searchable(text: $search, prompt: "搜索 SSID / BSSID")
        .onAppear {
            location.request()
            scanner.start()
        }
        .onChange(of: location.isAuthorized) { granted in
            if granted { scanner.scan() }
        }
    }

    // MARK: - 表格

    private var networkTable: some View {
        Table(filtered, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("SSID", value: \.ssid) { n in
                HStack(spacing: 4) {
                    if n.isCurrent {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    Text(n.displaySSID).foregroundStyle(n.ssid.isEmpty ? .secondary : .primary)
                }
            }
            .width(min: 140, ideal: 180)
            TableColumn("BSSID", value: \.bssid) { n in
                Text(n.bssid.isEmpty ? "—" : n.bssid).font(.system(.body, design: .monospaced))
            }
            .width(min: 130, ideal: 150)
            TableColumn("信号", value: \.rssi) { n in
                SignalCell(rssi: n.rssi)
            }
            .width(min: 90, ideal: 110)
            TableColumn("噪声", value: \.noise) { Text("\($0.noise) dBm") }
                .width(min: 60, ideal: 70)
            TableColumn("SNR", value: \.snr) { Text("\($0.snr) dB") }
                .width(min: 50, ideal: 60)
            TableColumn("频段", value: \.bandLabel) { BandBadge(band: $0.band) }
                .width(min: 60, ideal: 70)
            TableColumn("信道", value: \.channel) { Text("\($0.channel)") }
                .width(min: 40, ideal: 50)
            TableColumn("带宽", value: \.widthMHz) { Text("\($0.widthMHz) MHz") }
                .width(min: 60, ideal: 70)
            TableColumn("安全", value: \.security)
                .width(min: 80, ideal: 100)
            TableColumn("协议", value: \.phyMode)
                .width(min: 90, ideal: 110)
        }
    }

    // MARK: - 其他

    private var permissionBanner: some View {
        HStack {
            Image(systemName: "location.slash").foregroundStyle(.orange)
            Text(location.isDenied
                 ? "定位权限被拒绝：macOS 不允许读取 SSID/BSSID，列表只能显示信号与信道。"
                 : "需要定位权限才能显示 SSID/BSSID（macOS 系统要求）。")
            Spacer()
            Button(location.isDenied ? "打开系统设置" : "授权") {
                location.isDenied ? location.openSystemSettings() : location.request()
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.12))
    }

    private var statusBar: some View {
        HStack(spacing: 16) {
            Text(scanner.currentLink)
            Spacer()
            ForEach(Band.scannable) { b in
                HStack(spacing: 4) {
                    Circle().fill(b.color).frame(width: 7, height: 7)
                    Text("\(b.rawValue)：\(scanner.networks.filter { $0.band == b }.count)")
                }
            }
            if let err = scanner.lastError {
                Text(err).foregroundStyle(.red)
            } else if let t = scanner.lastScan {
                Text("更新于 \(t.formatted(date: .omitted, time: .standard))")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.bar)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker("频段", selection: $bandFilter) {
                ForEach(BandFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Toggle("自动刷新", isOn: $scanner.autoRefresh)
            Picker("间隔", selection: $scanner.interval) {
                Text("5 秒").tag(5.0)
                Text("10 秒").tag(10.0)
                Text("30 秒").tag(30.0)
                Text("60 秒").tag(60.0)
            }
            .frame(width: 90)
            Button {
                scanner.scan()
            } label: {
                if scanner.isScanning {
                    ProgressView().controlSize(.small)
                } else {
                    Label("扫描", systemImage: "arrow.clockwise")
                }
            }
            .keyboardShortcut("r")
            .disabled(scanner.isScanning)
            Button {
                showDetail.toggle()
            } label: {
                Label("详情", systemImage: "sidebar.right")
            }
            .keyboardShortcut("i")
        }
    }
}
