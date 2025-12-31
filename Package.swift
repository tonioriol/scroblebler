// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Scroblebler",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Scroblebler", targets: ["Scroblebler"])
    ],
    dependencies: [
        .package(url: "https://github.com/ejbills/mediaremote-adapter.git", branch: "master")
    ],
    targets: [
        .executableTarget(
            name: "Scroblebler",
            dependencies: [
                .product(name: "MediaRemoteAdapter", package: "mediaremote-adapter")
            ],
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
