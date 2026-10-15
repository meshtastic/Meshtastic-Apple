//
//  NeighborLinkTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/15/26.
//

import Foundation
import SwiftData
import MeshtasticProtobufs
import Testing
@testable import Meshtastic

/// Neighbor Info reports are saved as one `NeighborLinkEntity` per (reporter, neighbor).
@Suite("Neighbor links")
@MainActor
struct NeighborLinkTests {

	nonisolated private static let reporter: UInt32 = 0x7E1E_1000
	nonisolated private static let now = Date(timeIntervalSince1970: 1_800_000_000)

	private func makeContainer() throws -> ModelContainer {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config = ModelConfiguration(
			"NeighborLinkTests-\(UUID().uuidString)",
			schema: schema,
			isStoredInMemoryOnly: true,
			allowsSave: true
		)
		return try ModelContainer(for: schema, configurations: config)
	}

	private func makeReport(
		from reporter: UInt32 = NeighborLinkTests.reporter,
		nodeID: UInt32? = nil,
		neighbors: [(UInt32, Float)],
		interval: UInt32 = 21_600,
		viaMqtt: Bool = false,
		rxTime: UInt32 = 0
	) -> (NeighborInfo, MeshPacket) {
		var info = NeighborInfo()
		info.nodeID = nodeID ?? reporter
		// Relays overwrite this; it must not be used as the reporter.
		info.lastSentByID = 0x7E1E_FFFF
		info.nodeBroadcastIntervalSecs = interval
		info.neighbors = neighbors.map { num, snr in
			var neighbor = Neighbor()
			neighbor.nodeID = num
			neighbor.snr = snr
			return neighbor
		}
		var packet = MeshPacket()
		packet.from = reporter
		packet.to = UInt32.max
		packet.viaMqtt = viaMqtt
		packet.rxTime = rxTime
		return (info, packet)
	}

	private func ingest(_ report: (NeighborInfo, MeshPacket), into mesh: MeshPackets, now: Date = NeighborLinkTests.now) async {
		await mesh.neighborInfoPacket(report.0, packet: report.1, now: now)
	}

	private func links(in container: ModelContainer) throws -> [NeighborLinkEntity] {
		try ModelContext(container).fetch(FetchDescriptor<NeighborLinkEntity>())
			.sorted { ($0.reporterNum, $0.neighborNum) < ($1.reporterNum, $1.neighborNum) }
	}

	@discardableResult
	private func addLink(
		_ reporter: Int64,
		_ neighbor: Int64,
		receivedAt: Date = NeighborLinkTests.now,
		interval: Int32 = 21_600,
		in context: ModelContext
	) -> NeighborLinkEntity {
		let row = NeighborLinkEntity()
		row.key = NeighborLinkEntity.key(reporter: reporter, neighbor: neighbor)
		row.reporterNum = reporter
		row.neighborNum = neighbor
		row.snr = 5
		row.receivedAt = receivedAt
		row.reporterIntervalSecs = interval
		context.insert(row)
		return row
	}

	private func makeNode(_ num: Int64, lastHeard: Date?, in context: ModelContext) {
		let node = NodeInfoEntity()
		node.num = num
		node.id = num
		node.lastHeard = lastHeard
		context.insert(node)
	}

	// MARK: - Ingest

	@Test("A report saves one row per neighbor with the reporter from the packet")
	func reportSavesRows() async throws {
		let container = try makeContainer()
		let mesh = MeshPackets(modelContainer: container)
		await ingest(makeReport(neighbors: [(0x7E1E_0001, 7.0), (0x7E1E_0002, -3.25)], viaMqtt: true), into: mesh)

		let rows = try links(in: container)
		#expect(rows.count == 2)
		#expect(rows.allSatisfy { $0.reporterNum == Int64(Self.reporter) })
		#expect(rows.map(\.neighborNum) == [0x7E1E_0001, 0x7E1E_0002])
		#expect(rows.map(\.snr) == [7.0, -3.25])
		#expect(rows.map(\.key) == ["\(Self.reporter):\(0x7E1E_0001)", "\(Self.reporter):\(0x7E1E_0002)"])
		#expect(rows.allSatisfy { $0.viaMqtt && $0.reporterIntervalSecs == 21_600 && $0.receivedAt == Self.now })
	}

