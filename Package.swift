// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftX",
    products: [
        .library(name: "SwiftX", targets: ["SwiftX"]),
    ],
    targets: [
        .target(name: "SwiftX"),
        .testTarget(name: "SwiftXTests", dependencies: ["SwiftX"]),
    ]
)
