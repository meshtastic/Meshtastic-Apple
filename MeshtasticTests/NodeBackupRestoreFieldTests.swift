//
//  NodeBackupRestoreFieldTests.swift
//  MeshtasticTests
//
//  Fields the backup restore used to drop.
//

import Foundation
import SwiftData
import Testing
@testable import Meshtastic

@Suite("NodeBackupManager restore field coverage")
@MainActor
struct NodeBackupRestoreFieldTests {

	// MARK: - Helpers

	private func makeContext() throws -> ModelContext {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config = ModelConfiguration(
			"NodeBackupRestoreFieldTests-\(UUID().uuidString)",
			schema: schema,
			isStoredInMemoryOnly: true,
			allowsSave: true
		)
		let container = try ModelContainer(for: schema, configurations: config)
		let context = ModelContext(container)
		context.autosaveEnabled = false
		return context
	}

	// MARK: - NodeInfoEntity

	@Test("Node restore keeps power channel labels, status and trust flags")
	func nodeFieldsSurviveRestore() throws {
		let backup = try makeContext()
		let live = try makeContext()

		let node = NodeInfoEntity()
		node.num = 0x1234_5678
		node.id = 42
		node.powerChannelLabels = ["Solar", "Battery", "Load"]
		node.nodeStatus = "On the trail"
		node.isKeyManuallyVerified = true
		node.hasXeddsaSigned = true
		backup.insert(node)
		try backup.save()

		let restored = try NodeBackupManager.importNodes(from: backup, into: live)
		try live.save()

		let dst = try #require(restored[0x1234_5678])
		#expect(dst.id == 42)
		#expect(dst.powerChannelLabels == ["Solar", "Battery", "Load"])
		#expect(dst.nodeStatus == "On the trail")
		#expect(dst.isKeyManuallyVerified)
		#expect(dst.hasXeddsaSigned)
	}

	// MARK: - WaypointEntity

	@Test("Waypoint restore keeps geofence settings and the local-only flag")
	func waypointFieldsSurviveRestore() throws {
		let backup = try makeContext()
		let live = try makeContext()

		let waypoint = WaypointEntity()
		waypoint.id = 777
		waypoint.name = "Camp"
		waypoint.isLocal = true
		waypoint.geofenceRadius = 250
		waypoint.hasBoundingBox = true
		waypoint.boundingBoxLatitudeNorthI = 400_000_000
		waypoint.boundingBoxLatitudeSouthI = 399_000_000
		waypoint.boundingBoxLongitudeEastI = -1_050_000_000
		waypoint.boundingBoxLongitudeWestI = -1_051_000_000
		waypoint.notifyOnEnter = true
		waypoint.notifyOnExit = true
		waypoint.notifyFavoritesOnly = true
		backup.insert(waypoint)
		try backup.save()

		try NodeBackupManager.importWaypoints(from: backup, into: live)
		try live.save()

		let dst = try #require(try live.fetch(FetchDescriptor<WaypointEntity>()).first)
		#expect(dst.id == 777)
		#expect(dst.isLocal)
		#expect(dst.geofenceRadius == 250)
		#expect(dst.hasBoundingBox)
		#expect(dst.boundingBoxLatitudeNorthI == 400_000_000)
		#expect(dst.boundingBoxLatitudeSouthI == 399_000_000)
		#expect(dst.boundingBoxLongitudeEastI == -1_050_000_000)
		#expect(dst.boundingBoxLongitudeWestI == -1_051_000_000)
		#expect(dst.notifyOnEnter)
		#expect(dst.notifyOnExit)
		#expect(dst.notifyFavoritesOnly)
	}

	// MARK: - TelemetryEntity

	@Test("Telemetry restore keeps particulate matter readings")
	func airQualityTelemetrySurvivesRestore() throws {
		let backup = try makeContext()
		let live = try makeContext()

		let node = NodeInfoEntity()
		node.num = 99
		backup.insert(node)

		let telemetry = TelemetryEntity()
		telemetry.metricsType = 3
		telemetry.pm10Standard = 1
		telemetry.pm25Standard = 2
		telemetry.pm100Standard = 3
		telemetry.pm10Environmental = 4
		telemetry.pm25Environmental = 5
		telemetry.pm100Environmental = 6
		telemetry.nodeTelemetry = node
		backup.insert(telemetry)
		try backup.save()

		let nodes = try NodeBackupManager.importNodes(from: backup, into: live)
		try NodeBackupManager.importTelemetry(from: backup, into: live, nodesByNum: nodes)
		try live.save()

		let dst = try #require(try live.fetch(FetchDescriptor<TelemetryEntity>()).first)
		#expect(dst.pm10Standard == 1)
		#expect(dst.pm25Standard == 2)
		#expect(dst.pm100Standard == 3)
		#expect(dst.pm10Environmental == 4)
		#expect(dst.pm25Environmental == 5)
		#expect(dst.pm100Environmental == 6)
		#expect(dst.nodeTelemetry?.num == 99)
	}

	// MARK: - MessageEntity

	@Test("Message restore keeps the XEdDSA signature flag")
	func messageSignatureFlagSurvivesRestore() throws {
		let backup = try makeContext()
		let live = try makeContext()

		let message = MessageEntity()
		message.messageId = 123_456
		message.messagePayload = "signed hello"
		message.xeddsaSigned = true
		backup.insert(message)
		try backup.save()

		try NodeBackupManager.importMessages(from: backup, into: live, usersByNum: [:])
		try live.save()

		let dst = try #require(try live.fetch(FetchDescriptor<MessageEntity>()).first)
		#expect(dst.messageId == 123_456)
		#expect(dst.xeddsaSigned)
	}
}