	@Test("A new report replaces the reporter's set and leaves other reporters alone")
	func reportReplacesSet() async throws {
		let container = try makeContainer()
		let mesh = MeshPackets(modelContainer: container)
		await ingest(makeReport(neighbors: [(0x7E1E_0001, 7), (0x7E1E_0002, 2)]), into: mesh)
		await ingest(makeReport(from: 0x7E1E_2000, neighbors: [(0x7E1E_0001, 1)]), into: mesh)

		let later = Self.now.addingTimeInterval(3_600)
		await ingest(makeReport(neighbors: [(0x7E1E_0002, -1), (0x7E1E_0003, 4)], interval: 14_400), into: mesh, now: later)

		let rows = try links(in: container)
		let mine = rows.filter { $0.reporterNum == Int64(Self.reporter) }
		#expect(mine.map(\.neighborNum) == [0x7E1E_0002, 0x7E1E_0003])
		#expect(mine.map(\.snr) == [-1, 4])
		#expect(mine.allSatisfy { $0.receivedAt == later && $0.reporterIntervalSecs == 14_400 })
		#expect(rows.filter { $0.reporterNum == 0x7E1E_2000 }.map(\.neighborNum) == [0x7E1E_0001])
	}

	@Test("The request placeholder and the reporter itself are skipped")
	func skipsPlaceholder() async throws {
		let container = try makeContainer()
		let mesh = MeshPackets(modelContainer: container)
		await ingest(makeReport(neighbors: [(0, 0), (Self.reporter, 9), (0x7E1E_0001, 3)]), into: mesh)
		#expect(try links(in: container).map(\.neighborNum) == [0x7E1E_0001])
	}

	@Test("A request with only the placeholder does not clear the reporter's set")
	func requestKeepsSet() async throws {
		let container = try makeContainer()
		let mesh = MeshPackets(modelContainer: container)
		await ingest(makeReport(neighbors: [(0x7E1E_0001, 3)]), into: mesh)
		await ingest(makeReport(neighbors: [(0, 0)]), into: mesh, now: Self.now.addingTimeInterval(60))
		#expect(try links(in: container).map(\.neighborNum) == [0x7E1E_0001])
	}

	@Test("A report whose node_id doesn't match the sender is ignored")
	func mismatchedReporterIgnored() async throws {
		let container = try makeContainer()
		let mesh = MeshPackets(modelContainer: container)
		await ingest(makeReport(nodeID: 0x7E1E_3000, neighbors: [(0x7E1E_0001, 3)]), into: mesh)
		#expect(try links(in: container).isEmpty)
	}

	@Test("An older replayed report does not replace a newer one")
	func olderReportIgnored() async throws {
		let container = try makeContainer()
		let mesh = MeshPackets(modelContainer: container)
		await ingest(makeReport(neighbors: [(0x7E1E_0001, 3)]), into: mesh)
		let replayTime = UInt32(Self.now.addingTimeInterval(-3_600).timeIntervalSince1970)
		await ingest(makeReport(neighbors: [(0x7E1E_0002, 3)], rxTime: replayTime), into: mesh, now: Self.now.addingTimeInterval(60))
		#expect(try links(in: container).map(\.neighborNum) == [0x7E1E_0001])
	}

	@Test("The radio's receive time is used only when it is believable")
	func reportTime() {
		var packet = MeshPacket()
		let day: Int32 = 86_400
		#expect(MeshPackets.neighborReportTime(packet: packet, interval: 21_600, now: Self.now) == Self.now)
		packet.rxTime = UInt32(Self.now.timeIntervalSince1970) - 600
		#expect(MeshPackets.neighborReportTime(packet: packet, interval: 21_600, now: Self.now) == Self.now.addingTimeInterval(-600))
		packet.rxTime = UInt32(Self.now.timeIntervalSince1970) + 600
		#expect(MeshPackets.neighborReportTime(packet: packet, interval: 21_600, now: Self.now) == Self.now)
		// Clock never set.
		packet.rxTime = 1_000
		#expect(MeshPackets.neighborReportTime(packet: packet, interval: 21_600, now: Self.now) == Self.now)
		// Older than pruning would keep: dropped, not saved as new.
		packet.rxTime = UInt32(Self.now.timeIntervalSince1970) - UInt32(2 * day)
		#expect(MeshPackets.neighborReportTime(packet: packet, interval: 21_600, now: Self.now) == nil)
		// A 1 day interval keeps rows for 3 days, so a 2 day old report still counts.
		#expect(MeshPackets.neighborReportTime(packet: packet, interval: day, now: Self.now) == Self.now.addingTimeInterval(-2 * 86_400))
	}

	@Test("A replayed report older than a day is not saved")
	func staleReplayDropped() async throws {
		let container = try makeContainer()
		let mesh = MeshPackets(modelContainer: container)
		let replayTime = UInt32(Self.now.addingTimeInterval(-2 * 86_400).timeIntervalSince1970)
		await ingest(makeReport(neighbors: [(0x7E1E_0001, 3)], rxTime: replayTime), into: mesh)
		#expect(try links(in: container).isEmpty)
	}

	// MARK: - Pruning

