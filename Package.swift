// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftUIHTML",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(
            name: "SwiftUIHTML",
            targets: ["SwiftUIHTML"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SwiftUIHTML", dependencies: []),
    ]
)
