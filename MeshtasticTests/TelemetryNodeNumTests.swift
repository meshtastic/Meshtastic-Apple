//
//  TelemetryNodeNumTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//

import Foundation
import SwiftData
import MeshtasticProtobufs
import Testing
@testable import Meshtastic

/// Telemetry is tied to its node by `TelemetryEntity.nodeNum`. Rows saved by earlier versions only
/// have the `nodeTelemetry` relationship until the one-time backfill copies the number across.
///
/// Serialized because the backfill flag lives in UserDefaults and the lookups read it.
@Suite("Telemetry node number", .serialized)
@MainActor
struct TelemetryNodeNumTests {

	private static let connectedNode: Int64 = 0x7E1E_FFFF

	private func makeContainer() throws -> ModelContainer {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config = ModelConfiguration(
			"TelemetryNodeNumTests-\(UUID().uuidString)",
			schema: schema,
			isStoredInMemoryOnly: true,
			allowsSave: true
		)
		return try ModelContainer(for: schema, configurations: config)
	}

	/// Runs `body` with the backfill flag set to `complete`, then restores it.
	private func withBackfill<T>(complete: Bool, _ body: () async throws -> T) async rethrows -> T {
		let saved = TelemetryNodeNumBackfill.isComplete
		TelemetryNodeNumBackfill.isComplete = complete
		defer { TelemetryNodeNumBackfill.isComplete = saved }
		return try await body()
	}

	private func makeNode(_ num: Int64, in context: ModelContext) -> NodeInfoEntity {
		let node = NodeInfoEntity()
		node.num = num
		node.id = num
		context.insert(node)
		return node
	}

	/// A row as this version writes it: node number only.
	@discardableResult
	private func addRow(_ num: Int64, type: Int32, time: Date = Date(), in context: ModelContext) -> TelemetryEntity {
		let row = TelemetryEntity()
		row.metricsType = type
		row.time = time
		row.nodeNum = num
		context.insert(row)
		return row
	}

	/// A row as earlier versions wrote it: relationship only, `nodeNum` still 0.
	@discardableResult
	private func addLegacyRow(_ node: NodeInfoEntity, type: Int32, time: Date = Date(), in context: ModelContext) -> TelemetryEntity {
		let row = TelemetryEntity()
		row.metricsType = type
		row.time = time
		context.insert(row)
		row.nodeTelemetry = node
		return row
	}

	private func count(_ predicate: Predicate<TelemetryEntity>? = nil, in context: ModelContext) throws -> Int {
		try context.fetchCount(FetchDescriptor<TelemetryEntity>(predicate: predicate))
	}

	private func makeTelemetryPacket(from nodeNum: UInt32, _ fill: (inout Telemetry) -> Void) throws -> MeshPacket {
		var telemetry = Telemetry()
		fill(&telemetry)
		telemetry.time = 1_700_000_500
		var data = DataMessage()
		data.payload = try telemetry.serializedData()
		data.portnum = .telemetryApp
		var packet = MeshPacket()
		packet.id = UInt32.random(in: 1..<UInt32.max)
		packet.from = nodeNum
		packet.to = UInt32.max
		packet.rxTime = 1_700_000_000
		packet.decoded = data
		return packet
	}

	private func makeDeviceMetricsPacket(from nodeNum: UInt32) throws -> MeshPacket {
		try makeTelemetryPacket(from: nodeNum) {
			var device = DeviceMetrics()
			device.batteryLevel = 80
			$0.deviceMetrics = device
		}
	}

	// MARK: - Writing

