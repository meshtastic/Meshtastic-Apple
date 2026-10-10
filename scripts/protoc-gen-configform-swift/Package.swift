// swift-tools-version:5.9
import PackageDescription

// A protoc plugin that emits typed field descriptors (tag, Swift key path, kind) for
// every message under Config and ModuleConfig, so a form can be driven by the schema
// without runtime reflection - which swift-protobuf does not offer for fields at their
// default value. See scripts/gen_protos.sh, phase 5.
//
// Pinned to the exact swift-protobuf version MeshtasticProtobufs resolves, not a floor:
// the key paths this plugin writes must spell properties the way protoc-gen-swift of the
// same version did (`sx126XRxBoostedGain`, `useI2SAsBuzzer`). A drift here fails to
// compile rather than misbehaving, but it is better not to drift.
let package = Package(
    name: "protoc-gen-configform-swift",
    platforms: [.macOS(.v10_15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", exact: "1.36.1")
    ],
    targets: [
        .executableTarget(
            name: "protoc-gen-configform-swift",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "SwiftProtobufPluginLibrary", package: "swift-protobuf")
            ]
        )
    ]
)
