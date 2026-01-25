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
        .package(url: "https://github.com/scinfu/SwiftSoup.git", branch: "master"),
        .package(url: "https://github.com/kean/Nuke.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "SwiftUIHTML",
            dependencies: [
                .product(name: "NukeUI", package: "Nuke"),
            ]
        ),
        .testTarget(
            name: "SwiftUIHTMLTests",
            dependencies: [
                "SwiftUIHTML",
                .product(name: "Testing", package: "swift-testing"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ]),
    ]
)
