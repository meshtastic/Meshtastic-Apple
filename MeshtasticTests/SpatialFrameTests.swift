//
//  SpatialFrameTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/10/26.
//
import CoreLocation
import Foundation
import MeshtasticProtobufs
import simd
import Testing
@testable import Meshtastic

@Suite("Spatial map frame")
struct SpatialFrameTests {
	let seattle = GeoBounds(minLon: -122.45, minLat: 47.55, maxLon: -122.25, maxLat: 47.70)

	@Test func theCenterIsTheOriginAndAxesPointEastAndSouth() {
		let frame = SpatialFrame(bounds: seattle)
		let center = frame.localPosition(latitude: frame.centerLatitude, longitude: frame.centerLongitude, altitude: 0)
		#expect(center == SIMD3<Float>(0, 0, 0))
		let northEast = frame.localPosition(latitude: seattle.maxLat, longitude: seattle.maxLon, altitude: 120)
		#expect(northEast.x > 0 && northEast.z < 0 && northEast.y == 120)
		#expect(abs(Double(northEast.x) - frame.widthMeters / 2) < 0.01)
		#expect(abs(Double(-northEast.z) - frame.depthMeters / 2) < 0.01)
	}

	@Test func positionsRoundTripToCoordinates() {
		let frame = SpatialFrame(bounds: seattle)
		let coordinate = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
		let p = frame.localPosition(coordinate, altitude: 0)
		let back = frame.coordinate(x: p.x, z: p.z)
		#expect(abs(back.latitude - coordinate.latitude) < 1e-5)
		#expect(abs(back.longitude - coordinate.longitude) < 1e-5)
	}

	@Test func mercatorFractionsSpanTheBox() {
		let frame = SpatialFrame(bounds: seattle)
		let northWest = frame.mercatorFraction(latitude: seattle.maxLat, longitude: seattle.minLon)
		let southEast = frame.mercatorFraction(latitude: seattle.minLat, longitude: seattle.maxLon)
		#expect(abs(northWest.x) < 1e-9 && abs(northWest.y) < 1e-9)
		#expect(abs(southEast.x - 1) < 1e-9 && abs(southEast.y - 1) < 1e-9)
		// Mercator rows are denser toward the equator, so the middle row sits a little north of the
		// midpoint latitude, and the fractions round-trip.
		let midLat = frame.latitude(atMercatorFraction: 0.5)
		#expect(midLat > (seattle.minLat + seattle.maxLat) / 2)
		#expect(abs(midLat - 47.625) < 0.01)
		#expect(abs(frame.mercatorFraction(latitude: midLat, longitude: seattle.minLon).y - 0.5) < 1e-9)
	}

	@Test func aCircleAroundNodesHoldsThemAllWithPadding() throws {
		let nodes = [
			CLLocationCoordinate2D(latitude: 47.60, longitude: -122.33),
			CLLocationCoordinate2D(latitude: 47.61, longitude: -122.20),
			CLLocationCoordinate2D(latitude: 47.70, longitude: -122.25)
		]
		let circle = try #require(SpatialCircle.around(nodes, padding: 0.15))
		#expect(abs(circle.latitude - 47.65) < 1e-9 && abs(circle.longitude - -122.265) < 1e-9, "centered on the middle of the nodes' extent")
		#expect(nodes.allSatisfy { circle.contains($0) })
		let farthest = nodes.map { circle.distanceMeters(to: $0) }.max() ?? 0
		#expect(abs(circle.radiusMeters - farthest * 1.15) < 1e-6)
		#expect(SpatialCircle.around([]) == nil)
	}

	@Test func aSingleNodeGetsTheMinimumRadius() throws {
		let node = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)
		let circle = try #require(SpatialCircle.around([node], minimumRadiusMeters: 1_000))
		#expect(circle.radiusMeters == 1_000)
		#expect(circle.distanceMeters(to: node) < 1e-6)
	}

	@Test func theBoundsAreTheSquareAroundTheCircle() throws {
		let circle = SpatialCircle(latitude: 47.6, longitude: -122.3, radiusMeters: 5_000)
		let frame = SpatialFrame(bounds: circle.bounds)
		#expect(abs(frame.widthMeters - 10_000) < 1 && abs(frame.depthMeters - 10_000) < 1)
		#expect(abs(frame.centerLatitude - 47.6) < 1e-9 && abs(frame.centerLongitude - -122.3) < 1e-9)
		let transform = SpatialModelTransform(frame: frame, baseElevation: 0, maxElevation: 0)
		#expect(abs(transform.diskRadius - 0.5) < 1e-5, "the disk fills the one meter footprint")
		// A point on the circle is on the disk's edge in the model.
		let east = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3 + 5_000 / circle.metersPerDegreeLongitude)
		#expect(abs(simd_length(SIMD2(transform.position(east, altitude: 0).x, transform.position(east, altitude: 0).z)) - transform.diskRadius) < 1e-4)
	}

	@Test func nodesFarFromTheAnchorStayOutOfTheCircle() throws {
		// The 125 km rule drops far nodes before the circle is fitted, so the circle stays tabletop sized.
		let anchor = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)
		let far = CLLocationCoordinate2D(latitude: 52.5, longitude: 13.4)
		let near = CLLocationCoordinate2D(latitude: 47.9, longitude: -122.2)
		let selection = SpatialMapArea.select([anchor, near, far], anchor: anchor)
		let circle = try #require(SpatialCircle.around(selection.coordinates))
		#expect(!circle.contains(far))
		#expect(circle.radiusMeters <= SpatialMapArea.maxRadiusMeters * 1.15)
	}

	@Test func packetEventsComeOnlyFromLiveReceptions() {
		var packet = MeshPacket()
		packet.from = 0x1234
		packet.to = 0xFFFF_FFFF
		packet.hopStart = 3
		packet.hopLimit = 1
		#expect(MeshPacketEvent(packet: packet) == nil, "a replayed packet has no RSSI")
		packet.rxRssi = -70
		packet.rxSnr = 5.5
		let event = MeshPacketEvent(packet: packet)
		#expect(event?.hopsTraveled == 2)
		#expect(event?.isBroadcast == true)
		#expect(event?.rxSnr == 5.5)

		var mqtt = MeshPacket()
		mqtt.from = 0x1234
		mqtt.viaMqtt = true
		#expect(MeshPacketEvent(packet: mqtt) != nil, "MQTT receptions have no RSSI but are live")

		var ack = packet
		ack.decoded.portnum = .routingApp
		ack.rxTime = 0
		#expect(MeshPacketEvent(packet: ack) == nil, "a routing packet with no receive time is the radio's own ACK")
	}
}
