//
//  TraceRouteParsingTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/13/26.
//
//  Feeds trace route responses through `handleTraceRouteApp` against an in-memory store.
//

import Foundation
import SwiftData
import Testing
@testable import Meshtastic
import MeshtasticProtobufs

@Suite("Trace route parsing", .serialized)
@MainActor
struct TraceRouteParsingTests {

	private let deviceNum: Int64 = 0x0A1B_2C3D
	private let targetNum: Int64 = 0x1111_2222
	private let knownHopNum: UInt32 = 0x3333_4444
	private let newHopNum: UInt32 = 0x5555_6666
	private let unknownRepeater: UInt32 = 0xFFFF_FFFF

	// MARK: - Helpers

	private func makeManager() throws -> (AccessoryManager, ModelContext) {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config = ModelConfiguration(
			"TraceRouteParsingTests-\(UUID().uuidString)",
			schema: schema,
			isStoredInMemoryOnly: true,
			allowsSave: true
		)
		let container = try ModelContainer(for: schema, configurations: config)
		let context = ModelContext(container)
		context.autosaveEnabled = false

		let manager = AccessoryManager(transports: [])
		let device = Device(
			id: UUID(),
			name: "Test Radio",
			transportType: .ble,
			identifier: "test-traceroute",
			connectionState: .connected,
			num: deviceNum
		)
		manager.activeConnection = (device: device, connection: MockChannelSetConnection())
		manager.context = context

		for num in [deviceNum, targetNum, Int64(knownHopNum)] {
			let node = NodeInfoEntity()
			node.num = num
			let user = UserEntity()
			user.num = num
			user.longName = "Node \(num.toHex())"
			user.shortName = String(num.toHex().suffix(4))
			node.user = user
			context.insert(user)
			context.insert(node)
		}
		try context.save()
		return (manager, context)
	}

	private func makeResponse(
		requestID: UInt32,
		from: Int64,
		to: Int64,
		route: [UInt32],
		snrTowards: [Int32],
		routeBack: [UInt32] = [],
		snrBack: [Int32] = [],
		hopStart: UInt32 = 3
	) throws -> MeshPacket {
		var discovery = RouteDiscovery()
		discovery.route = route
		discovery.snrTowards = snrTowards
		discovery.routeBack = routeBack
		discovery.snrBack = snrBack

		var data = DataMessage()
		data.portnum = .tracerouteApp
		data.requestID = requestID
		data.payload = try discovery.serializedData()

		var packet = MeshPacket()
		packet.id = UInt32.random(in: 1..<UInt32.max)
		packet.from = UInt32(from)
		packet.to = UInt32(to)
		packet.hopStart = hopStart
		packet.decoded = data
		return packet
	}

	private func insertSentRequest(id: UInt32, context: ModelContext) throws -> TraceRouteEntity {
		let route = TraceRouteEntity()
		route.id = Int64(id)
		route.sent = true
		route.sentAt = Date().addingTimeInterval(-8)
		route.time = route.sentAt
		route.node = getNodeInfo(id: targetNum, context: context)
		context.insert(route)
		try context.save()
		return route
	}

	private func routes(_ context: ModelContext) throws -> [TraceRouteEntity] {
		try context.fetch(FetchDescriptor<TraceRouteEntity>())
	}

	private func forwardHops(_ route: TraceRouteEntity) -> [TraceRouteHopEntity] {
		route.hops.filter { !$0.back }.sorted { $0.index < $1.index }
	}

	private func backHops(_ route: TraceRouteEntity) -> [TraceRouteHopEntity] {
		route.hops.filter { $0.back }.sorted { $0.index < $1.index }
	}

	// MARK: - Tests

	@Test("SNR values are divided by four and -128 means unknown")
	func snrScaling() throws {
		let (manager, context) = try makeManager()
		_ = try insertSentRequest(id: 100, context: context)
		let packet = try makeResponse(
			requestID: 100, from: targetNum, to: deviceNum,
			route: [knownHopNum], snrTowards: [28, -128],
			routeBack: [knownHopNum], snrBack: [-10, 20]
		)
		manager.handleTraceRouteApp(packet)

		let route = try #require(try routes(context).first)
		let forward = forwardHops(route)
		#expect(forward.map(\.snr) == [5, 7, -32])
		let back = backHops(route)
		#expect(back.map(\.snr) == [-2.5])
	}

