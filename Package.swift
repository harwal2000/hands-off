// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HandsOff",
    platforms: [.macOS(.v14)],
    targets: [
        // Private CoreGraphics API (CGVirtualDisplay), wrapped so Swift only sees a small class.
        .target(name: "CVirtualDisplay", linkerSettings: [.linkedFramework("CoreGraphics")]),
        .target(name: "HandsOffCore"),
        .executableTarget(name: "HandsOff", dependencies: ["CVirtualDisplay", "HandsOffCore"]),
        .testTarget(name: "HandsOffCoreTests", dependencies: ["HandsOffCore"]),
    ]
)
