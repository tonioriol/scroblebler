// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Scroblebler",
    platforms: [.macOS(.v11)],
    products: [
        .executable(name: "Scroblebler", targets: ["Scroblebler"])
    ],
    dependencies: [
        .package(url: "https://github.com/ejbills/mediaremote-adapter.git", revision: "5b2c2ab"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.0.0"),
        // 2.9.6 is the last Sparkle that supports macOS 11; 2.10 needs macOS 12.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
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
                "Scroblebler.entitlements",
                "Assets.xcassets"
            ]
        ),
        .testTarget(
            name: "ScrobbleblerTests",
            dependencies: ["Scroblebler"],
            path: "ScrobbleblerTests"
        )
    ]
)
