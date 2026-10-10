import SwiftUI

struct ContentView: View {
    @StateObject private var scanner = NetworkScanner()
    @StateObject private var location = LocationAuth()
    @ObservedObject private var updater = UpdateChecker.shared

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
                    || $0.vendorName.localizedCaseInsensitiveContains(search)
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
        .searchable(text: $search, prompt: "Search SSID / BSSID / vendor")
        .onAppear {
            location.request()
            scanner.start()
        }
        .onChange(of: location.isAuthorized) { granted in
            if granted { scanner.scan() }
        }
        .onReceive(scanner.$networks) { list in
            // Drop selected networks that vanished from the new results, otherwise the charts dim everything else
            let ids = Set(list.map(\.id))
            let kept = selection.filter { ids.contains($0) }
            if kept.count != selection.count { selection = kept }
        }
    }

    // MARK: - Table

    private var networkTable: some View {
        Table(filtered, selection: $selection, sortOrder: $sortOrder) {
            // Table allows at most 10 columns, so the vendor logo lives in the SSID cell with the name on hover
            TableColumn("SSID", value: \.ssid) { n in
                HStack(spacing: 5) {
                    if !n.bssid.isEmpty {
                        VendorLogo(vendor: n.vendor)
                    }
                    if n.isCurrent {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    Text(n.displaySSID).foregroundStyle(n.ssid.isEmpty ? Color.secondary : Color.primary)
                }
            }
            .width(min: 140, ideal: 180)
            TableColumn("BSSID", value: \.bssid) { n in
                Text(n.bssid.isEmpty ? "—" : n.bssid).font(.system(.body, design: .monospaced))
            }
            .width(min: 130, ideal: 150)
            TableColumn("Signal", value: \.rssi) { n in
                SignalCell(rssi: n.rssi)
            }
            .width(min: 90, ideal: 110)
            TableColumn("Noise", value: \.noise) { Text($0.hasNoise ? "\($0.noise) dBm" : "—") }
                .width(min: 60, ideal: 70)
            TableColumn("SNR", value: \.snrSortKey) { Text($0.snr.map { "\($0) dB" } ?? "—") }
                .width(min: 50, ideal: 60)
            TableColumn("Band", value: \.bandLabel) { BandBadge(band: $0.band) }
                .width(min: 60, ideal: 70)
            TableColumn("Channel", value: \.channel) { Text("\($0.channel)") }
                .width(min: 40, ideal: 50)
            TableColumn("Width", value: \.widthMHz) { Text("\($0.widthMHz) MHz") }
                .width(min: 60, ideal: 70)
            TableColumn("Security", value: \.security)
                .width(min: 80, ideal: 100)
            TableColumn("PHY", value: \.phyMode)
                .width(min: 90, ideal: 110)
        }
    }

    // MARK: - Other

    private var permissionBanner: some View {
        HStack {
            Image(systemName: "location.slash").foregroundStyle(.orange)
            if location.isDenied {
                Text("Location access denied: macOS won't reveal SSIDs/BSSIDs, so only signal and channel are shown.")
                Spacer()
                Button("Open System Settings") { location.openSystemSettings() }
            } else {
                Text("Location permission is required to show SSIDs/BSSIDs (a macOS requirement).")
                Spacer()
                Button("Allow") { location.request() }
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
                    Text(verbatim: "\(b.label): \(scanner.networks.filter { $0.band == b }.count)")
                }
            }
            if let status = updater.status {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text(status)
                }
            }
            if let err = scanner.lastError {
                Text(err).foregroundStyle(.red)
            } else if let t = scanner.lastScan {
                Text("Updated \(t.formatted(date: .omitted, time: .standard))")
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
            Picker("Band", selection: $bandFilter) {
                ForEach(BandFilter.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Toggle("Auto Refresh", isOn: $scanner.autoRefresh)
            // A menu-style Picker renders an empty label in the macOS 26 toolbar, so show the value ourselves
            Menu {
                Picker("Interval", selection: $scanner.interval) {
                    ForEach([5, 10, 30, 60], id: \.self) { s in
                        Text("\(s) s").tag(Double(s))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                    Text("\(Int(scanner.interval)) s").monospacedDigit()
                }
            }
            .fixedSize()
            .help("Refresh interval")
            Button {
                scanner.scan()
            } label: {
                if scanner.isScanning {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Scan", systemImage: "arrow.clockwise")
                }
            }
            .keyboardShortcut("r")
            .disabled(scanner.isScanning)
            Button {
                showDetail.toggle()
            } label: {
                Label("Details", systemImage: "sidebar.right")
            }
            .keyboardShortcut("i")
        }
    }
}
