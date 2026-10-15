import AppKit
import Combine
import CoreLocation

/// Since macOS 14, CoreWLAN returns nil for ssid/bssid without location authorization.
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
        // On macOS, when-in-use authorization also maps to authorizedAlways (.authorizedWhenInUse is unavailable in the macOS SDK)
        status == .authorizedAlways
    }

    var isDenied: Bool {
        status == .denied || status == .restricted
    }

    func request() {
        guard status == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
        // Some macOS versions only show the prompt once location is actually requested
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
