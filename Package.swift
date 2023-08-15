// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LPReducer",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "LPReducer",
            targets: ["LPReducer"]),
    ],
    targets: [
        .target(
            name: "LPReducer"),
        .testTarget(
            name: "LPReducerTests",
            dependencies: ["LPReducer"]),
    ]
)
