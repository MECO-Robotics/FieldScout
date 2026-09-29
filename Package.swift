// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FieldScout",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FieldScout", targets: ["FieldScout"])
    ],
    targets: [
        .executableTarget(
            name: "FieldScout",
            path: "Sources/FieldScout"
        ),
        .testTarget(
            name: "FieldScoutTests",
            dependencies: ["FieldScout"],
            path: "Tests/FieldScoutTests"
        )
    ]
)
