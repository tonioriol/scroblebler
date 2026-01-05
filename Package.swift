// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Scroblebler",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Scroblebler", targets: ["Scroblebler"])
    ],
    dependencies: [
        .package(url: "https://github.com/ejbills/mediaremote-adapter.git", branch: "master"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Scroblebler",
            dependencies: [
                .product(name: "MediaRemoteAdapter", package: "mediaremote-adapter"),
                .product(name: "GRDB", package: "GRDB.swift")
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
