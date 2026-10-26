// swift-tools-version:6.0
//
//  Package.swift
//  CinemaContent
//
//  Copyright(c) Garth Vander Houwen 10/23/26.
//
//  The 360° environment images for the visionOS cinema. A separate package so the images only
//  ship in the visionOS app. scripts/cinema builds them.

import PackageDescription

let package = Package(
	name: "CinemaContent",
	platforms: [
		.visionOS(.v2)
	],
	products: [
		.library(name: "CinemaContent", targets: ["CinemaContent"])
	],
	targets: [
		.target(name: "CinemaContent", resources: [.copy("Environments")])
	]
)
