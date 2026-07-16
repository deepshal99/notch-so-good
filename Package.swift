// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchSoGood",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.0.0"),
        .package(url: "https://github.com/aptabase/aptabase-swift", from: "0.3.5")
    ],
    targets: [
        .executableTarget(
            name: "NotchSoGood",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Aptabase", package: "aptabase-swift")
            ],
            path: "NotchSoGood",
            exclude: ["Info.plist"],
            resources: [
                .copy("Assets.xcassets"),
            ]
        )
    ]
)
