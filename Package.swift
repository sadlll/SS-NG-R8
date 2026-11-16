// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ProxyDiagnostics",
    platforms: [.macOS(.v14)],
    products: [.library(name: "ProxyDiagnostics", targets: ["ProxyDiagnostics"])],
    targets: [
        .target(name: "ProxyDiagnostics", path: "Diagnostics",
                sources: ["ProxyProbe.swift", "OverlayConnection.swift", "ProxyTestResult.swift", "PingProbe.swift"]),
        .testTarget(name: "ProxyDiagnosticsTests", dependencies: ["ProxyDiagnostics"],
                    path: "Tests/ProxyDiagnosticsTests")
    ],
    swiftLanguageVersions: [.v5]
)
