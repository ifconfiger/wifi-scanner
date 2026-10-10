// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WiFi-Scanner",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "WiFiScanner",
            path: "Sources/WiFiScanner",
            linkerSettings: [
                .linkedFramework("CoreWLAN"),
                .linkedFramework("CoreLocation"),
            ]
        )
    ]
)
