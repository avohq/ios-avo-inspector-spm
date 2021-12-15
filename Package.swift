// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AvoInspectorStatic",
    platforms: [
        .iOS(.v10)
    ],
    products: [
        .library(
            name: "AvoInspectorStatic",
            targets: ["AvoInspectorStatic"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "AvoInspectorStatic",
            dependencies: [],
            path: "Sources/AvoInspectorStatic"
        )
    ]
)
