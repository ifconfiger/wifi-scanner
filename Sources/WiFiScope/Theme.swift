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

/// 高饱和度调色板：信道分布曲线和厂商首字母图标共用，按名字稳定取色（每次启动颜色不变）
enum Palette {
    // 色相尽量拉开，相邻两个对比强；暖色只留 3 个，避免和 2.4 GHz 的橙色混成一片
    static let vivid: [Color] = [
        0x2F7BFF,  // 蓝
        0xFF2D78,  // 玫红
        0x1DBF5E,  // 绿
        0x9B4DFF,  // 紫
        0xFF8A00,  // 橙
        0x00B8D9,  // 青
        0xE5262B,  // 红
        0x8BC400,  // 黄绿
        0x5B5BF0,  // 靛
        0xF2B600,  // 金黄
        0x00A39A,  // 蓝绿
        0xD63AF9,  // 品红
    ].map { hex in
        Color(.sRGB,
              red: Double(hex >> 16 & 0xFF) / 255,
              green: Double(hex >> 8 & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }

    static func color(for key: String) -> Color {
        vivid[Int(stableHash(key) % UInt64(vivid.count))]
    }

    /// 给一组名字分配颜色：优先用 hash 对应的颜色，被占了就顺延到下一个空位，
    /// 同一张图里不同名字尽量不撞色，网络增减时大部分颜色保持不变
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

    /// FNV-1a；String.hashValue 每次启动随机，不能用来取色
    static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01B3
        }
        return h
    }
}
