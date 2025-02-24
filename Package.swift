// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "Uno",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "Uno",
            targets: ["Uno"]),
    ],
    dependencies: [
        .package(url: "https://github.com/raspu/Highlightr.git", from: "2.1.2"),
    ],
    targets: [
        .target(
            name: "Uno",
            dependencies: ["Highlightr"]),
    ]
) 