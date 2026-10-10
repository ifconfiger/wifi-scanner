import SwiftUI

/// Field help for the detail panel: an explanation plus optional good/bad levels
struct InfoTip {
    struct Level {
        let range: String
        let label: String
        let color: Color
    }

    let text: String
    var levels: [Level] = []
}

extension InfoTip.Level {
    static func level(_ range: String, _ label: String, _ color: Color) -> Self {
        Self(range: range, label: label, color: color)
    }
}

enum InfoTips {
    /// Detail panel rows; each has a title and a help tip
    enum Field {
        // Basics
        case ssid, bssid, vendor, security, phy, country, networkType
        // Radio
        case band, primaryChannel, centerChannel, primaryFrequency, occupiedRange, channelWidth, beaconInterval
        // Signal
        case signalStrength, noise, snr, last5Min, firstSeen
        // Channel environment
        case coChannel, overlapping, stations, utilization

        var title: String {
            switch self {
            case .ssid: return "SSID"
            case .bssid: return "BSSID"
            case .vendor: return String(localized: "Vendor")
            case .security: return String(localized: "Security")
            case .phy: return String(localized: "PHY")
            case .country: return String(localized: "Country/Region")
            case .networkType: return String(localized: "Network Type")
            case .band: return String(localized: "Band")
            case .primaryChannel: return String(localized: "Primary Channel")
            case .centerChannel: return String(localized: "Center Channel")
            case .primaryFrequency: return String(localized: "Primary Frequency")
            case .occupiedRange: return String(localized: "Occupied Range")
            case .channelWidth: return String(localized: "Channel Width")
            case .beaconInterval: return String(localized: "Beacon Interval")
            case .signalStrength: return String(localized: "Signal Strength")
            case .noise: return String(localized: "Noise")
            case .snr: return String(localized: "SNR")
            case .last5Min: return String(localized: "Last 5 Minutes")
            case .firstSeen: return String(localized: "First Seen")
            case .coChannel: return String(localized: "Co-channel APs")
            case .overlapping: return String(localized: "Overlapping APs")
            case .stations: return String(localized: "Connected Clients")
            case .utilization: return String(localized: "Channel Utilization")
            }
        }

