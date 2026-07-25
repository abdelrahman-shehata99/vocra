// swift-tools-version: 5.9
//
// Swift Package Manager manifest for the optional native AEC module (spec §9, T18).
// The CocoaPods podspec alongside this file is still maintained — apps that have
// not migrated to SPM keep building through it unchanged.

import PackageDescription

let package = Package(
    name: "vocra_flutter",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        // The plugin name contains "_", so the library name uses "-".
        .library(name: "vocra-flutter", targets: ["vocra_flutter"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "vocra_flutter",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            path: "Sources/vocra_flutter"
        )
    ]
)
