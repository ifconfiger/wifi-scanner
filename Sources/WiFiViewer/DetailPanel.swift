import AppKit
import Charts
import SwiftUI

/// Right-hand detail panel: all fields, channel environment and signal history for a single selected network
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
                    Group {
                        if selectionCount > 1 {
                            Text("\(selectionCount) networks selected")
                        } else {
                            Text("Select a network to see details")
                        }
                    }
                    .foregroundStyle(.secondary)
                    Text("Click one in the list or a chart").font(.caption).foregroundStyle(.tertiary)
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

            section(String(localized: "Basics"), [
                (.ssid, n.displaySSID),
                (.bssid, n.bssid.isEmpty ? String(localized: "— (location permission required)") : n.bssid),
                (.vendor, n.vendor.map { $0.isGuess ? String(localized: "\($0.brand) (guessed)") : $0.brand }
                    ?? (n.bssid.isEmpty ? "—" : String(localized: "Unknown"))),
                (.security, n.security),
                (.phy, n.phyMode.isEmpty ? "—" : n.phyMode),
                (.country, n.countryCode.isEmpty ? "—" : n.countryCode),
                (.networkType, n.isIBSS ? String(localized: "Ad-hoc (IBSS)") : String(localized: "Infrastructure")),
            ])

            section(String(localized: "Radio"), [
                (.band, n.band.label),
                (.primaryChannel, "\(n.channel)"),
                (.centerChannel, n.band == .ghz24 && n.widthMHz >= 40
                    ? String(localized: "\(Int(n.centerChannel)) (estimated)") : "\(Int(n.centerChannel))"),
                (.primaryFrequency, "\(n.frequencyMHz) MHz"),
                (.occupiedRange, "\(n.centerFrequencyMHz - n.widthMHz / 2) – \(n.centerFrequencyMHz + n.widthMHz / 2) MHz"),
                (.channelWidth, "\(n.widthMHz) MHz"),
                (.beaconInterval, "\(n.beaconInterval) TU (≈ \(Int(Double(n.beaconInterval) * 1.024)) ms)"),
            ])

            section(String(localized: "Signal"), [
                (.signalStrength, "\(n.rssi) dBm (\(n.quality))"),
                (.noise, n.hasNoise ? "\(n.noise) dBm" : String(localized: "— (connected network only)")),
                (.snr, n.snr.map { "\($0) dB" } ?? "—"),
                (.last5Min, rssis.isEmpty ? "—" : String(localized:
                    "Min \(rssis.min()!) / Avg \(rssis.reduce(0, +) / rssis.count) / Max \(rssis.max()!) dBm")),
                (.firstSeen, firstSeen.map { $0.formatted(date: .omitted, time: .standard) } ?? "—"),
            ])

            section(String(localized: "Channel Environment"), [
                (.coChannel, "\(coChannel.count)"),
                (.overlapping, "\(overlapping.count)"),
                (.stations, n.stationCount.map { String(localized: "\($0) (reported by AP)") }
                    ?? String(localized: "Not broadcast by AP")),
                (.utilization, n.channelUtilization.map { String(localized: "\(Int($0 * 100))% (reported by AP)") }
                    ?? String(localized: "Not broadcast by AP")),
            ])

            if !overlapping.isEmpty {
                GroupBox("Overlapping Networks") {
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
                GroupBox("Signal History") {
                    Chart(samples) { s in
                        AreaMark(x: .value("Time", s.date), y: .value("dBm", s.rssi + 100))
                            .foregroundStyle(n.band.color.opacity(0.18))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Time", s.date), y: .value("dBm", s.rssi + 100))
                            .foregroundStyle(n.band.color)
                            .interpolationMethod(.monotone)
                    }
                    // Area marks start from 0, so shift everything by +100 and map axis labels back to dBm
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

    @ViewBuilder
    private func badges(_ n: WiFiNetwork) -> some View {
        if !n.bssid.isEmpty, n.vendor != nil {
            VendorLogo(vendor: n.vendor, size: 18)
        }
        BandBadge(band: n.band).fixedSize()
        Text("Channel \(n.channel)").font(.caption).foregroundStyle(.secondary).fixedSize()
    }

    @ViewBuilder
    private func connectedLabel(_ n: WiFiNetwork) -> some View {
        if n.isCurrent {
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .fixedSize()
        }
    }

    private func header(_ n: WiFiNetwork) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(n.displaySSID)
                    .font(.title2.bold())
                    .lineLimit(2)
                    .textSelection(.enabled)
                // A narrow inspector can't fit "Connected" beside the badges, so it drops to its own line
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        badges(n)
                        connectedLabel(n)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) { badges(n) }
                        connectedLabel(n)
                    }
                }
                if !n.bssid.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(n.bssid, forType: .string)
                    } label: {
                        Label("Copy BSSID", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            Spacer()
            SignalRing(rssi: n.rssi)
        }
    }

    private func section(_ title: String, _ rows: [(InfoTips.Field, String)]) -> some View {
        GroupBox(title) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                ForEach(rows.indices, id: \.self) { i in
                    GridRow {
                        HStack(spacing: 3) {
                            Text(rows[i].0.title).foregroundStyle(.secondary)
                            InfoTipButton(title: rows[i].0.title, tip: rows[i].0.tip)
                        }
                        .gridColumnAlignment(.trailing)
                        Text(rows[i].1)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            // Without a full-width frame Grid under-measures wrapped values and the rows spill over the box title
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        }
    }
}

/// Ring-shaped signal strength indicator
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
