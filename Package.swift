// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SpaceMouseWS",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SpaceMouse", targets: ["SpaceMouse"]),
    ],
    targets: [
        .target(name: "SpaceMouse"),
        .executableTarget(
            name: "spacemouse-debug",
            dependencies: ["SpaceMouse"]
        ),
    ]
)
