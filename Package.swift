// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Audifern",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Audifern", targets: ["Audifern"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(name: "CompanionCore"),
        .target(name: "QuickAccessKit"),
        .target(name: "QuickAccessUI", dependencies: ["QuickAccessKit"]),
        .executableTarget(name: "Audifern", dependencies: ["CompanionCore", "QuickAccessKit", "QuickAccessUI", .product(name: "Sparkle", package: "Sparkle")], resources: [.process("Resources")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "CompanionCoreTests", dependencies: ["CompanionCore"]),
        .testTarget(name: "AudifernTests", dependencies: ["Audifern", "QuickAccessKit", "QuickAccessUI"])
    ]
)