	@Test("Hops not yet in the node DB keep their node number")
	func unknownHopKeepsNum() throws {
		let (manager, context) = try makeManager()
		_ = try insertSentRequest(id: 101, context: context)
		#expect(getNodeInfo(id: Int64(newHopNum), context: context) == nil)

		let packet = try makeResponse(
			requestID: 101, from: targetNum, to: deviceNum,
			route: [knownHopNum, newHopNum, unknownRepeater], snrTowards: [10, 20, 30, 40],
			routeBack: [newHopNum], snrBack: [12, 16]
		)
		manager.handleTraceRouteApp(packet)

		let route = try #require(try routes(context).first)
		#expect(forwardHops(route).map(\.num) == [deviceNum, Int64(knownHopNum), Int64(newHopNum), Int64(unknownRepeater), targetNum])
		#expect(backHops(route).map(\.num) == [Int64(newHopNum)])
		#expect(getNodeInfo(id: Int64(newHopNum), context: context) == nil)
		#expect(getNodeInfo(id: Int64(unknownRepeater), context: context) == nil)
		#expect(route.routeText?.contains(newHopNum.toHex()) == true, "a hop the app has never heard from is named by its ID")
		#expect(route.routeBackText?.contains(newHopNum.toHex()) == true)
	}

	@Test("A response without a return leg leaves hopsBack at -1")
	func missingReturnLeg() throws {
		let (manager, context) = try makeManager()
		_ = try insertSentRequest(id: 102, context: context)
		let packet = try makeResponse(
			requestID: 102, from: targetNum, to: deviceNum,
			route: [knownHopNum], snrTowards: [10, 20],
			hopStart: 0
		)
		manager.handleTraceRouteApp(packet)

		let route = try #require(try routes(context).first)
		#expect(route.hopsTowards == 1)
		#expect(route.hopsBack == -1)
		#expect(backHops(route).isEmpty)
		#expect(route.routeBackText == nil)
	}

	@Test("A response to our own request stays initiated")
	func initiatedRoute() throws {
		let (manager, context) = try makeManager()
		_ = try insertSentRequest(id: 103, context: context)
		let packet = try makeResponse(
			requestID: 103, from: targetNum, to: deviceNum,
			route: [], snrTowards: [24], routeBack: [], snrBack: [20]
		)
		manager.handleTraceRouteApp(packet)

		let route = try #require(try routes(context).first)
		#expect(route.sent)
		#expect(route.response)
		#expect(!route.observed)
		#expect(route.fromNum == deviceNum)
		#expect(route.toNum == targetNum)
		#expect(route.node?.num == targetNum)
		#expect(route.hopsTowards == 0)
		#expect(route.hopsBack == 0)
		let roundTrip = try #require(route.roundTrip)
		#expect(roundTrip >= 8 && roundTrip < 60)
	}

	@Test("A response seen on the mesh is stored as observed")
	func observedRoute() throws {
		let (manager, context) = try makeManager()
		let requester = Int64(knownHopNum)
		let packet = try makeResponse(
			requestID: 104, from: targetNum, to: requester,
			route: [newHopNum], snrTowards: [8, 12], routeBack: [newHopNum], snrBack: [4, 16]
		)
		manager.handleTraceRouteApp(packet)

		let route = try #require(try routes(context).first)
		#expect(!route.sent)
		#expect(route.observed)
		#expect(route.response)
		#expect(route.fromNum == requester)
		#expect(route.toNum == targetNum)
		#expect(route.node == nil)
		#expect(route.sentAt == nil)
		#expect(route.roundTrip == nil)
	}

	@Test("Seeing the same response again updates the record in place")
	func rebroadcastIsIdempotent() throws {
		let (manager, context) = try makeManager()
		let packet = try makeResponse(
			requestID: 105, from: targetNum, to: Int64(knownHopNum),
			route: [newHopNum], snrTowards: [8, 12], routeBack: [newHopNum], snrBack: [4, 16]
		)
		manager.handleTraceRouteApp(packet)
		manager.handleTraceRouteApp(packet)

		let all = try routes(context)
		#expect(all.count == 1)
		let route = try #require(all.first)
		#expect(route.hops.count == 4)
		#expect(try context.fetch(FetchDescriptor<TraceRouteHopEntity>()).count == 4)
	}

	@Test("A rate-limit notice keeps the request ours and marks it rate limited")
	func rateLimitKeepsSent() throws {
		let (manager, context) = try makeManager()
		let route = try insertSentRequest(id: 106, context: context)

		var notice = ClientNotification()
		notice.replyID = 106
		notice.level = .warning
		notice.message = "TraceRoute can only be sent once every 30 seconds"
		manager.handleClientNotification(notice)

		#expect(route.sent)
		#expect(route.rateLimited)
		#expect(!route.observed)
		#expect(route.state() == .rateLimited)
	}

	@Test("A request with no request id is ignored")
	func requestIsIgnored() throws {
		let (manager, context) = try makeManager()
		let packet = try makeResponse(
			requestID: 0, from: targetNum, to: deviceNum,
			route: [], snrTowards: []
		)
		manager.handleTraceRouteApp(packet)
		#expect(try routes(context).isEmpty)
	}
}
