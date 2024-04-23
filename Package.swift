// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AvoInspector",
    platforms: [
        .iOS(.v12)
    ],
    products: [
        .library(
            name: "AvoInspector",
            targets: ["AvoInspector"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "AvoInspector",
            resources: [.copy("PrivacyInfo.xcprivacy")]
        )
    ]
)
