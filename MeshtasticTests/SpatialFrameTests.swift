//
//  SpatialFrameTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/10/26.
//
import CoreLocation
import Foundation
import MeshtasticProtobufs
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

	@Test func aBoxAroundNodesIsPaddedAndNeverASliver() throws {
		let nodes = [CLLocationCoordinate2D(latitude: 47.60, longitude: -122.33), CLLocationCoordinate2D(latitude: 47.61, longitude: -122.20)]
		let box = try #require(GeoBounds.around(nodes, padding: 0.1, minimumSpanMeters: 2_000))
		#expect(box.minLon < -122.33 && box.maxLon > -122.20)
		let frame = SpatialFrame(bounds: box)
		#expect(frame.depthMeters >= frame.widthMeters * 0.5)
		#expect(box.contains(nodes[0]) && box.contains(nodes[1]))
		#expect(GeoBounds.around([]) == nil)
	}

	@Test func aSingleNodeGetsTheMinimumBox() throws {
		let box = try #require(GeoBounds.around([CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)], minimumSpanMeters: 2_000))
		let frame = SpatialFrame(bounds: box)
		#expect(abs(frame.depthMeters - 2_000) < 1 && abs(frame.widthMeters - 2_000) < 1)
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
