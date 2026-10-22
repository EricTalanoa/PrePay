// swift-tools-version: 6.0

import PackageDescription

// Pay math with no UI or network. Its own package so `swift test` runs it on
// any machine with Swift, Linux included, without the iOS SDK.
let package = Package(
    name: "PrepayCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PrepayCore", targets: ["PrepayCore"])],
    targets: [
        .target(name: "PrepayCore"),
        .testTarget(name: "PrepayCoreTests", dependencies: ["PrepayCore"]),
    ]
)
