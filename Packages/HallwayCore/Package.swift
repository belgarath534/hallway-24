// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HallwayCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "HallwayCore", targets: ["HallwayCore"])],
    targets: [
        .target(name: "HallwayCore"),
        .testTarget(name: "HallwayCoreTests", dependencies: ["HallwayCore"]),
    ]
)