	@Test("A telemetry packet stores the node number and leaves the relationship nil")
	func packetStoresNodeNum() async throws {
		let container = try makeContainer()
		let nodeNum: UInt32 = 0x7E1E_0001
		let mesh = MeshPackets(modelContainer: container)
		await mesh.telemetryPacket(
			packet: try makeTelemetryPacket(from: nodeNum) {
				var environment = EnvironmentMetrics()
				environment.temperature = 21
				$0.environmentMetrics = environment
			},
			connectedNode: Self.connectedNode
		)
		await mesh.flushDebouncedSaves()

		let context = ModelContext(container)
		let rows = try context.fetch(FetchDescriptor<TelemetryEntity>())
		#expect(rows.count == 1)
		#expect(rows.first?.nodeNum == Int64(nodeNum))
		#expect(rows.first?.nodeTelemetry == nil)
		let node = try #require(try context.fetch(FetchDescriptor<NodeInfoEntity>()).first)
		#expect(node.num == Int64(nodeNum))
		#expect(node.telemetries.isEmpty)
	}

	@Test("Device metrics carried in a node info packet store the node number")
	func nodeInfoDeviceMetricsStoreNodeNum() async throws {
		let container = try makeContainer()
		let mesh = MeshPackets(modelContainer: container)
		var info = NodeInfo()
		info.num = 0x7E1E_0002
		var device = DeviceMetrics()
		device.batteryLevel = 55
		info.deviceMetrics = device
		_ = await mesh.nodeInfoPacket(nodeInfo: info, channel: 0)
		await mesh.flushDebouncedSaves()

		let context = ModelContext(container)
		let rows = try context.fetch(FetchDescriptor<TelemetryEntity>())
		#expect(rows.count == 1)
		#expect(rows.first?.nodeNum == 0x7E1E_0002)
		#expect(rows.first?.nodeTelemetry == nil)
	}

	// MARK: - Reading

	@Test("Node accessors find new rows and, before the backfill, legacy rows")
	func accessorsBeforeBackfill() async throws {
		try await withBackfill(complete: false) {
			let container = try makeContainer()
			let context = container.mainContext
			let num: Int64 = 0x7E1E_0010
			let node = makeNode(num, in: context)
			let other = makeNode(0x7E1E_0011, in: context)
			let now = Date()
			// One new and one legacy row per type, the new row being the latest.
			for type: Int32 in 0...4 {
				addLegacyRow(node, type: type, time: now.addingTimeInterval(-60), in: context)
				addRow(num, type: type, time: now, in: context)
				addRow(other.num, type: type, time: now.addingTimeInterval(60), in: context)
			}
			try context.save()

			for type: Int32 in 0...4 {
				#expect(node.telemetryCount(ofType: type) == 2)
				#expect(node.safeTelemetries(ofType: type).count == 2)
			}
			#expect(node.latestDeviceMetrics?.nodeNum == num)
			#expect(node.latestEnvironmentMetrics?.nodeNum == num)
			#expect(node.latestPowerMetrics?.nodeNum == num)
			#expect(node.latestAirQualityMetrics?.nodeNum == num)
			#expect(node.latestLocalStats?.nodeNum == num)
			#expect(node.hasDeviceMetrics)
			#expect(node.hasEnvironmentMetrics)
			#expect(node.hasPowerMetrics)
			#expect(node.hasAirQualityMetrics)
			#expect(node.hasLocalStats)
		}
	}

	@Test("Node accessors find a node with only legacy rows before the backfill")
	func legacyOnlyBeforeBackfill() async throws {
		try await withBackfill(complete: false) {
			let container = try makeContainer()
			let context = container.mainContext
			let node = makeNode(0x7E1E_0012, in: context)
			addLegacyRow(node, type: 0, in: context)
			addLegacyRow(node, type: 1, in: context)
			try context.save()

			#expect(node.latestDeviceMetrics != nil)
			#expect(node.hasEnvironmentMetrics)
			#expect(node.telemetryCount(ofType: 1) == 1)
		}
	}

	@Test("After the backfill, lookups use the node number only")
	func accessorsAfterBackfill() async throws {
		try await withBackfill(complete: true) {
			let container = try makeContainer()
			let context = container.mainContext
			let num: Int64 = 0x7E1E_0020
			let node = makeNode(num, in: context)
			addRow(num, type: 0, in: context)
			// A legacy row the backfill never reached is no longer matched.
			addLegacyRow(node, type: 0, in: context)
			try context.save()

			#expect(node.telemetryCount(ofType: 0) == 1)
			#expect(node.latestDeviceMetrics?.nodeNum == num)
			#expect(try count(TelemetryEntity.predicate(forNode: num), in: context) == 1)
			#expect(try count(TelemetryEntity.predicate(forNodes: [num], metricsType: 0), in: context) == 1)
		}
	}

