import SwiftUI

extension Band {
    /// 与图标配色一致：2.4G 橙、5G 蓝、6G 紫
    var color: Color {
        switch self {
        case .ghz24: return .orange
        case .ghz5: return .blue
        case .ghz6: return .purple
        case .unknown: return .gray
        }
    }
}

struct BandBadge: View {
    let band: Band

    var body: some View {
        Text(band.rawValue)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(band.color.opacity(0.18), in: Capsule())
            .foregroundStyle(band.color)
    }
}

func signalColor(_ rssi: Int) -> Color {
    switch rssi {
    case (-60)...: return .green
    case (-70)...: return .yellow
    case (-80)...: return .orange
    default: return .red
    }
}

func signalFraction(_ rssi: Int) -> Double {
    min(max(Double(rssi + 100) / 70, 0), 1)
}

struct SignalCell: View {
    let rssi: Int

    var body: some View {
        HStack(spacing: 6) {
            Gauge(value: signalFraction(rssi)) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(signalColor(rssi))
                .frame(width: 40)
            Text("\(rssi) dBm").monospacedDigit()
        }
    }
}
