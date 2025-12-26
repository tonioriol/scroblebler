// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Scroblebler",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Scroblebler", targets: ["Scroblebler"])
    ],
    targets: [
        .executableTarget(
            name: "Scroblebler",
            path: "Scroblebler",
            exclude: [
                "Info.plist",
                "Scroblebler.entitlements",
                "Assets.xcassets",
                "Preview Content"
            ]
        )
    ]
)
