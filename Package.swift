// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Tape",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "Tape", targets: ["Line"])],
    targets: [
        .target(name: "LineCore"),
        .executableTarget(name: "Line", dependencies: ["LineCore"]),
        .testTarget(name: "LineCoreTests", dependencies: ["LineCore"])
    ]
)