	@Test("The node list environment filter finds new and legacy rows")
	func environmentFilterFindsBoth() async throws {
		try await withBackfill(complete: false) {
			let container = try makeContainer()
			let context = container.mainContext
			let newNode = makeNode(0x7E1E_0030, in: context)
			let legacyNode = makeNode(0x7E1E_0031, in: context)
			_ = makeNode(0x7E1E_0032, in: context)
			addRow(newNode.num, type: 1, in: context)
			addLegacyRow(legacyNode, type: 1, in: context)
			try context.save()

			let rows = try context.fetch(FetchDescriptor<TelemetryEntity>(
				predicate: TelemetryEntity.predicate(forNodes: [0x7E1E_0030, 0x7E1E_0031, 0x7E1E_0032], metricsType: 1)
			))
			#expect(Set(rows.compactMap(\.ownerNodeNum)) == [0x7E1E_0030, 0x7E1E_0031])
		}
	}

	@Test("Before the backfill, a lookup for node 0 matches nothing, not the rows the backfill hasn't reached")
	func nodeZeroSkipsUnfilledRows() async throws {
		try await withBackfill(complete: false) {
			let container = try makeContainer()
			let context = container.mainContext
			let node = makeNode(0x7E1E_0040, in: context)
			addLegacyRow(node, type: 0, in: context)
			addLegacyRow(node, type: 0, in: context)
			// No node: nodeNum 0 and no relationship.
			addRow(0, type: 0, in: context)
			try context.save()

			#expect(try count(TelemetryEntity.predicate(forNode: 0), in: context) == 0)
			#expect(try count(TelemetryEntity.predicate(forNode: 0, metricsType: 0), in: context) == 0)
			#expect(try count(TelemetryEntity.predicate(forNodes: [0]), in: context) == 0)
			#expect(try count(TelemetryEntity.predicate(forNodes: [0], metricsType: 0), in: context) == 0)
			#expect(try count(TelemetryEntity.predicate(forNode: node.num), in: context) == 2)

			TelemetryEntity.deleteAll(forNodes: [0], in: context)
			try context.save()
			#expect(try count(TelemetryEntity.predicate(forNode: node.num), in: context) == 2)
		}
	}

	// MARK: - Backfill

	@Test("The backfill copies the node number in chunks and finishes")
	func backfillFillsInChunks() async throws {
		try await withBackfill(complete: false) {
			let container = try makeContainer()
			let context = container.mainContext
			let first = makeNode(0x7E1E_0040, in: context)
			let second = makeNode(0x7E1E_0041, in: context)
			for index in 0..<7 {
				addLegacyRow(index.isMultiple(of: 2) ? first : second, type: 0, in: context)
			}
			addRow(0x7E1E_0042, type: 0, in: context)
			// An orphan the .nullify rule already cut loose: nothing to fill it from.
			let orphan = TelemetryEntity()
			context.insert(orphan)
			try context.save()

			let worker = TelemetryNodeNumBackfillActor(modelContainer: container)
			let chunks = Counter()
			let finished = await TelemetryNodeNumBackfill.run(using: worker, chunkSize: 3) {
				chunks.value += 1
				return true
			}
			#expect(finished)
			// 7 rows in chunks of 3: three filling passes, then one that finds nothing.
			#expect(chunks.value == 4)

			let check = ModelContext(container)
			let firstNum: Int64 = 0x7E1E_0040
			let secondNum: Int64 = 0x7E1E_0041
			#expect(try count(#Predicate { $0.nodeNum == firstNum }, in: check) == 4)
			#expect(try count(#Predicate { $0.nodeNum == secondNum }, in: check) == 3)
			#expect(try count(#Predicate { $0.nodeNum == 0 }, in: check) == 1)
		}
	}

