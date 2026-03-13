// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchSoGood",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "NotchSoGood",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "NotchSoGood",
            exclude: ["Info.plist"],
            resources: [
                .copy("Assets.xcassets"),
            ]
        )
    ]
)
