//
//  SpatialZoomTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/12/26.
//
import CoreLocation
import Foundation
import simd
import Testing
@testable import Meshtastic

@Suite("Spatial map zoom")
struct SpatialZoomTests {
	private let full = SpatialCircle(latitude: 47.6, longitude: -122.3, radiusMeters: 20_000)

	private func offset(_ circle: SpatialCircle, from other: SpatialCircle) -> Double {
		other.distanceMeters(to: CLLocationCoordinate2D(latitude: circle.latitude, longitude: circle.longitude))
	}

	@Test func zoomStaysBetweenTheWholeMeshAndAOneKilometerRadius() {
		#expect(SpatialZoom.maximumZoom(fullRadiusMeters: 20_000) == 20)
		#expect(SpatialZoom.clamp(0.3, fullRadiusMeters: 20_000) == 1)
		#expect(SpatialZoom.clamp(5, fullRadiusMeters: 20_000) == 5)
		#expect(SpatialZoom.clamp(50, fullRadiusMeters: 20_000) == 20)
		// A mesh already at the smallest circle can't zoom.
		#expect(SpatialZoom.maximumZoom(fullRadiusMeters: 1_000) == 1)
		#expect(SpatialZoom.clamp(3, fullRadiusMeters: 800) == 1)
		#expect(SpatialZoom.clamp(.nan, fullRadiusMeters: 20_000) == 1)
		#expect(SpatialZoom.maximumZoom(fullRadiusMeters: .infinity) == 1)
	}

	@Test func theZoomedCircleIsSmallerAroundTheFullCenter() {
		let circle = SpatialZoom.circle(full: full, zoom: 4, center: nil)
		#expect(circle.radiusMeters == 5_000)
		#expect(circle.latitude == full.latitude && circle.longitude == full.longitude)
		// Past the limit it stops at 1 km.
		#expect(SpatialZoom.circle(full: full, zoom: 100, center: nil).radiusMeters == 1_000)
		// Zoom 1 is the whole mesh, wherever the center was.
		let node = CLLocationCoordinate2D(latitude: 47.65, longitude: -122.25)
		#expect(SpatialZoom.circle(full: full, zoom: 1, center: node) == full)
		#expect(SpatialZoom.circle(full: full, zoom: 0.5, center: node) == full)
	}

	@Test func theZoomedCircleCentersOnANodeInside() {
		// About 4.5 km north-east: well inside the room a 5 km circle has.
		let node = CLLocationCoordinate2D(latitude: 47.63, longitude: -122.26)
		let circle = SpatialZoom.circle(full: full, zoom: 4, center: node)
		#expect(abs(circle.latitude - node.latitude) < 1e-9)
		#expect(abs(circle.longitude - node.longitude) < 1e-9)
		#expect(circle.contains(node))
	}

	@Test func theZoomedCircleStaysInsideTheFullCircle() {
		// A node near the rim: the circle is pulled in so it never shows ground past the mesh.
		let rim = CLLocationCoordinate2D(latitude: full.latitude + 19_000 / SpatialFrame.metersPerDegreeLatitude, longitude: full.longitude)
		for zoom in [1.5, 2, 4, 10, 20] {
			let circle = SpatialZoom.circle(full: full, zoom: zoom, center: rim)
			#expect(offset(circle, from: full) + circle.radiusMeters <= full.radiusMeters + 1)
			#expect(circle.latitude > full.latitude)
		}
		// Far enough in, the node is still on the disk.
		#expect(SpatialZoom.circle(full: full, zoom: 4, center: rim).contains(rim))
	}

	@Test func nodesOutsideTheZoomedCircleAreHidden() {
		let circle = SpatialZoom.circle(full: full, zoom: 4, center: nil)
		let inside = CLLocationCoordinate2D(latitude: full.latitude + 0.02, longitude: full.longitude)
		let outside = CLLocationCoordinate2D(latitude: full.latitude + 0.1, longitude: full.longitude)
		#expect(SpatialZoom.isShown(inside, in: circle))
		#expect(!SpatialZoom.isShown(outside, in: circle))
		// Both are on the whole-mesh map.
		#expect(SpatialZoom.isShown(outside, in: full))
	}

	@Test func pinsOnTheBuiltTerrainAreHiddenPastTheRim() {
		// The same nodes placed on a model of the zoomed circle: on the disk or past its rim.
		let circle = SpatialZoom.circle(full: full, zoom: 4, center: nil)
		let transform = SpatialModelTransform(frame: SpatialFrame(bounds: circle.bounds), baseElevation: 0, maxElevation: 0)
		let inside = transform.position(CLLocationCoordinate2D(latitude: full.latitude + 0.02, longitude: full.longitude), altitude: 0)
		let outside = transform.position(CLLocationCoordinate2D(latitude: full.latitude + 0.1, longitude: full.longitude), altitude: 0)
		#expect(SpatialZoom.isOnDisk(x: inside.x, z: inside.z, diskRadius: transform.diskRadius))
		#expect(!SpatialZoom.isOnDisk(x: outside.x, z: outside.z, diskRadius: transform.diskRadius))
	}

	@Test func thePreviewIsHeldUnderTheBezel() {
		// Zooming in four times on the middle: scaled only as far as the bezel.
		let zoomIn = SpatialZoom.Preview(offset: .zero, scale: 4, diskRadius: 0.5, maxRadius: 0.55)
		#expect(abs(zoomIn.scale - 1.1) < 1e-5)
		#expect(zoomIn.translation == .zero)
		// Zooming out shrinks the terrain inside the rim, and not below a fifth.
		#expect(SpatialZoom.Preview(offset: .zero, scale: 0.5, diskRadius: 0.5, maxRadius: 0.55).scale == 0.5)
		#expect(SpatialZoom.Preview(offset: .zero, scale: 0.01, diskRadius: 0.5, maxRadius: 0.55).scale == 0.2)
		// A shift toward a center off the middle is cut so the terrain stays under the bezel.
		let shifted = SpatialZoom.Preview(offset: [0.3, 0], scale: 0.5, diskRadius: 0.5, maxRadius: 0.55)
		#expect(shifted.translation.x < 0)
		#expect(abs(shifted.translation.x) + shifted.scale * 0.5 <= 0.55 + 1e-5)
		// The new center lands on the middle when there is room.
		let roomy = SpatialZoom.Preview(offset: [0.1, 0], scale: 0.5, diskRadius: 0.5, maxRadius: 0.55)
		#expect(simd_length(roomy.apply(x: 0.1, z: 0)) < 1e-5)
		#expect(SpatialZoom.Preview(offset: .zero, scale: .nan, diskRadius: 0.5, maxRadius: 0.55) == .identity)
	}

	@Test func flyoverPointsPastTheRimEndAtIt() {
		let past = SpatialZoom.clampToDisk([0.6, 0.04, -0.8], diskRadius: 0.5)
		#expect(abs((past.x * past.x + past.z * past.z).squareRoot() - 0.5) < 1e-5)
		#expect(past.y == 0.04)
		#expect(past.x > 0 && past.z < 0)
		let inside = SIMD3<Float>(0.1, 0.02, 0.2)
		#expect(SpatialZoom.clampToDisk(inside, diskRadius: 0.5) == inside)
	}
}
