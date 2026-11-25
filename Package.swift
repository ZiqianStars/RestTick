// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RestTick",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "RestTickCore",
            path: "Sources/RestTickCore"
        ),
        .executableTarget(
            name: "RestTick",
            dependencies: ["RestTickCore"],
            path: "Sources/RestTick"
        ),
        .executableTarget(
            name: "RestTickTests",
            dependencies: ["RestTickCore"],
            path: "Tests/RestTickTests"
        )
    ]
)
