// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "protoc-gen-fieldmeta-swift",
    platforms: [.macOS(.v10_15)],
    dependencies: [
        // Mirror MeshtasticProtobufs/Package.swift's requirement so this plugin's naming
        // engine (SwiftProtobufPluginLibrary/NamingUtils) resolves to the same version
        // that generates the app's .pb.swift files — keeping emitted type/property names
        // in lockstep with the real generated code.
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.33.3")
    ],
    targets: [
        .executableTarget(
            name: "protoc-gen-fieldmeta-swift",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "SwiftProtobufPluginLibrary", package: "swift-protobuf")
            ]
        )
    ]
)
