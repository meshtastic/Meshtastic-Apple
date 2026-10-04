// PositionWireUnitsTests.swift
// MeshtasticTests
//
// Position.ground_speed is km/h and ground_track is 1e-5 degrees on the wire. These cover the
// phone fix the app sends to its radio and the headings it stores from the mesh.

import CoreLocation
import Foundation
import MeshtasticProtobufs
import SwiftData
import Testing
@testable import Meshtastic

@Suite("Position wire units: sending a phone fix")
struct PositionPhoneFixTests {

	private func fix(course: Double, courseAccuracy: Double, speed: Double, speedAccuracy: Double, verticalAccuracy: Double = -1) -> CLLocation {
		CLLocation(
			coordinate: CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321),
			altitude: 56,
			horizontalAccuracy: 5,
			verticalAccuracy: verticalAccuracy,
			course: course,
			courseAccuracy: courseAccuracy,
			speed: speed,
			speedAccuracy: speedAccuracy,
			timestamp: Date(timeIntervalSince1970: 1_700_000_000)
		)
	}

	@Test func speed_isKilometersPerHourRounded() {
		#expect(Position.groundSpeedKmh(metersPerSecond: 10, accuracy: 1) == 36)
		#expect(Position.groundSpeedKmh(metersPerSecond: 2.5, accuracy: 1) == 9)
		#expect(Position.groundSpeedKmh(metersPerSecond: 1.2, accuracy: 1) == 4)
	}

	@Test func speed_zeroIsAReading() {
		#expect(Position.groundSpeedKmh(metersPerSecond: 0, accuracy: 0) == 0)
	}

	@Test func speed_invalidIsNil() {
		#expect(Position.groundSpeedKmh(metersPerSecond: -1, accuracy: 1) == nil)
		#expect(Position.groundSpeedKmh(metersPerSecond: 3, accuracy: -1) == nil)
		#expect(Position.groundSpeedKmh(metersPerSecond: .nan, accuracy: 1) == nil)
		#expect(Position.groundSpeedKmh(metersPerSecond: .infinity, accuracy: 1) == nil)
	}

	@Test func track_isHundredThousandthsOfADegree() {
		#expect(Position.groundTrack(courseDegrees: 90, accuracy: 5) == 9_000_000)
		#expect(Position.groundTrack(courseDegrees: 271.123456, accuracy: 5) == 27_112_346)
	}

	@Test func track_dueNorthIsAReading() {
		#expect(Position.groundTrack(courseDegrees: 0, accuracy: 5) == 0)
	}

	@Test func track_wrapsAtAFullCircle() {
		#expect(Position.groundTrack(courseDegrees: 359.999999, accuracy: 5) == 0)
		#expect(Position.groundTrack(courseDegrees: 360, accuracy: 5) == 0)
	}

	@Test func track_invalidIsNil() {
		#expect(Position.groundTrack(courseDegrees: -1, accuracy: 5) == nil)
		#expect(Position.groundTrack(courseDegrees: 90, accuracy: -1) == nil)
		#expect(Position.groundTrack(courseDegrees: .nan, accuracy: 5) == nil)
	}

	@Test func altitudeHae_isRoundedMeters() {
		#expect(Position.altitudeHae(ellipsoidalAltitude: 1234.6, verticalAccuracy: 3) == 1235)
		#expect(Position.altitudeHae(ellipsoidalAltitude: -12.4, verticalAccuracy: 3) == -12)
		#expect(Position.altitudeHae(ellipsoidalAltitude: 0, verticalAccuracy: 3) == 0)
	}

	@Test func altitudeHae_invalidIsNil() {
		#expect(Position.altitudeHae(ellipsoidalAltitude: 100, verticalAccuracy: 0) == nil)
		#expect(Position.altitudeHae(ellipsoidalAltitude: 100, verticalAccuracy: -1) == nil)
		#expect(Position.altitudeHae(ellipsoidalAltitude: .nan, verticalAccuracy: 3) == nil)
	}

	@Test func unknownFix_leavesSpeedTrackAndHaeUnset() {
		var position = Position()
		position.setSpeedTrackAndHae(from: fix(course: -1, courseAccuracy: -1, speed: -1, speedAccuracy: -1))
		#expect(!position.hasGroundSpeed)
		#expect(!position.hasGroundTrack)
		#expect(!position.hasAltitudeHae)
	}

	@Test func stoppedFacingNorth_sendsZeroSpeedAndTrack() {
		var position = Position()
		position.setSpeedTrackAndHae(from: fix(course: 0, courseAccuracy: 10, speed: 0, speedAccuracy: 0.5))
		#expect(position.hasGroundSpeed)
		#expect(position.groundSpeed == 0)
		#expect(position.hasGroundTrack)
		#expect(position.groundTrack == 0)
	}

	@Test func movingFix_sendsWireUnits() {
		var position = Position()
		position.setSpeedTrackAndHae(from: fix(course: 90, courseAccuracy: 5, speed: 10, speedAccuracy: 0.5))
		#expect(position.groundSpeed == 36)
		#expect(position.groundTrack == 9_000_000)
	}

	@Test func validVerticalAccuracy_sendsEllipsoidalAltitude() {
		let location = fix(course: -1, courseAccuracy: -1, speed: -1, speedAccuracy: -1, verticalAccuracy: 3)
		var position = Position()
		position.setSpeedTrackAndHae(from: location)
		#expect(position.hasAltitudeHae)
		#expect(position.altitudeHae == Int32(location.ellipsoidalAltitude.rounded()))
	}
}

