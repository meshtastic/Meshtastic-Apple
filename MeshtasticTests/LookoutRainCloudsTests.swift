//
//  LookoutRainCloudsTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/13/26.
//
#if os(visionOS)
import CoreLocation
import Foundation
import Testing
@testable import Meshtastic

@Suite("Lookout rain clouds")
struct LookoutRainCloudsTests {
	let site = LookoutSite(latitude: 47.5, longitude: -121.5, elevation: 1_200, name: nil)

	@Test func boxReachesTheTerrainsEdge() {
		let bounds = LookoutRainClouds.bounds(around: site)
		let center = CLLocation(latitude: site.latitude, longitude: site.longitude)
		let north = CLLocation(latitude: bounds.maxLat, longitude: site.longitude)
		let east = CLLocation(latitude: site.latitude, longitude: bounds.maxLon)
		#expect(abs(north.distance(from: center) - LookoutRainClouds.maxRadius) < 1_000)
		#expect(abs(east.distance(from: center) - LookoutRainClouds.maxRadius) < 1_000)
	}

	@Test func cloudsFloatOverTheSite() {
		#expect(LookoutRainClouds.altitude(for: site) == LookoutRainClouds.cloudBase)
		let peak = LookoutSite(latitude: 47.5, longitude: -121.5, elevation: 3_000, name: nil)
		#expect(LookoutRainClouds.altitude(for: peak) == 3_000 + LookoutRainClouds.siteClearance)
	}

	@Test func sheetIsPlacedLikeTheTerrain() {
		let frame = SpatialFrame(bounds: LookoutRainClouds.bounds(around: site))
		let heading = LookoutTerrain.frontHeading
		let mesh = LookoutRainClouds.mesh(site: site, heading: heading, frame: frame)
		#expect(mesh.positions.count == LookoutRainClouds.rings * LookoutRainClouds.spokes + 1, "the rings and the cap's middle")
		#expect(mesh.indices.count == (LookoutRainClouds.rings - 1) * LookoutRainClouds.spokes * 6 + LookoutRainClouds.spokes * 3)
		#expect(mesh.positions.last!.y > 0, "the cap is overhead")
		// The first ring's first spoke: due north, at the inner radius.
		let rise = LookoutRainClouds.altitude(for: site) - LookoutTerrain.eyeElevation(for: site)
		let expected = LookoutTerrain.direction(bearing: 0, distance: LookoutRainClouds.innerRadius, rise: rise, heading: heading)
			* LookoutTerrain.depth(LookoutRainClouds.innerRadius)
		#expect(simd_distance(mesh.positions[0], expected) < 0.001)
		#expect(mesh.positions[0].y > 0, "over the eye")
		#expect(mesh.uvs.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
	}

	@Test func northIsAtTheImagesTop() {
		let frame = SpatialFrame(bounds: LookoutRainClouds.bounds(around: site))
		let mesh = LookoutRainClouds.mesh(site: site, heading: LookoutTerrain.frontHeading, frame: frame)
		let last = (LookoutRainClouds.rings - 1) * LookoutRainClouds.spokes
		let north = mesh.uvs[last], south = mesh.uvs[last + LookoutRainClouds.spokes / 2]
		// Texture v runs up from the image's bottom, so north has the larger v.
		#expect(north.y > south.y)
	}

	@Test func farRainFades() {
		#expect(LookoutRainClouds.visibility(distance: 0) == 1)
		#expect(LookoutRainClouds.visibility(distance: 30_000) < LookoutRainClouds.visibility(distance: 5_000))
		#expect(LookoutRainClouds.visibility(distance: LookoutRainClouds.maxRadius) > 0)
		#expect(LookoutRainClouds.visibility(distance: LookoutRainClouds.maxRadius + 1) == 0)
	}
}
#endif
