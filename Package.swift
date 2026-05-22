// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Scroblebler",
    platforms: [.macOS(.v11)],
    products: [
        .executable(name: "Scroblebler", targets: ["Scroblebler"])
    ],
    dependencies: [
        .package(url: "https://github.com/ejbills/mediaremote-adapter.git", revision: "78aae86c03adab11a7b352211cc82381737cf854"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "Scroblebler",
            dependencies: [
                .product(name: "MediaRemoteAdapter", package: "mediaremote-adapter"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Scroblebler",
            exclude: [
                "Info.plist",
                "Scroblebler.entitlements",
                "Assets.xcassets",
                "Preview Content"
            ]
        ),
        .testTarget(
            name: "ScrobbleblerTests",
            dependencies: ["Scroblebler"],
            path: "ScrobbleblerTests"
        )
    ]
)
