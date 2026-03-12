// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchSoGood",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "NotchSoGood",
            path: "NotchSoGood",
            exclude: ["Info.plist"],
            resources: [
                .copy("Assets.xcassets"),
            ]
        )
    ]
)
