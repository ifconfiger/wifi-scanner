import SwiftUI

extension Band {
    /// Matches the app icon: 2.4 GHz orange, 5 GHz blue, 6 GHz purple
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
        Text(band.label)
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
            // Drawn by hand: Gauge's tint turns gray in inactive windows and accent-blue in dark mode
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25))
                Capsule().fill(signalColor(rssi)).frame(width: 40 * signalFraction(rssi))
            }
            .frame(width: 40, height: 5)
            Text("\(rssi) dBm").monospacedDigit()
        }
    }
}

/// High-saturation palette shared by spectrum curves and vendor monograms; colors are picked stably by name (same across launches)
enum Palette {
    // Hues spread apart with strong contrast between neighbors; only 3 warm colors so they don't blur with the 2.4 GHz orange
    private static let vividHex: [UInt32] = [
        0x2F7BFF,  // blue
        0xFF2D78,  // rose
        0x1DBF5E,  // green
        0x9B4DFF,  // purple
        0xFF8A00,  // orange
        0x00B8D9,  // cyan
        0xE5262B,  // red
        0x8BC400,  // yellow-green
        0x5B5BF0,  // indigo
        0xF2B600,  // gold
        0x00A39A,  // teal
        0xD63AF9,  // magenta
    ]

    static let vivid: [Color] = vividHex.map { hex in
        Color(.sRGB,
              red: Double(hex >> 16 & 0xFF) / 255,
              green: Double(hex >> 8 & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }

    static func color(for key: String) -> Color {
        vivid[Int(stableHash(key) % UInt64(vivid.count))]
    }

    /// Assign colors to a set of names: use the hashed slot first, probing to the next free one if taken,
    /// so different names in one chart rarely collide and most colors stay put as networks come and go
    static func assign(_ keys: [String]) -> [String: Color] {
        var used = Set<Int>()
        var result: [String: Color] = [:]
        for key in Set(keys).sorted() {
            var i = Int(stableHash(key) % UInt64(vivid.count))
            if used.count < vivid.count {
                while used.contains(i) { i = (i + 1) % vivid.count }
            }
            used.insert(i)
            result[key] = vivid[i]
        }
        return result
    }

    /// FNV-1a; String.hashValue is randomized per launch and can't be used for colors
    static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01B3
        }
        return h
    }
}
