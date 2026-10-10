# WiFiScope

English | [简体中文](README.zh-CN.md)

A native macOS Wi-Fi scanner in the spirit of WiFi Explorer. It lists nearby 2.4 / 5 / 6 GHz networks without dropping your current connection, and charts channels, signal strength and network names.

## Install
Download the latest `WiFiScope-x.y.z-macos-arm64.dmg` from [Releases](https://github.com/ifconfiger/wifi-scanner/releases), open it and drag WiFiScope onto Applications. The app and the disk image are signed with a Developer ID and notarized by Apple. A `.zip` of the app is attached as well. Apple Silicon only, macOS 13+.

On first launch macOS asks for **location permission**. Allow it, otherwise SSIDs and BSSIDs stay hidden.

## Interface
```
┌ Toolbar: [All|2.4|5|6 GHz]       Auto Refresh  Interval  Scan(⌘R)  Details(⌘I) ┐
├──────────── Network list (sortable / searchable) ────────────┬─ Detail panel ─┤
│ SSID  BSSID  Signal  Noise  SNR  Band  Channel  Width  Sec PHY │ Name/band/ring │
├──────────── Charts ──────────────────────────────────────────┤ Basics         │
│ [Channels|Signal Ranking|Congestion|Signal History]            │ Radio          │
│  "All" shows one block per band (2.4 / 5 / 6 GHz)              │ Signal         │
│                                                                │ Channel env.   │
│                                                                │ Overlaps/history│
└─ Status bar: current link · networks per band · last update ──┴────────────────┘
```

### Charts
| Chart | What it shows |
|---|---|
| Channels | One rounded trapezoid per AP: x = channel (width = channel width), y = signal in dBm, SSID on top. The same SSID shares a color, and colors are kept distinct within a chart. Click a curve to select it |
| Signal Ranking | Horizontal bars sorted by signal, colored by band (2.4 orange / 5 blue / 6 purple). Click a bar to select it |
| Congestion | AP count on each primary channel, stacked strong / medium / weak — handy for picking a free channel |
| Signal History | RSSI over the last 5 minutes (selected networks, or the 5 strongest when nothing is selected) |

### Detail panel (one network selected)
- **Basics**: SSID, BSSID (copyable), vendor, security, PHY (n/ac/ax/be), country/region, network type
- **Radio**: band, primary channel, center channel, frequency, occupied range, channel width, beacon interval
- **Signal**: RSSI with a quality rating, noise, SNR, 5-minute min/avg/max, first seen
- **Channel environment**: co-channel APs, overlapping APs, connected clients and channel utilization (when the AP broadcasts BSS Load), list of overlapping networks
- A small signal history chart
- Every field has a question-mark icon; hover it for an explanation and good/bad thresholds (signal strength, SNR, noise, channel utilization, …)

### Vendor identification
- The small icon before each SSID is the AP vendor's logo. Hover it for the brand, IEEE organization name and OUI. The search box also matches vendors.
- The vendor comes from the first 3 bytes of the BSSID (OUI), looked up offline in `Resources/oui.tsv` (the IEEE MA-L registry). Refresh it with `uv run tools/update_oui.py`.
- Virtual BSSIDs (locally administered addresses, e.g. Xiaomi `5a:…`, Ubiquiti `66:…`) are looked up again with the low bits of the first byte cleared. Their icon is translucent and the tooltip says "guessed". Phone hotspots use random addresses and usually show `?`.
- Logos are favicons fetched by brand domain (DuckDuckGo → Google → the site's `/favicon.ico`) and cached in `~/Library/Caches/WiFiScope/logos/`. Only the brand domain is sent, never a BSSID. Without an image a colored monogram is shown.

### Language
The UI is available in English (default) and Simplified Chinese. Switch it from **WiFiScope → Language** (English / 简体中文 / Follow System); the app offers to restart to apply it.

### Updates
WiFiScope checks GitHub Releases at launch (at most once a day) and offers a newer version. **Download** saves the DMG to `~/Downloads` and opens it in Finder; quit WiFiScope, drag the new copy onto Applications and choose Replace. Use **WiFiScope → Check for Updates…** to check manually, or turn off **Automatically Check for Updates** in the same menu.

## Building (macOS 13+, Xcode)
```bash
./build.sh
open build/WiFiScope.app
```
`build.sh` builds a release binary, packages it as `build/WiFiScope.app` and signs it ad-hoc. If the active developer directory is the Command Line Tools it switches to `/Applications/Xcode.app`, because the SwiftUI macros in the macOS 26+ SDK ship only with Xcode.

For development you can `open Package.swift` in Xcode, but location permission, the icon and translations only work when running the `.app` produced by `build.sh`.

### Localization
UI strings use English source text as keys (`Text("Scan")`, `String(localized: "…")`). Translations live in `Resources/zh-Hans.lproj/Localizable.strings`; `Resources/en.lproj` holds English plurals and the `InfoPlist.strings` for the location prompt. After changing UI text, run:
```bash
uv run tools/check_l10n.py
```
It compiles with `-emit-localized-strings` and lists any key missing a Chinese translation.

### Icon
`Resources/AppIcon.icns` is generated by `tools/make_icon.py` (three spectrum curves = 2.4/5/6 GHz, in the app's colors). Regenerate it after changing the design:
```bash
uv run tools/make_icon.py
```

To package a disk image locally after `./build.sh`:
```bash
tools/make_dmg.sh            # → build/WiFiScope.dmg
```

### Releasing
Push a tag of the form `main-vX.Y.Z`. `.github/workflows/release.yml` builds an arm64 app with that version, signs it with Developer ID, notarizes and staples it, packs it into a DMG (`tools/make_dmg.sh`), signs, notarizes and staples the DMG (`tools/notarize.sh`), and publishes a GitHub Release with the DMG, a zip of the app and `SHA256SUMS.txt`. The update checker looks for the `.dmg` asset, so keep that naming. Without the `APPLE_SIGN_*` / `APPLE_NOTARY_*` secrets (e.g. in a fork) it falls back to ad-hoc signing.

## How it works
- Scanning uses CoreWLAN's `CWInterface.scanForNetworks(withSSID:includeHidden:)`. It blocks for about 3–5 seconds and returns everything at once; there is no public per-network callback. So the app first shows the system scan cache, `cachedScanResults()`, which is nearly instant. While a scan runs it polls that cache and inserts new networks early, then reconciles with the full result.
- The system driver does off-channel scans **while staying associated**, so your Wi-Fi isn't dropped. Latency can jitter for those few seconds, so don't set the interval too short.
- Monitor mode is not used, since it would take the adapter off the current network.
- The PHY generation, client count and channel utilization come from parsing the 802.11 information elements (IEs) the AP broadcasts.

## Known limitations
- **Location permission**: since macOS 14, reading SSIDs/BSSIDs requires location authorization. If you deny it, only signal and channel are visible. macOS may ask again after a rebuild re-signs the app.
- **2.4 GHz 40 MHz**: CoreWLAN doesn't report the secondary channel's direction, so the center is estimated (marked "estimated" in the details).
- **320 MHz (Wi-Fi 7)**: CoreWLAN's channel-width enum tops out at 160 MHz.
- **Noise / SNR**: CoreWLAN only measures noise for the connected network; others show "—".
- **Duplicate BSSIDs**: CoreWLAN sometimes returns the same BSS several times (usually a router's hidden SSID); these are merged into one row by BSSID.
- **Connected clients / channel utilization**: only available when the AP broadcasts BSS Load, which many home routers don't.
- **Scan rate**: macOS throttles frequent scans, and scanning too fast can fail.
- Local `build.sh` builds are ad-hoc signed. GitHub Releases are signed with a Developer ID and notarized by CI (see `.github/workflows/release.yml`).
