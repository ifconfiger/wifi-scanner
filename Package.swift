// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WiFiScope",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "WiFiScope",
            path: "Sources/WiFiScope",
            linkerSettings: [
                .linkedFramework("CoreWLAN"),
                .linkedFramework("CoreLocation"),
            ]
        )
    ]
)
