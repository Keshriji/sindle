// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "Spindle",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "Spindle", path: "Sources")]
)
