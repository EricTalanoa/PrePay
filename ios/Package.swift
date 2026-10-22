// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Prepay",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        // An xtool project contains exactly one library product: the app.
        .library(name: "Prepay", targets: ["Prepay"]),
    ],
    dependencies: [
        .package(path: "PrepayCore"),
        .package(url: "https://github.com/supabase/supabase-swift", from: "2.55.0"),
    ],
    targets: [
        .target(
            name: "Prepay",
            dependencies: [
                .product(name: "PrepayCore", package: "PrepayCore"),
                .product(name: "Supabase", package: "supabase-swift"),
            ],
            resources: [.process("Resources")]
        ),
        // Renders the README screenshots; see .github/workflows/screenshots.yml.
        .testTarget(
            name: "PrepayScreenshots",
            dependencies: [
                "Prepay",
                .product(name: "PrepayCore", package: "PrepayCore"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
