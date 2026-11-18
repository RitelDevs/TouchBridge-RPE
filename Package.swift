// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TouchBridgeStudio", platforms: [.macOS(.v14)],
    products: [.executable(name: "TouchBridgeStudio", targets: ["StudioApp"])],
    targets: [
        .target(name: "StudioCore"),
        .executableTarget(name: "StudioApp", dependencies: ["StudioCore"]),
        .testTarget(name: "StudioCoreTests", dependencies: ["StudioCore"]),
        .testTarget(name: "StudioAppTests", dependencies: ["StudioApp", "StudioCore"])
    ]
)
