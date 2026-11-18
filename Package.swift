// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DellMonitorBar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "DellMonitorBar", targets: ["DellMonitorBar"])],
    targets: [
        .target(name: "DDCBridge", publicHeadersPath: "include", cSettings: [.unsafeFlags(["-fobjc-arc"])],
                linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreGraphics"), .linkedFramework("CoreDisplay")]),
        .target(name: "MonitorCore"),
        .executableTarget(name: "DellMonitorBar", dependencies: ["DDCBridge", "MonitorCore"]),
        .testTarget(name: "MonitorCoreTests", dependencies: ["MonitorCore"]),
        .testTarget(name: "AppTests", dependencies: ["DellMonitorBar", "MonitorCore"])
    ]
)
