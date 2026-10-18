// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FundamentCalc",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "FundamentCalc", path: "Sources/FundamentCalc")
    ]
)
