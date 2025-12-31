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
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "6.2.3"),
    ],
    targets: [
        .target(
            name: "SwiftUIHTML", dependencies: []),
        .testTarget(
            name: "SwiftUIHTMLTests",
            dependencies: [
                "SwiftUIHTML",
                .product(name: "Testing", package: "swift-testing"),
            ]),
    ]
)
