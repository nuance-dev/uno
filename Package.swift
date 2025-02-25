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
        .executable(
            name: "UnoApp",
            targets: ["Uno"])
    ],
    dependencies: [
        // Removed highlightr dependency
    ],
    targets: [
        .target(
            name: "Uno",
            dependencies: [], // Removed highlightr dependency
            path: "Uno") // Added path to correct source directory
    ]
) 