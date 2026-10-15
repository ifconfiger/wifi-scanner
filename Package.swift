// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WiFi-Viewer",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "WiFiViewer",
            path: "Sources/WiFiViewer",
            linkerSettings: [
                .linkedFramework("CoreWLAN"),
                .linkedFramework("CoreLocation"),
            ]
        )
    ]
)
