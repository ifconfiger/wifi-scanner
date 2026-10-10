# WiFiScope

[English](README.md) | 简体中文

类 WiFi Explorer 的 macOS 原生 Wi-Fi 扫描器：不断开当前连接，列出 2.4 / 5 / 6 GHz 周边网络，用图表展示信道、信号强度和网络名称。

## 安装
从 [Releases](https://github.com/ifconfiger/wifi-scanner/releases) 下载最新的 `WiFiScope-x.y.z-macos-arm64.zip`，解压后把 `WiFiScope.app` 拖进「应用程序」。发布版已用 Developer ID 签名并通过 Apple 公证。仅支持 Apple Silicon，macOS 13+。

首次启动会弹出**定位权限**请求，必须允许，否则看不到 SSID/BSSID。

## 界面
```
┌ 工具栏：[全部|2.4|5|6 GHz]            自动刷新 间隔 扫描(⌘R) 详情(⌘I) ┐
├──────────────── 网络列表（可排序/搜索） ────────────────┬── 详情面板 ──┤
│ SSID  BSSID  信号  噪声  SNR  频段  信道  带宽  安全  协议 │ 名称/频段/信号环 │
├──────────── 图表区 ────────────────────────────────────┤ 基本信息      │
│ [信道分布|信号排行|信道拥挤度|信号历史]                  │ 射频          │
│  选“全部”时按 2.4 / 5 / 6 GHz 分块展示                   │ 信号          │
│                                                        │ 信道环境      │
│                                                        │ 重叠网络/历史  │
└─ 状态栏：当前连接 · 各频段数量 · 更新时间 ──────────────┴──────────────┘
```

### 图表
| 图表 | 内容 |
|---|---|
| 信道分布 | 每个 AP 画一条圆角梯形：横轴信道（宽度=带宽）、纵轴信号 dBm，顶部标 SSID。同一 SSID 同色，同一张图里尽量不撞色。点曲线即选中 |
| 信号排行 | 横向条形图，按信号强弱排序，颜色区分频段（2.4 橙 / 5 蓝 / 6 紫）。点条形即选中 |
| 信道拥挤度 | 每个主信道上有几个 AP，按强/中/弱堆叠，用于挑空闲信道 |
| 信号历史 | 最近 5 分钟 RSSI 曲线（选中的网络，未选时取最强 5 个） |

### 详情面板（选中一个网络时）
- **基本信息**：SSID、BSSID（可复制）、厂商、安全类型、协议（n/ac/ax/be）、国家/地区、网络类型
- **射频**：频段、主信道、中心信道、频率、占用频率范围、带宽、信标间隔
- **信号**：RSSI 与质量评级、噪声、SNR、5 分钟内最低/平均/最高、首次发现时间
- **信道环境**：同信道 AP 数、频谱重叠 AP 数、已连接设备数和信道利用率（需 AP 广播 BSS Load），重叠网络列表
- 信号历史小图
- 每个字段名后有问号图标，鼠标悬浮弹出说明和好/差分级（信号强度、信噪比、噪声、信道利用率等）

### 厂商识别
- 列表 SSID 前的小图标是 AP 厂商 logo，悬浮显示品牌名、IEEE 注册名和 OUI；搜索框也能按厂商（含中文品牌名）搜。
- 厂商由 BSSID 前 3 字节（OUI）查 `Resources/oui.tsv`（IEEE MA-L 注册表，离线）。更新：`uv run tools/update_oui.py`。
- 虚拟 BSSID（本地管理地址，如小米 `5a:…`、Ubiquiti `66:…`）会清掉首字节低位再查，图标半透明、提示里标“推测”。手机热点的随机地址通常查不到，显示 `?`。
- logo 按品牌域名抓 favicon（DuckDuckGo → Google → 官网 `/favicon.ico`），缓存在 `~/Library/Caches/WiFiScope/logos/`；只发送品牌域名，不上传 BSSID。拿不到图时显示彩色首字母。

### 语言
界面支持英文（默认）和简体中文。在菜单 **WiFiScope → Language / 语言** 中切换（English / 简体中文 / 跟随系统），切换后按提示重启生效。

### 检查更新
启动时自动检查 GitHub Releases（每天最多一次），有新版本时弹窗提供下载。也可以通过 **WiFiScope → 检查更新…** 手动检查，或在同一菜单关闭「自动检查更新」。

## 构建（需要 macOS 13+ 和 Xcode）
```bash
./build.sh
open build/WiFiScope.app
```
`build.sh` 编译 release 版本、打包成 `build/WiFiScope.app` 并做 ad-hoc 签名。若当前开发者目录是 Command Line Tools，会自动改用 `/Applications/Xcode.app`（macOS 26+ SDK 的 SwiftUI 宏插件只随 Xcode 提供）。

开发调试可以 `open Package.swift` 用 Xcode 打开；但定位授权、图标和翻译只有用 build.sh 打出的 .app 运行才生效。

### 本地化
界面文字以英文原文作为 key（`Text("Scan")`、`String(localized: "…")`），中文翻译在 `Resources/zh-Hans.lproj/Localizable.strings`；`Resources/en.lproj` 存放英文复数规则和定位弹窗用的 `InfoPlist.strings`。修改界面文字后运行：
```bash
uv run tools/check_l10n.py
```
它会带 `-emit-localized-strings` 编译一遍，列出缺少中文翻译的 key。

### 图标
`Resources/AppIcon.icns` 由 `tools/make_icon.py` 生成（三条频谱曲线 = 2.4/5/6 GHz，配色与 App 内一致）。改设计后重新生成：
```bash
uv run tools/make_icon.py
```

### 发版
推送形如 `main-vX.Y.Z` 的 tag，`.github/workflows/release.yml` 会以该版本号构建 arm64 应用，用 Developer ID 签名、公证并钉入票据，然后发布带 zip 和 SHA-256 的 GitHub Release。缺少 `APPLE_SIGN_*` / `APPLE_NOTARY_*` secrets 时（如 fork 仓库）退回 ad-hoc 签名。

## 原理
- 扫描用 `CoreWLAN` 的 `CWInterface.scanForNetworks(withSSID:includeHidden:)`，这是阻塞调用（约 3~5 秒），一次性返回全部结果，没有逐个回调的公开 API。所以启动时先显示系统扫描缓存 `cachedScanResults()`（几乎瞬间），扫描期间轮询缓存把新出现的网络先插进列表，扫完再用完整结果校正。
- 系统驱动在**保持关联**的状态下做离信道扫描，不断开当前 Wi-Fi。扫描那几秒内延迟可能有抖动，所以别把间隔调得太短。
- 没用监听模式（monitor mode）——那个会让网卡离开当前网络。
- 协议代际、连接设备数、信道利用率通过解析 AP 广播的 802.11 信息元素（IE）得到。

## 已知限制
- **定位权限**：macOS 14 起读取 SSID/BSSID 必须有定位授权；拒绝后只能看到信号和信道。重新编译签名后系统可能再次询问。
- **2.4 GHz 40 MHz**：CoreWLAN 不提供扩展信道方向，中心位置为估算（详情里会标“估算”）。
- **320 MHz（Wi-Fi 7）**：CoreWLAN 带宽枚举最高 160 MHz。
- **噪声 / SNR**：CoreWLAN 只测当前连接网络的噪声，其他网络显示“—”。
- **重复 BSSID**：CoreWLAN 偶尔把同一 BSS（多为路由器的隐藏 SSID）返回多次，已按 BSSID 合并成一行。
- **连接设备数 / 信道利用率**：只有 AP 开启 BSS Load 广播时才有，很多家用路由器不广播。
- **扫描频率**：系统对频繁扫描会限流，太快可能报错。
- 本地 build.sh 只做 ad-hoc 签名；GitHub Release 由 CI 用 Developer ID 签名并公证（见 `.github/workflows/release.yml`）。
