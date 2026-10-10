import SwiftUI

/// 详情面板字段说明：一段解释 + 可选的好坏分级
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
    /// 按详情面板的行标题取说明
    static let all: [String: InfoTip] = [
        // 基本信息
        "SSID": InfoTip(text: "网络名称。隐藏网络不广播名称；没有定位权限时 macOS 也不给读取，都会显示为“隐藏/无权限”。"),
        "BSSID": InfoTip(text: "AP 某个射频的 MAC 地址，一个 SSID 可以对应多个 BSSID（多台 AP、或同一台 AP 的 2.4/5/6 GHz 各一个）。macOS 要求定位权限才能读取。"),
        "厂商": InfoTip(text: "由 BSSID 前 3 字节（OUI）查 IEEE 注册表得到。标“推测”的是虚拟 BSSID（本地管理地址），厂商由还原后的 OUI 推断，可能不准；手机热点通常用随机地址，查不到。"),
        "安全": InfoTip(text: "认证/加密方式。", levels: [
            .level("WPA3", "推荐", .green),
            .level("WPA2/WPA3", "良好（兼容旧设备）", .green),
            .level("WPA2", "可用", .yellow),
            .level("WPA / WEP", "已不安全", .red),
            .level("开放", "无加密，流量可被旁听", .red),
        ]),
        "协议": InfoTip(text: "AP 支持的最高 Wi-Fi 代际（由广播的信息元素推断）。代际越新，速率和多设备效率越高；实际速率还取决于终端是否支持。", levels: [
            .level("be (Wi-Fi 7)", "最新", .green),
            .level("ax (Wi-Fi 6/6E)", "主流", .green),
            .level("ac (Wi-Fi 5)", "够用", .yellow),
            .level("n (Wi-Fi 4) 及更早", "老旧，会拖慢同信道", .orange),
        ]),
        "国家/地区": InfoTip(text: "AP 广播的国家码，决定可用信道和最大发射功率。"),
        "网络类型": InfoTip(text: "基础设施 = 普通路由器/AP；点对点 (IBSS) = 设备之间直连的 ad-hoc 网络，少见。"),

        // 射频
        "频段": InfoTip(text: "2.4 GHz 穿墙好、覆盖远，但只有 3 个不重叠信道（1/6/11），干扰多；5 GHz 信道多、速度快，穿墙较弱；6 GHz 最干净、最快，覆盖最短，需要 Wi-Fi 6E 以上设备。"),
        "主信道": InfoTip(text: "AP 发信标所在的 20 MHz 信道。2.4 GHz 应只用 1 / 6 / 11，其他信道会同时干扰两边。"),
        "中心信道": InfoTip(text: "多个 20 MHz 信道绑定成 40/80/160 MHz 后的中心位置，频谱图按它来画。2.4 GHz 的 40 MHz 拿不到扩展方向，是估算值。"),
        "主信道频率": InfoTip(text: "主信道的中心频率。"),
        "占用频率": InfoTip(text: "按带宽算出的实际占用频率范围，和别的 AP 有交叠就会互相干扰。"),
        "信道带宽": InfoTip(text: "带宽越宽理论速率越高，但更容易和邻居重叠、抗干扰更差。", levels: [
            .level("2.4 GHz", "建议 20 MHz", .yellow),
            .level("5 GHz", "80 MHz 常用；拥挤时 40 MHz", .green),
            .level("6 GHz", "160 MHz 也很常见", .green),
        ]),
        "信标间隔": InfoTip(text: "AP 广播信标的周期，1 TU = 1.024 ms。默认 100 TU，几乎所有设备都不需要改；过小浪费空口，过大影响终端发现和省电唤醒。"),

        // 信号
        "信号强度": InfoTip(text: "RSSI，接收到的 AP 信号功率，单位 dBm，越接近 0 越强。每差 3 dB 功率差一倍。", levels: [
            .level("≥ -50 dBm", "优秀：满速", .green),
            .level("-60 ~ -50", "良好：视频会议、4K 都没问题", .green),
            .level("-70 ~ -60", "一般：日常上网可以，速率下降", .yellow),
            .level("-80 ~ -70", "较弱：容易卡顿、掉速", .orange),
            .level("< -80 dBm", "很差：经常断连", .red),
        ]),
        "噪声": InfoTip(text: "该信道上的背景噪声，越低（越负）越好。CoreWLAN 只测当前连接的网络，其他网络显示“—”。", levels: [
            .level("≤ -90 dBm", "安静", .green),
            .level("-90 ~ -80", "有一定干扰", .yellow),
            .level("> -80 dBm", "噪声大（微波炉、蓝牙、无线摄像头等）", .red),
        ]),
        "信噪比": InfoTip(text: "SNR = 信号强度 − 噪声，比单看信号更能反映实际体验：信号再强、噪声也高，速率照样上不去。只有当前连接的网络能算。", levels: [
            .level("≥ 40 dB", "优秀：可跑最高调制速率", .green),
            .level("25 ~ 40 dB", "良好", .green),
            .level("15 ~ 25 dB", "一般：速率明显下降", .yellow),
            .level("10 ~ 15 dB", "较差：不稳定", .orange),
            .level("< 10 dB", "很差：基本连不上", .red),
        ]),
        "最近 5 分钟": InfoTip(text: "本次运行期间最近 5 分钟采到的信号最低/平均/最高值。最高和最低相差超过 10 dB 说明信号不稳定（人员走动、遮挡、AP 调功率等）。"),
        "首次发现": InfoTip(text: "本次运行中第一次扫描到这个 BSSID 的时间。"),

        // 信道环境
        "同信道 AP": InfoTip(text: "主信道相同的其他 AP。同信道的 AP 会轮流占用空口（CSMA/CA），能互相听到就要排队，数量越多每个人分到的时间越少。", levels: [
            .level("0 ~ 2 个", "空闲", .green),
            .level("3 ~ 5 个", "有些拥挤", .yellow),
            .level("> 5 个", "拥挤，考虑换信道", .red),
        ]),
        "频谱重叠 AP": InfoTip(text: "占用频率有交叠的 AP（含同信道）。部分重叠比同信道更糟：彼此无法正常协调，只能当噪声硬扛。"),
        "已连接设备": InfoTip(text: "AP 在 BSS Load 信息里自报的已关联终端数。很多家用路由器不广播。", levels: [
            .level("< 20 台", "轻松", .green),
            .level("20 ~ 50 台", "繁忙", .yellow),
            .level("> 50 台", "很满（企业 AP 常见）", .red),
        ]),
        "信道利用率": InfoTip(text: "AP 自报的信道忙碌时间比例，包括别的网络和干扰占用的时间，是判断信道是否拥挤最直接的指标。", levels: [
            .level("< 30%", "空闲", .green),
            .level("30% ~ 50%", "中等", .yellow),
            .level("50% ~ 70%", "繁忙，延迟上升", .orange),
            .level("> 70%", "拥塞，考虑换信道", .red),
        ]),
    ]
}

/// 问号图标，鼠标悬浮弹出说明
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
