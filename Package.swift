// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "hops",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "HopsCore",
            targets: ["HopsCore"]
        ),
        .executable(
            name: "hops",
            targets: ["hops"]
        ),
        .executable(
            name: "hopsd",
            targets: ["hopsd"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.5.0"),
        .package(url: "https://github.com/grpc/grpc-swift.git", from: "1.21.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.62.0")
    ],
    targets: [
        .target(
            name: "HopsCore",
            dependencies: [
                .product(name: "TOMLKit", package: "TOMLKit")
            ]
        ),
        .executableTarget(
            name: "hops",
            dependencies: [
                "HopsCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .executableTarget(
            name: "hopsd",
            dependencies: [
                "HopsCore",
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "HopsCoreTests",
            dependencies: ["HopsCore"]
        )
    ]
)
