// swift-tools-version:5.9
// org.meshtastic:kp1812 (ITU-R P.1812) as the XCFramework each kp1812 release attaches.
// To update, copy the url and checksum from that release's Package.swift.
import PackageDescription

let package = Package(
	name: "Kp1812",
	platforms: [.iOS(.v15), .macOS(.v12), .macCatalyst(.v15), .visionOS(.v1)],
	products: [
		.library(name: "Kp1812", targets: ["Kp1812"])
	],
	targets: [
		.binaryTarget(
			name: "Kp1812",
			url: "https://github.com/meshtastic/kp1812/releases/download/v0.2.0/Kp1812.xcframework.zip",
			checksum: "da6f20f277e5ba17730166c7714ee67b65cf974ab1b8eda6e7c37dabe8a26736"
		)
	]
)