@Suite("Position wire units: reading ground track")
struct PositionGroundTrackReadingTests {

	private func position(groundTrack: UInt32?) -> Position {
		var position = Position()
		if let groundTrack { position.groundTrack = groundTrack }
		return position
	}

	@Test func unset_isNil() {
		#expect(position(groundTrack: nil).groundTrackDegrees == nil)
	}

	@Test func zero_isNorth() {
		#expect(position(groundTrack: 0).groundTrackDegrees == 0)
	}

	@Test func scaledValue_isWholeDegrees() {
		#expect(position(groundTrack: 9_000_000).groundTrackDegrees == 90)
		#expect(position(groundTrack: 27_112_346).groundTrackDegrees == 271)
		#expect(position(groundTrack: 4_550_000).groundTrackDegrees == 46)
	}

	@Test func justBelowAFullCircle_wrapsToNorth() {
		#expect(position(groundTrack: 35_999_999).groundTrackDegrees == 0)
	}

	@Test func outOfRange_isNil() {
		#expect(position(groundTrack: 36_000_000).groundTrackDegrees == nil)
		#expect(position(groundTrack: 0xFFFF_FFFF).groundTrackDegrees == nil)
	}
}

@Suite("Position wire units: stored heading", .serialized)
@MainActor
struct PositionStoredHeadingTests {

	private func positionPacket(from nodeNum: UInt32, groundTrack: UInt32?) throws -> MeshPacket {
		var position = Position()
		position.latitudeI = Int32(47.6062 * 1e7)
		position.longitudeI = Int32(-122.3321 * 1e7)
		position.groundSpeed = 36
		if let groundTrack { position.groundTrack = groundTrack }

		var dataMessage = DataMessage()
		dataMessage.payload = try position.serializedData()
		dataMessage.portnum = .positionApp

		var packet = MeshPacket()
		packet.from = nodeNum
		packet.decoded = dataMessage
		return packet
	}

	private func latestPosition(_ nodeNum: Int64) throws -> PositionEntity? {
		let context = ModelContext(sharedModelContainer)
		return try context.fetch(FetchDescriptor<PositionEntity>(
			predicate: #Predicate { $0.nodePosition?.num == nodeNum && $0.latest == true }
		)).first
	}

	@Test func positionPacket_storesHeadingInDegrees() async throws {
		let nodeNum: UInt32 = 0x20DE_FD01
		let mesh = MeshPackets(modelContainer: sharedModelContainer)
		await mesh.upsertPositionPacket(packet: try positionPacket(from: nodeNum, groundTrack: 9_000_000))
		await mesh.flushDebouncedSaves()

		let stored = try #require(try latestPosition(Int64(nodeNum)))
		#expect(stored.heading == 90)
		#expect(stored.speed == 36)
	}

	@Test func positionPacket_withoutTrack_clearsAReusedHeading() async throws {
		let nodeNum: UInt32 = 0x20DE_FD02
		let mesh = MeshPackets(modelContainer: sharedModelContainer)
		await mesh.upsertPositionPacket(packet: try positionPacket(from: nodeNum, groundTrack: 9_000_000))
		await mesh.flushDebouncedSaves()
		await mesh.upsertPositionPacket(packet: try positionPacket(from: nodeNum, groundTrack: nil))
		await mesh.flushDebouncedSaves()

		let stored = try #require(try latestPosition(Int64(nodeNum)))
		#expect(stored.heading == 0)
	}

	@Test func nodeInfo_storesHeadingInDegrees() async throws {
		let nodeNum: UInt32 = 0x20DE_FD03
		var nodeInfo = NodeInfo()
		nodeInfo.num = nodeNum
		nodeInfo.position.latitudeI = Int32(47.6062 * 1e7)
		nodeInfo.position.longitudeI = Int32(-122.3321 * 1e7)
		nodeInfo.position.groundTrack = 18_000_000

		let mesh = MeshPackets(modelContainer: sharedModelContainer)
		_ = await mesh.nodeInfoPacket(nodeInfo: nodeInfo, channel: 0)

		let stored = try #require(try latestPosition(Int64(nodeNum)))
		#expect(stored.heading == 180)
	}
}

@Suite("Position wire units: TAK export")
@MainActor
struct PositionTAKExportTests {

	@Test func storedPosition_exportsMetersPerSecondAndDegrees() throws {
		let context = ModelContext(sharedModelContainer)
		let node = NodeInfoEntity()
		node.num = 0x20DE_FD04
		context.insert(node)
		let position = PositionEntity()
		context.insert(position)
		position.latitudeI = Int32(47.6062 * 1e7)
		position.longitudeI = Int32(-122.3321 * 1e7)
		position.speed = 36
		position.heading = 90
		position.latest = true
		position.nodePosition = node
		node.latestPositionCache = position

		let bridge = TAKMeshtasticBridge(accessoryManager: nil, takServerManager: nil)
		let cot = try #require(bridge.createCoTFromNode(node))
		#expect(cot.track?.speed == 10)
		#expect(cot.track?.course == 90)
	}
}
