// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "TrackKit",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "TrackKit",
            targets: ["TrackKit"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "TrackKit",
            dependencies: [],
            path: "Sources/TrackKit",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "TrackKitTests",
            dependencies: ["TrackKit"],
            path: "Tests/TrackKitTests"
        ),
    ]
) 