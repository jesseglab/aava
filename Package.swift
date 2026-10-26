// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AavaCore",
    platforms: [.macOS(.v14), .iOS("18.0")],
    products: [.library(name: "AavaCore", targets: ["AavaCore"])],
    targets: [
        .target(name: "AavaCore", path: "Sources/AavaCore"),
        .testTarget(name: "AavaCoreTests", dependencies: ["AavaCore"], path: "Tests/AavaCoreTests")
    ]
)
