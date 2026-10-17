// swift-tools-version:6.0
//
//  Package.swift
//  ShowcaseContent
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
//  The showcase room for the visionOS immersive space, as a Reality Composer Pro content
//  package. Xcode compiles ShowcaseContent.rkassets into the package's resource bundle; the app
//  loads it with `Entity(named: "Showcase", in: showcaseContentBundle)`.

import PackageDescription

let package = Package(
	name: "ShowcaseContent",
	platforms: [
		.visionOS(.v2)
	],
	products: [
		.library(name: "ShowcaseContent", targets: ["ShowcaseContent"])
	],
	targets: [
		.target(name: "ShowcaseContent")
	]
)
