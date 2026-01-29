// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "hops",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "HopsCore",
            targets: ["HopsCore"]
        ),
        .library(
            name: "HopsProto",
            targets: ["HopsProto"]
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
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.62.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.25.0"),
        .package(url: "https://github.com/apple/containerization.git", from: "0.23.2")
    ],
    targets: [
        .target(
            name: "HopsProto",
            dependencies: [
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf")
            ]
        ),
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
                "HopsProto",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf")
            ]
        ),
        .executableTarget(
            name: "hopsd",
            dependencies: [
                "HopsCore",
                "HopsProto",
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "Containerization", package: "containerization"),
                .product(name: "ContainerizationExtras", package: "containerization")
            ]
        ),
        .testTarget(
            name: "HopsCoreTests",
            dependencies: ["HopsCore"]
        )
    ]
)
