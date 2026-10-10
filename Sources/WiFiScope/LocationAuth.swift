import AppKit
import Combine
import CoreLocation

/// macOS 14 起，没有定位授权时 CoreWLAN 的 ssid/bssid 一律返回 nil。
final class LocationAuth: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var status: CLAuthorizationStatus
    private let manager: CLLocationManager

    override init() {
        let m = CLLocationManager()
        manager = m
        status = m.authorizationStatus
        super.init()
        m.delegate = self
    }

    var isAuthorized: Bool {
        // macOS 上 whenInUse 授权也映射为 authorizedAlways（.authorizedWhenInUse 在 macOS SDK 中不可用）
        status == .authorizedAlways
    }

    var isDenied: Bool {
        status == .denied || status == .restricted
    }

    func request() {
        guard status == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
        // 部分 macOS 版本只有真正请求位置时才弹授权框
        manager.startUpdatingLocation()
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        if s != .notDetermined { manager.stopUpdatingLocation() }
        DispatchQueue.main.async { self.status = s }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
