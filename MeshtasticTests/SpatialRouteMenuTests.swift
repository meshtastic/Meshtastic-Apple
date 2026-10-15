//
//  SpatialRouteMenuTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/15/26.
//
import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import Meshtastic

/// The spatial map's trace route menu: what each stored route becomes, its order, and its text.
@Suite("Spatial map trace route menu")
@MainActor
struct SpatialRouteMenuTests {
	private static let origin: Int64 = 0x5EA7_0001
	private static let relay: Int64 = 0x5EA7_0002
	private static let target: Int64 = 0x5EA7_0003

	private func route(id: Int64, time: Date?, towards: Int = 1, back: Int? = 1) -> SpatialRouteSnapshot {
		let point = SpatialRouteSnapshot.Point(num: Self.origin, coordinate: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.33), altitude: 0, snr: 0)
		return SpatialRouteSnapshot(
			id: id, fromNum: Self.origin, toNum: Self.target, originName: "Base", targetName: "Ridge", time: time,
			hopsTowards: towards, hopsBack: back, forward: [point, point], back: []
		)
	}

	@discardableResult
	private func insertNode(_ num: Int64, name: String, in context: ModelContext) -> NodeInfoEntity {
		let user = UserEntity()
		user.num = num
		user.userId = num.toHex()
		user.longName = name
		context.insert(user)
		let node = NodeInfoEntity()
		node.num = num
		node.id = num
		node.user = user
		context.insert(node)
		return node
	}

	/// Base → Relay → Ridge and back through the relay, with every node's position snapshotted.
	private func insertRoute(id: Int64, time: Date, hopsBack: Int32, target: NodeInfoEntity, in context: ModelContext) -> TraceRouteEntity {
		let route = TraceRouteEntity()
		route.id = id
		route.fromNum = Self.origin
		route.toNum = Self.target
		route.time = time
		route.sent = true
		route.response = true
		route.hasPositions = true
		route.hopsTowards = 1
		route.hopsBack = hopsBack
		route.node = target
		context.insert(route)
		for (index, num) in [Self.origin, Self.relay, Self.target].enumerated() {
			let hop = TraceRouteHopEntity()
			hop.index = Int32(index)
			hop.num = num
			hop.snr = 5
			hop.traceRoute = route
			context.insert(hop)
			let position = TraceRouteNodePositionEntity()
			position.num = num
			position.latitudeI = Int32((47.6 + Double(index) * 0.01) * 1e7)
			position.longitudeI = Int32(-122.33 * 1e7)
			position.traceRoute = route
			context.insert(position)
		}
		if hopsBack > 0 {
			let hop = TraceRouteHopEntity()
			hop.back = true
			hop.num = Self.relay
			hop.snr = 3
			hop.traceRoute = route
			context.insert(hop)
		}
		return route
	}

	private func cleanUp(_ context: ModelContext) {
		try? context.delete(model: TraceRouteEntity.self, where: #Predicate { $0.fromNum == 0x5EA7_0001 })
		try? context.delete(model: NodeInfoEntity.self, where: #Predicate { $0.num >= 0x5EA7_0001 && $0.num <= 0x5EA7_0003 })
		try? context.delete(model: UserEntity.self, where: #Predicate { $0.num >= 0x5EA7_0001 && $0.num <= 0x5EA7_0003 })
		try? context.save()
	}

	@Test func snapshotCarriesNamesAndHopCounts() throws {
		let context = ModelContext(sharedModelContainer)
		defer { cleanUp(context) }
		let target = insertNode(Self.target, name: "Ridge", in: context)
		let withReturn = insertRoute(id: 0x5EA7_1001, time: .now, hopsBack: 1, target: target, in: context)
		let noReturn = insertRoute(id: 0x5EA7_1002, time: .now, hopsBack: -1, target: target, in: context)
		try context.save()

		let snapshot = try #require(SpatialRouteSource.snapshot(withReturn, originName: "Base"))
		#expect(snapshot.originName == "Base")
		#expect(snapshot.targetName == "Ridge")
		#expect(snapshot.hopsTowards == 1)
		#expect(snapshot.hopsBack == 1)
		#expect(snapshot.forward.map(\.num) == [Self.origin, Self.relay, Self.target])
		#expect(snapshot.back.map(\.num) == [Self.target, Self.relay, Self.origin])

		let oneWay = try #require(SpatialRouteSource.snapshot(noReturn, originName: nil))
		#expect(oneWay.hopsBack == nil, "a negative stored count means no return path")
		#expect(oneWay.originName == Self.origin.toHex(), "an unknown originator falls back to its hex id")
	}

	@Test func routesLookUpTheOriginatorsName() throws {
		let context = ModelContext(sharedModelContainer)
		defer { cleanUp(context) }
		insertNode(Self.origin, name: "Base", in: context)
		// In the future so other tests' routes in the shared store can't push it past the limit.
		let target = insertNode(Self.target, name: "Ridge", in: context)
		_ = insertRoute(id: 0x5EA7_2001, time: Date.now.addingTimeInterval(86_400 * 365), hopsBack: 1, target: target, in: context)
		try context.save()

		let snapshot = try #require(SpatialRouteSource.routes(context: context).first { $0.id == 0x5EA7_2001 })
		#expect(snapshot.originName == "Base")
		#expect(SpatialRouteMenuEntry(route: snapshot).title == "Base → Ridge")
	}

	@Test func newestComesFirst() {
		let base = Date(timeIntervalSince1970: 1_000_000)
		let routes = [
			route(id: 1, time: base),
			route(id: 2, time: nil),
			route(id: 3, time: base.addingTimeInterval(600)),
			route(id: 4, time: base.addingTimeInterval(60)),
			route(id: 5, time: base.addingTimeInterval(600))
		]
		#expect(SpatialRouteSource.newestFirst(routes).map(\.id) == [5, 3, 4, 1, 2], "ties go to the newer id, no time goes last")
	}

	@Test func menuEntryText() {
		let now = Date(timeIntervalSince1970: 1_000_000)
		let fiveMinutesAgo = now.addingTimeInterval(-300)
		let direct = SpatialRouteMenuEntry(route: route(id: 1, time: fiveMinutesAgo, towards: 0, back: 0), now: now)
		#expect(direct.title == "Base → Ridge")
		#expect(direct.subtitle == "Direct · 5 minutes ago")
		#expect(SpatialRouteMenuEntry(route: route(id: 2, time: fiveMinutesAgo, towards: 3, back: 3), now: now).subtitle == "3 Hops · 5 minutes ago")
		#expect(SpatialRouteMenuEntry(route: route(id: 3, time: fiveMinutesAgo, towards: 3, back: 2), now: now).subtitle == "3 Hops out · 2 Hops back · 5 minutes ago")
		#expect(SpatialRouteMenuEntry(route: route(id: 4, time: fiveMinutesAgo, towards: 3, back: nil), now: now).subtitle == "3 Hops, no return · 5 minutes ago")
		#expect(SpatialRouteMenuEntry(route: route(id: 5, time: now.addingTimeInterval(-86_400), towards: 1, back: 1), now: now).subtitle == "1 Hop · yesterday")
		#expect(SpatialRouteMenuEntry(route: route(id: 6, time: now.addingTimeInterval(30), towards: 1, back: 1), now: now).subtitle == "1 Hop · now", "a time slightly ahead reads as now")
		#expect(SpatialRouteMenuEntry(route: route(id: 7, time: nil, towards: 2, back: 2), now: now).subtitle == "2 Hops")
	}
}
