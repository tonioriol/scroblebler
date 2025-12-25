// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Audioscrobbler",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Audioscrobbler", targets: ["Audioscrobbler"])
    ],
    targets: [
        .executableTarget(
            name: "Audioscrobbler",
            path: "Audioscrobbler",
            exclude: [
                "Info.plist",
                "Audioscrobbler.entitlements",
                "Assets.xcassets",
                "Preview Content"
            ]
        )
    ]
)
