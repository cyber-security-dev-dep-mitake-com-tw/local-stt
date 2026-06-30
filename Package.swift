// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalSTT",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LocalSTT", targets: ["LocalSTTApp"]),
        .library(name: "LocalSTTCore", targets: ["LocalSTTCore"])
    ],
    targets: [
        .target(name: "LocalSTTCore"),
        .executableTarget(name: "LocalSTTApp", dependencies: ["LocalSTTCore"]),
        .testTarget(name: "LocalSTTCoreTests", dependencies: ["LocalSTTCore"])
    ]
)

