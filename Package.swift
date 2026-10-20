// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenCompanion",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "OpenCompanion", targets: ["OpenCompanion"])],
    targets: [
        .target(name: "CompanionCore"),
        .executableTarget(name: "OpenCompanion", dependencies: ["CompanionCore"]),
        .testTarget(name: "CompanionCoreTests", dependencies: ["CompanionCore"]),
        .testTarget(name: "OpenCompanionTests", dependencies: ["OpenCompanion"])
    ]
)