	@Test("The backfill stops without finishing when told to")
	func backfillStops() async throws {
		let container = try makeContainer()
		let context = container.mainContext
		let node = makeNode(0x7E1E_0050, in: context)
		addLegacyRow(node, type: 0, in: context)
		try context.save()

		let worker = TelemetryNodeNumBackfillActor(modelContainer: container)
		let finished = await TelemetryNodeNumBackfill.run(using: worker, chunkSize: 10) { false }
		#expect(!finished)
		#expect(try count(#Predicate { $0.nodeNum == 0 }, in: ModelContext(container)) == 1)
	}

	@Test("The backfill flag switches lookups from both to the node number only")
	func flagSwitchesPredicate() async throws {
		let container = try makeContainer()
		let context = container.mainContext
		let num: Int64 = 0x7E1E_0060
		let node = makeNode(num, in: context)
		addLegacyRow(node, type: 0, in: context)
		try context.save()

		let before = try await withBackfill(complete: false) {
			try count(TelemetryEntity.predicate(forNode: num), in: context)
		}
		let after = try await withBackfill(complete: true) {
			try count(TelemetryEntity.predicate(forNode: num), in: context)
		}
		#expect(before == 1)
		#expect(after == 0)
	}

	// MARK: - Pruning

	@Test("Pruning counts a node's history by node number")
	func pruneCountsByNodeNum() async throws {
		try await withBackfill(complete: true) {
			let container = try makeContainer()
			let nodeNum: UInt32 = 0x7E1E_0070
			let num = Int64(nodeNum)
			let context = ModelContext(container)
			_ = makeNode(num, in: context)
			let old = Date(timeIntervalSince1970: 1_600_000_000)
			for index in 0..<(MeshPackets.maxTelemetryPerType + 50) {
				addRow(num, type: 0, time: old.addingTimeInterval(TimeInterval(index)), in: context)
			}
			try context.save()

			// The prune runs once every 128 inserts per node and type.
			let mesh = MeshPackets(modelContainer: container)
			for _ in 0..<128 {
				await mesh.telemetryPacket(packet: try makeDeviceMetricsPacket(from: nodeNum), connectedNode: Self.connectedNode)
			}
			await mesh.flushDebouncedSaves()

			let check = ModelContext(container)
			#expect(try count(TelemetryEntity.predicate(forNode: num, metricsType: 0), in: check) == MeshPackets.maxTelemetryPerType)
			// The oldest rows went first.
			let earliest = old
			#expect(try count(#Predicate { $0.time == earliest }, in: check) == 0)
		}
	}

	// MARK: - Deleting nodes

	@Test("Deleting nodes deletes their telemetry, new rows and legacy rows")
	func deleteAllRemovesTelemetry() async throws {
		try await withBackfill(complete: false) {
			let container = try makeContainer()
			let context = container.mainContext
			let doomed = makeNode(0x7E1E_0080, in: context)
			let kept = makeNode(0x7E1E_0081, in: context)
			addRow(doomed.num, type: 0, in: context)
			addRow(doomed.num, type: 1, in: context)
			addLegacyRow(doomed, type: 4, in: context)
			addRow(kept.num, type: 0, in: context)
			try context.save()

			TelemetryEntity.deleteAll(forNodes: [doomed.num], in: context)
			context.delete(doomed)
			try context.save()

			let check = ModelContext(container)
			let rows = try check.fetch(FetchDescriptor<TelemetryEntity>())
			#expect(rows.count == 1)
			#expect(rows.first?.nodeNum == 0x7E1E_0081)
		}
	}

	@Test("Clearing stale nodes deletes their telemetry")
	func clearStaleNodesDeletesTelemetry() async throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		let stale = makeNode(0x7E1E_0090, in: context)
		stale.lastHeard = Date(timeIntervalSinceNow: -30 * 86_400)
		let fresh = makeNode(0x7E1E_0091, in: context)
		fresh.lastHeard = Date()
		addRow(stale.num, type: 0, in: context)
		addRow(fresh.num, type: 0, in: context)
		try context.save()

