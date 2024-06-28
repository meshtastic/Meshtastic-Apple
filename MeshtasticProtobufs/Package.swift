// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MeshtasticProtobufs",
    products: [
        .library(
            name: "MeshtasticProtobufs",
            targets: ["MeshtasticProtobufs"]
        ),
    ], 
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.19.0"),
    ],
    targets: [
        .target(
            name: "MeshtasticProtobufs",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf")
            ]
        )
    ]
)
