// swift-tools-version:6.0
//
//  Package.swift
//  ShackContent
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
//  The ham shack room for the visionOS immersive space, as a Reality Composer Pro content
//  package. Xcode compiles ShackContent.rkassets into the package's resource bundle; the app
//  loads it with `Entity(named: "Shack", in: shackContentBundle)`.

import PackageDescription

let package = Package(
	name: "ShackContent",
	platforms: [
		.visionOS(.v2)
	],
	products: [
		.library(name: "ShackContent", targets: ["ShackContent"])
	],
	targets: [
		.target(name: "ShackContent")
	]
)
