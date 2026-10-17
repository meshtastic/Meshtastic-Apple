//
//  ShowcaseSnapshotReaderTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
import Foundation
import SwiftData
import simd
import Testing
@testable import Meshtastic

@Suite("Showcase snapshot reader")
struct ShowcaseSnapshotReaderTests {

	private static let now = Date(timeIntervalSince1970: 2_000_000_000)

	private func makeContainer() throws -> ModelContainer {
		try ModelContainer(for: Schema(MeshtasticSchema.allModels), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
	}

	private func seed(
		_ context: ModelContext, num: Int64, heardAgo: TimeInterval?, favorite: Bool = false,
		ignored: Bool = false, withPosition: Bool = false, hwModel: String = "TBEAM"
	) {
		let node = NodeInfoEntity()
		node.num = num
		node.id = num
		node.favorite = favorite
		node.ignored = ignored
		node.lastHeard = heardAgo.map { Self.now.addingTimeInterval(-$0) }
		node.snr = 6.5
		node.rssi = -90
		let user = UserEntity()
		user.num = num
		user.shortName = "S\(num)"
		user.longName = "Node \(num)"
		user.hwModel = hwModel
		user.role = Int32(DeviceRoles.router.rawValue)
		node.user = user
		context.insert(user)
		context.insert(node)
		if withPosition {
			let position = PositionEntity()
			position.latitudeI = 476_000_000
			position.longitudeI = -1_223_000_000
			position.time = Self.now
			position.nodePosition = node
			context.insert(position)
			node.latestPositionCache = position
		}
	}

	@Test("Connected radio, then favorites, then newest heard; ignored nodes left out; nodes without a position kept")
	func ordering() async throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		seed(context, num: 1, heardAgo: 600)
		seed(context, num: 2, heardAgo: 60, withPosition: true)
		seed(context, num: 3, heardAgo: 5 * 60 * 60, favorite: true)
		seed(context, num: 4, heardAgo: 10, ignored: true)
		seed(context, num: 5, heardAgo: nil)
		seed(context, num: 6, heardAgo: 3 * 60 * 60)
		try context.save()

		let reader = ShowcaseSnapshotReader(modelContainer: container)
		let result = await reader.read(connectedNodeNum: 6, now: Self.now)
		#expect(result.nodes.map(\.id) == [6, 3, 2, 1, 5])
		#expect(result.totalCount == 5)
		let byNum = Dictionary(uniqueKeysWithValues: result.nodes.map { ($0.id, $0) })
		#expect(byNum[6]?.isConnectedRadio == true)
		#expect(byNum[6]?.isOnline == false)
		#expect(byNum[2]?.isOnline == true)
		#expect(byNum[2]?.hasPosition == true)
		#expect(byNum[1]?.hasPosition == false)
		#expect(byNum[2]?.shortName == "S2")
		#expect(byNum[2]?.hwModel == "TBEAM")
		#expect(byNum[2]?.role == .router)
		#expect(byNum[2]?.rssi == -90)
	}

	@Test("The limit keeps the connected radio and favorites and counts everyone")
	func limit() async throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		for num in 1...20 {
			seed(context, num: Int64(num), heardAgo: TimeInterval(num * 60), favorite: num == 20)
		}
		try context.save()

		let reader = ShowcaseSnapshotReader(modelContainer: container)
		let result = await reader.read(connectedNodeNum: 19, limit: 5, now: Self.now)
		#expect(result.nodes.map(\.id) == [19, 20, 1, 2, 3])
		#expect(result.totalCount == 20)
	}

	@Test("The rack's mesh faces outward")
	func meshes() {
		let grid = ShowcaseRackGrid.forRoom(rack: ShowcaseRoomGeometry.defaultPose(.wallRack))
		let rack = ShowcaseMeshGeometry.rackCells(grid: grid)
		#expect(rack.triangleCount == grid.perPage * 12)
		expectOutward(rack)
		// Cell 0 is the top row, so its texel is in the top row of the texture (v = 0 at the bottom).
		let texel = ShowcaseMeshGeometry.rackTexel(0, grid: grid)
		#expect(abs(texel.y - (1 - 0.5 / Float(grid.rows))) < 1e-5)
		#expect(texel.y > 0.5)
	}

	/// Every triangle winds counterclockwise seen from the side its normals face.
	private func expectOutward(_ mesh: ShowcaseMeshGeometry) {
		for part in mesh.parts.values {
			for triangle in stride(from: 0, to: part.indices.count, by: 3) {
				let a = part.positions[Int(part.indices[triangle])]
				let b = part.positions[Int(part.indices[triangle + 1])]
				let c = part.positions[Int(part.indices[triangle + 2])]
				let normal = part.normals[Int(part.indices[triangle])] + part.normals[Int(part.indices[triangle + 1])] + part.normals[Int(part.indices[triangle + 2])]
				#expect(simd_dot(simd_cross(b - a, c - a), normal) > 0)
			}
		}
	}
}
