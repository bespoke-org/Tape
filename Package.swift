// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DayTape",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "DayTape", targets: ["Line"])],
    targets: [
        .target(name: "LineCore"),
        .executableTarget(name: "Line", dependencies: ["LineCore"]),
        .testTarget(name: "LineCoreTests", dependencies: ["LineCore"])
    ]
)