        var tip: InfoTip {
            switch self {
            case .ssid:
                return InfoTip(text: String(localized: "The network name. Hidden networks don't broadcast it, and macOS won't reveal it without location permission; both show as “hidden / no permission”."))
            case .bssid:
                return InfoTip(text: String(localized: "The MAC address of one AP radio. One SSID can have many BSSIDs (several APs, or one per 2.4/5/6 GHz radio on the same AP). macOS requires location permission to read it."))
            case .vendor:
                return InfoTip(text: String(localized: "Looked up from the first 3 bytes of the BSSID (OUI) in the IEEE registry. “Guessed” means a virtual BSSID (locally administered address) whose vendor was inferred from the restored OUI and may be wrong; phone hotspots usually use random addresses and can't be identified."))
            case .security:
                return InfoTip(text: String(localized: "Authentication / encryption method."), levels: [
                    .level("WPA3", String(localized: "Recommended"), .green),
                    .level("WPA2/WPA3", String(localized: "Good (works with older devices)"), .green),
                    .level("WPA2", String(localized: "Acceptable"), .yellow),
                    .level("WPA / WEP", String(localized: "No longer secure"), .red),
                    .level(String(localized: "Open"), String(localized: "Unencrypted; traffic can be sniffed"), .red),
                ])
            case .phy:
                return InfoTip(text: String(localized: "The newest Wi-Fi generation the AP supports (inferred from its information elements). Newer generations are faster and handle many devices better; actual speed also depends on the client."), levels: [
                    .level("be (Wi-Fi 7)", String(localized: "Latest"), .green),
                    .level("ax (Wi-Fi 6/6E)", String(localized: "Mainstream"), .green),
                    .level("ac (Wi-Fi 5)", String(localized: "Adequate"), .yellow),
                    .level(String(localized: "n (Wi-Fi 4) or older"), String(localized: "Legacy; slows down the whole channel"), .orange),
                ])
            case .country:
                return InfoTip(text: String(localized: "The country code broadcast by the AP; it determines the allowed channels and maximum transmit power."))
            case .networkType:
                return InfoTip(text: String(localized: "Infrastructure = a regular router/AP. Ad-hoc (IBSS) = devices connected directly to each other; rare."))
            case .band:
                return InfoTip(text: String(localized: "2.4 GHz penetrates walls and reaches far, but has only 3 non-overlapping channels (1/6/11) and lots of interference. 5 GHz has more channels and is faster but weaker through walls. 6 GHz is the cleanest and fastest with the shortest range, and needs Wi-Fi 6E or newer devices."))
            case .primaryChannel:
                return InfoTip(text: String(localized: "The 20 MHz channel the AP sends beacons on. On 2.4 GHz only 1 / 6 / 11 should be used; other channels interfere with both neighbors."))
            case .centerChannel:
                return InfoTip(text: String(localized: "The center of the bonded 40/80/160 MHz channel; the spectrum chart is drawn around it. For 2.4 GHz 40 MHz the extension direction is unavailable, so it is estimated."))
            case .primaryFrequency:
                return InfoTip(text: String(localized: "The center frequency of the primary channel."))
            case .occupiedRange:
                return InfoTip(text: String(localized: "The frequency range actually occupied given the channel width. APs whose ranges overlap interfere with each other."))
            case .channelWidth:
                return InfoTip(text: String(localized: "Wider channels give higher theoretical speed but overlap neighbors more easily and tolerate interference worse."), levels: [
                    .level("2.4 GHz", String(localized: "20 MHz recommended"), .yellow),
                    .level("5 GHz", String(localized: "80 MHz typical; 40 MHz when crowded"), .green),
                    .level("6 GHz", String(localized: "160 MHz is common too"), .green),
                ])
            case .beaconInterval:
                return InfoTip(text: String(localized: "How often the AP broadcasts beacons; 1 TU = 1.024 ms. The default of 100 TU almost never needs changing; too small wastes airtime, too large hurts discovery and power-save wakeups."))
            case .signalStrength:
                return InfoTip(text: String(localized: "RSSI, the received AP signal power in dBm; closer to 0 is stronger. Every 3 dB is a doubling of power."), levels: [
                    .level("≥ -50 dBm", String(localized: "Excellent: full speed"), .green),
                    .level("-60 ~ -50", String(localized: "Good: video calls and 4K are fine"), .green),
                    .level("-70 ~ -60", String(localized: "Fair: fine for browsing, slower speeds"), .yellow),
                    .level("-80 ~ -70", String(localized: "Weak: stutters and slowdowns"), .orange),
                    .level("< -80 dBm", String(localized: "Poor: frequent disconnects"), .red),
                ])
            case .noise:
                return InfoTip(text: String(localized: "Background noise on the channel; lower (more negative) is better. CoreWLAN only measures the connected network; others show “—”."), levels: [
                    .level("≤ -90 dBm", String(localized: "Quiet"), .green),
                    .level("-90 ~ -80", String(localized: "Some interference"), .yellow),
                    .level("> -80 dBm", String(localized: "Noisy (microwaves, Bluetooth, wireless cameras, …)"), .red),
                ])
            case .snr:
                return InfoTip(text: String(localized: "SNR = signal strength − noise. It reflects real-world experience better than signal alone: a strong signal with high noise still won't be fast. Only available for the connected network."), levels: [
                    .level("≥ 40 dB", String(localized: "Excellent: highest modulation rates"), .green),
                    .level("25 ~ 40 dB", String(localized: "Good"), .green),
                    .level("15 ~ 25 dB", String(localized: "Fair: noticeably slower"), .yellow),
                    .level("10 ~ 15 dB", String(localized: "Poor: unstable"), .orange),
                    .level("< 10 dB", String(localized: "Very poor: barely connects"), .red),
                ])
            case .last5Min:
                return InfoTip(text: String(localized: "Min / average / max signal sampled over the last 5 minutes of this session. A spread over 10 dB means the signal is unstable (people moving, obstructions, AP power changes, …)."))
            case .firstSeen:
                return InfoTip(text: String(localized: "When this BSSID was first seen in this session."))
            case .coChannel:
                return InfoTip(text: String(localized: "Other APs on the same primary channel. Co-channel APs take turns using the air (CSMA/CA); if they can hear each other they queue, so the more there are, the less airtime each gets."), levels: [
                    .level("0 ~ 2", String(localized: "Idle"), .green),
                    .level("3 ~ 5", String(localized: "Somewhat crowded"), .yellow),
                    .level("> 5", String(localized: "Crowded; consider changing channel"), .red),
                ])
            case .overlapping:
                return InfoTip(text: String(localized: "APs whose occupied frequencies overlap (including co-channel). Partial overlap is worse than sharing a channel: the APs can't coordinate and just see each other as noise."))
            case .stations:
                return InfoTip(text: String(localized: "The number of associated clients the AP reports in its BSS Load element. Many home routers don't broadcast it."), levels: [
                    .level("< 20", String(localized: "Light"), .green),
                    .level("20 ~ 50", String(localized: "Busy"), .yellow),
                    .level("> 50", String(localized: "Very full (common on enterprise APs)"), .red),
                ])
            case .utilization:
                return InfoTip(text: String(localized: "The share of time the AP reports the channel as busy, including other networks and interference. It is the most direct measure of congestion."), levels: [
                    .level("< 30%", String(localized: "Idle"), .green),
                    .level("30% ~ 50%", String(localized: "Moderate"), .yellow),
                    .level("50% ~ 70%", String(localized: "Busy; latency rises"), .orange),
                    .level("> 70%", String(localized: "Congested; consider changing channel"), .red),
                ])
            }
        }
    }
}

/// Question-mark icon that shows the tip on hover
struct InfoTipButton: View {
    let title: String
    let tip: InfoTip

    @State private var shown = false

    var body: some View {
        Image(systemName: "questionmark.circle")
            .font(.caption)
            .foregroundStyle(shown ? Color.accentColor : Color.secondary.opacity(0.7))
            .contentShape(Rectangle())
            .onHover { shown = $0 }
            .popover(isPresented: $shown, arrowEdge: .leading) {
                content.padding(12).frame(width: 300)
            }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(tip.text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if !tip.levels.isEmpty {
                Divider()
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 5) {
                    ForEach(tip.levels.indices, id: \.self) { i in
                        let l = tip.levels[i]
                        GridRow {
                            Circle().fill(l.color).frame(width: 8, height: 8)
                            Text(l.range).font(.callout.monospacedDigit()).fontWeight(.medium)
                            Text(l.label)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}