		let mesh = MeshPackets(modelContainer: container)
		#expect(await mesh.clearStaleNodes(nodeExpireDays: 7))

		let rows = try ModelContext(container).fetch(FetchDescriptor<TelemetryEntity>())
		#expect(rows.map(\.nodeNum) == [0x7E1E_0091])
	}

	@Test("Evicting nodes over the cap deletes their telemetry")
	func evictionDeletesTelemetry() async throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		let oldest = makeNode(0x7E1E_00A0, in: context)
		oldest.lastHeard = Date(timeIntervalSinceNow: -3_600)
		let newest = makeNode(0x7E1E_00A1, in: context)
		newest.lastHeard = Date()
		addRow(oldest.num, type: 0, in: context)
		addRow(newest.num, type: 0, in: context)
		try context.save()

		let mesh = MeshPackets(modelContainer: container)
		#expect(await mesh.evictNodesIfOverCap(1) == 1)
		await mesh.flushDebouncedSaves()
		await mesh.savePendingChanges()

		let rows = try ModelContext(container).fetch(FetchDescriptor<TelemetryEntity>())
		#expect(rows.map(\.nodeNum) == [0x7E1E_00A1])
	}

	@Test("Renumbering a node moves its telemetry")
	func renumberMovesTelemetry() throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		let oldNum: Int64 = 0x7E1E_00B0
		let newNum: Int64 = 0x7E1E_00B1
		let user = UserEntity()
		user.num = oldNum
		context.insert(user)
		let node = makeNode(oldNum, in: context)
		node.user = user
		addRow(oldNum, type: 0, in: context)
		try context.save()

		#expect(NodeRenumber.apply(from: oldNum, to: newNum, in: context))
		let rows = try ModelContext(container).fetch(FetchDescriptor<TelemetryEntity>())
		#expect(rows.map(\.nodeNum) == [newNum])
	}

	@Test("Renumbering keeps older telemetry linked to the node already on the new number")
	func renumberKeepsDuplicateLegacyTelemetry() throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		let oldNum: Int64 = 0x7E1E_00C0
		let newNum: Int64 = 0x7E1E_00C1
		let user = UserEntity()
		user.num = oldNum
		context.insert(user)
		let node = makeNode(oldNum, in: context)
		node.user = user
		let duplicate = makeNode(newNum, in: context)
		addLegacyRow(duplicate, type: 0, in: context)
		addRow(newNum, type: 0, in: context)
		try context.save()

		#expect(NodeRenumber.apply(from: oldNum, to: newNum, in: context))
		let rows = try ModelContext(container).fetch(FetchDescriptor<TelemetryEntity>())
		#expect(rows.map(\.nodeNum) == [newNum, newNum])
	}

	// MARK: - Backup restore

	@Test("Restoring a backup keeps the node number and fills it for older backups")
	func backupRestoreCarriesNodeNum() throws {
		let backup = ModelContext(try makeContainer())
		let live = ModelContext(try makeContainer())
		let node = makeNode(99, in: backup)
		addRow(99, type: 0, in: backup)
		// Written by an older app: relationship only.
		addLegacyRow(node, type: 1, in: backup)
		// Belongs to a node the backup does not have.
		addRow(1234, type: 0, in: backup)
		try backup.save()

		let nodes = try NodeBackupManager.importNodes(from: backup, into: live)
		try NodeBackupManager.importTelemetry(from: backup, into: live, nodesByNum: nodes)
		try live.save()

		let rows = try live.fetch(FetchDescriptor<TelemetryEntity>(sortBy: [SortDescriptor(\.metricsType)]))
		#expect(rows.map(\.metricsType) == [0, 1])
		#expect(rows.allSatisfy { $0.nodeNum == 99 && $0.nodeTelemetry == nil })
	}
}

/// Mutable box for counting calls from the backfill's main-actor callback.
@MainActor
private final class Counter {
	var value = 0
}
