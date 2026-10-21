// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Audifern",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Audifern", targets: ["Audifern"])],
    targets: [
        .target(name: "CompanionCore"),
        .target(name: "QuickAccessKit"),
        .target(name: "QuickAccessUI", dependencies: ["QuickAccessKit"]),
        .executableTarget(name: "Audifern", dependencies: ["CompanionCore", "QuickAccessKit", "QuickAccessUI"], resources: [.process("Resources")]),
        .testTarget(name: "CompanionCoreTests", dependencies: ["CompanionCore"]),
        .testTarget(name: "AudifernTests", dependencies: ["Audifern", "QuickAccessKit", "QuickAccessUI"])
    ]
)
