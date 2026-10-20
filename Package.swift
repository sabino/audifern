// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Audifern",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Audifern", targets: ["Audifern"])],
    targets: [
        .target(name: "CompanionCore"),
        .executableTarget(name: "Audifern", dependencies: ["CompanionCore"], resources: [.process("Resources")]),
        .testTarget(name: "CompanionCoreTests", dependencies: ["CompanionCore"]),
        .testTarget(name: "AudifernTests", dependencies: ["Audifern"])
    ]
)
