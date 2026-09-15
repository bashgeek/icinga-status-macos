// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IcingaStatusCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "IcingaCore", targets: ["IcingaCore"])],
    targets: [
        .target(name: "IcingaCore"),
        .testTarget(name: "IcingaCoreTests", dependencies: ["IcingaCore"])
    ]
)