	@Test("Rows older than a day, or three intervals if longer, are pruned")
	func pruneByAge() async throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		let hour: TimeInterval = 3_600
		// 6 h interval: kept for 24 h.
		addLink(1, 10, receivedAt: Self.now.addingTimeInterval(-23 * hour), interval: 21_600, in: context)
		addLink(1, 11, receivedAt: Self.now.addingTimeInterval(-25 * hour), interval: 21_600, in: context)
		// 12 h interval: kept for 36 h.
		addLink(2, 10, receivedAt: Self.now.addingTimeInterval(-30 * hour), interval: 43_200, in: context)
		addLink(2, 11, receivedAt: Self.now.addingTimeInterval(-37 * hour), interval: 43_200, in: context)
		// No interval: the 24 h floor applies.
		addLink(3, 10, receivedAt: Self.now.addingTimeInterval(-25 * hour), interval: 0, in: context)
		try context.save()

		let mesh = MeshPackets(modelContainer: container)
		#expect(await mesh.pruneNeighborLinks(now: Self.now) == 3)
		await mesh.savePendingChanges()

		#expect(try links(in: container).map(\.key) == ["1:10", "2:10"])
	}

	@Test("Rows over the cap go oldest first")
	func pruneByCap() async throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		for index in 0..<6 {
			addLink(1, Int64(10 + index), receivedAt: Self.now.addingTimeInterval(TimeInterval(-60 * index)), in: context)
		}
		// Too old: goes by age, and must not count against the cap.
		addLink(2, 10, receivedAt: Self.now.addingTimeInterval(-48 * 3_600), in: context)
		try context.save()

		let mesh = MeshPackets(modelContainer: container)
		#expect(await mesh.pruneNeighborLinks(now: Self.now, cap: 4) == 3)
		await mesh.savePendingChanges()

		#expect(try links(in: container).map(\.neighborNum) == [10, 11, 12, 13])
	}

	// MARK: - Clean-up

	@Test("Deleting a node deletes the rows it appears in on either side")
	func deleteForNodes() throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		addLink(1, 2, in: context)
		addLink(2, 3, in: context)
		addLink(3, 4, in: context)
		try context.save()

		NeighborLinkEntity.deleteAll(forNodes: [2], in: context)
		try context.save()

		#expect(try links(in: container).map(\.key) == ["3:4"])
	}

	@Test("Clearing stale nodes deletes their neighbor links")
	func clearStaleNodesDeletesLinks() async throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		makeNode(1, lastHeard: Date(timeIntervalSinceNow: -30 * 86_400), in: context)
		makeNode(2, lastHeard: Date(), in: context)
		addLink(1, 2, in: context)
		addLink(2, 1, in: context)
		addLink(2, 3, in: context)
		try context.save()

		let mesh = MeshPackets(modelContainer: container)
		#expect(await mesh.clearStaleNodes(nodeExpireDays: 7))

		#expect(try links(in: container).map(\.key) == ["2:3"])
	}

	@Test("Evicting nodes over the cap deletes their neighbor links")
	func evictionDeletesLinks() async throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		makeNode(1, lastHeard: Date(timeIntervalSinceNow: -3_600), in: context)
		makeNode(2, lastHeard: Date(), in: context)
		addLink(1, 2, in: context)
		addLink(2, 3, in: context)
		try context.save()

		let mesh = MeshPackets(modelContainer: container)
		#expect(await mesh.evictNodesIfOverCap(1) == 1)
		await mesh.savePendingChanges()

		#expect(try links(in: container).map(\.key) == ["2:3"])
	}

	@Test("Renumbering moves both columns and the key, replacing rows under the new number")
	func renumberMovesLinks() throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		let old: Int64 = 0x0BAD_0001
		let new: Int64 = 0x0BAD_0002
		addLink(old, 5, in: context)
		addLink(6, old, in: context)
		// Saved under the new number before the connect: these go.
		addLink(new, 5, in: context)
		addLink(6, new, in: context)
		addLink(7, 8, in: context)
		try context.save()

		#expect(NodeRenumber.apply(from: old, to: new, in: context))

		let rows = try links(in: container)
		#expect(rows.map(\.key).sorted() == ["\(new):5", "6:\(new)", "7:8"].sorted())
		#expect(rows.allSatisfy { $0.key == NeighborLinkEntity.key(reporter: $0.reporterNum, neighbor: $0.neighborNum) })
	}

	@Test("Clearing the database deletes all neighbor links")
	func clearDatabaseDeletesLinks() async throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		addLink(1, 2, in: context)
		addLink(3, 4, in: context)
		try context.save()

		let mesh = MeshPackets(modelContainer: container)
		#expect(await mesh.clearDatabase(includeRoutes: false))

		#expect(try links(in: container).isEmpty)
	}
}
