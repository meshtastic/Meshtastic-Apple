//
//  WatchNodeSnapshotTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 8/23/26.
//
//  Pins MeshPackets.watchNodeSnapshot — the Watch update's data source. It runs on
//  the MeshPackets actor because that actor owns every node/position delete (cap
//  eviction, near-duplicate pruning); the previous main-context walk raced those
//  deletes and trapped in SwiftData's backing-data lookup, which was the app's
//  largest crash. These tests cover the mapping and filtering; the serialization
//  property is by construction (same actor), not something a unit test can race.
//

import CoreLocation
import Foundation
import SwiftData
import Testing

@testable import Meshtastic

@Suite("Watch node snapshot")
struct WatchNodeSnapshotTests {

	private static let userLat = 48.0
	private static let userLon = -122.0
	private static let halfMile = 804.672

	private func makeContainer() throws -> ModelContainer {
		try ModelContainer(
			for: Schema(MeshtasticSchema.allModels),
			configurations: ModelConfiguration(isStoredInMemoryOnly: true)
		)
	}

	@discardableResult
	private func seedNode(
		_ context: ModelContext,
		num: Int64,
		name: String,
		hasUser: Bool = true,
		latitude: Double? = nil,
		longitude: Double? = nil
	) -> NodeInfoEntity {
		let node = NodeInfoEntity()
		node.num = num
		node.lastHeard = Date()
		node.snr = 7.5
		if hasUser {
			let user = UserEntity()
			user.num = num
			user.longName = name
			user.shortName = String(name.prefix(4))
			node.user = user
			context.insert(user)
		}
		context.insert(node)
		if let latitude, let longitude {
			let position = PositionEntity()
			position.latitudeI = Int32(latitude * 1e7)
			position.longitudeI = Int32(longitude * 1e7)
			position.altitude = 42
			position.time = Date()
			position.nodePosition = node
			context.insert(position)
			node.latestPositionCache = position
		}
		return node
	}

	@Test func includesOnlyNodesWithUserAndPositionInRange() async throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		// In range: same coordinates as the user.
		seedNode(context, num: 1, name: "Near Node", latitude: Self.userLat, longitude: Self.userLon)
		// Out of range: a degree of latitude is ~111 km.
		seedNode(context, num: 2, name: "Far Node", latitude: Self.userLat + 1.0, longitude: Self.userLon)
		// No position at all.
		seedNode(context, num: 3, name: "No Position")
		// No user: excluded by the fetch predicate.
		seedNode(context, num: 4, name: "No User", hasUser: false, latitude: Self.userLat, longitude: Self.userLon)
		try context.save()

		let mesh = MeshPackets(modelContainer: container)
		let nodes = await mesh.watchNodeSnapshot(
			userLatitude: Self.userLat,
			userLongitude: Self.userLon,
			maxDistanceMeters: Self.halfMile
		)

		#expect(nodes.count == 1)
		let node = try #require(nodes.first)
		#expect(node.num == 1)
		#expect(node.longName == "Near Node")
		#expect(node.altitude == 42)
		#expect(node.snr == 7.5)
		#expect(node.latitude != nil && abs(node.latitude! - Self.userLat) < 0.0001)
	}

	@Test func zeroCoordinatePositionIsExcluded() async throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		// 0/0 is the mesh's "no fix" sentinel, not a real position.
		seedNode(context, num: 5, name: "Null Island", latitude: 0, longitude: 0)
		try context.save()

		let mesh = MeshPackets(modelContainer: container)
		let nodes = await mesh.watchNodeSnapshot(
			userLatitude: 0, userLongitude: 0, maxDistanceMeters: Self.halfMile
		)
		#expect(nodes.isEmpty)
	}

	/// A retired actor's container may be torn down mid-flight (recreateShared);
	/// the snapshot must refuse rather than read through it.
	@Test func invalidatedActorReturnsEmpty() async throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		seedNode(context, num: 6, name: "Live Node", latitude: Self.userLat, longitude: Self.userLon)
		try context.save()

		let mesh = MeshPackets(modelContainer: container)
		await mesh.invalidate()
		let nodes = await mesh.watchNodeSnapshot(
			userLatitude: Self.userLat,
			userLongitude: Self.userLon,
			maxDistanceMeters: Self.halfMile
		)
		#expect(nodes.isEmpty)
	}

	/// The exact scenario that crashed in the field: the actor deletes nodes (cap
	/// eviction) and the snapshot runs against the same store afterward. Deleted
	/// rows must simply be absent — no invalidated instances reachable.
	@Test func snapshotAfterActorEvictionSeesOnlySurvivors() async throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		for i in 1...5 {
			seedNode(context, num: Int64(i), name: "Node \(i)", latitude: Self.userLat, longitude: Self.userLon)
		}
		try context.save()

		let mesh = MeshPackets(modelContainer: container)
		await mesh.evictNodesIfOverCap(2)
		let nodes = await mesh.watchNodeSnapshot(
			userLatitude: Self.userLat,
			userLongitude: Self.userLon,
			maxDistanceMeters: Self.halfMile
		)
		#expect(nodes.count == 2)
	}
}
