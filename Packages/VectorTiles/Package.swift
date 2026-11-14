// swift-tools-version: 6.1
// mvt-tools with MVT decoding turned on. Since 3.0 its decoders are package traits, off by
// default, and an Xcode project has no way to enable a trait on a package it depends on.
import PackageDescription

let package = Package(
	name: "VectorTiles",
	platforms: [.iOS(.v16), .macCatalyst(.v16), .macOS(.v15), .visionOS(.v1)],
	products: [
		.library(name: "VectorTiles", targets: ["VectorTiles"])
	],
	dependencies: [
		.package(url: "https://github.com/Outdooractive/mvt-tools.git", from: "3.1.1", traits: ["EnableMVT"])
	],
	targets: [
		.target(
			name: "VectorTiles",
			dependencies: [.product(name: "MVTTools", package: "mvt-tools")]
		)
	]
)
