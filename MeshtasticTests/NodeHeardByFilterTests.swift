//
//  NodeHeardByFilterTests.swift
//  MeshtasticTests
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation
import SwiftData
import Testing

@testable import Meshtastic

/// The node, map and contact filters' "Heard By" choice (feature 021, T087).
@MainActor
@Suite("Node heard-by filter", .serialized)
struct NodeHeardByFilterTests {

	private let radioA: Int64 = 0x0A0A_0A0A
	private let radioB: Int64 = 0x0B0B_0B0B

	private func makeDefaults() -> UserDefaults {
		let suiteName = "NodeHeardByFilterTests"
		let defaults = UserDefaults(suiteName: suiteName)!
		defaults.removePersistentDomain(forName: suiteName)
		return defaults
	}

	private func makeContext() throws -> ModelContext {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let configuration = ModelConfiguration("HeardBy-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
		return ModelContext(try ModelContainer(for: schema, configurations: configuration))
	}

	@Test("The choice persists, counts as filtering and resets to any radio")
	func persistence() {
		let defaults = makeDefaults()
		let filters = NodeFilterParameters(store: defaults)
		#expect(filters.heardByRadio == 0)
		#expect(!filters.isFiltering)

		filters.heardByRadio = radioB
		#expect(filters.isFiltering)
		#expect(NodeFilterParameters(store: defaults).heardByRadio == radioB)

		filters.reset()
		#expect(filters.heardByRadio == 0)
		#expect(NodeFilterParameters(store: defaults).heardByRadio == 0)
	}

	@Test("Only nodes the chosen radio heard match, plus the radio itself")
	func nodesHeardByTheRadio() throws {
		let context = try makeContext()
		for radio in [radioA, radioB] {
			let myInfo = MyInfoEntity()
			myInfo.myNodeNum = radio
			context.insert(myInfo)
		}
		// 1 is heard by both, 2 only by A, 3 only by B.
		for (radio, node) in [(radioA, Int64(1)), (radioB, 1), (radioA, 2), (radioB, 3)] {
			context.insert(NodeObservationEntity(radioNum: radio, nodeNum: node))
		}
		try context.save()

		let filters = NodeFilterParameters(store: makeDefaults())
		filters.refreshHeardByNodeNums(in: context)
		#expect(filters.heardByNodeNums == nil)

		filters.heardByRadio = radioB
		#expect(filters.heardByNodeNums == nil, "looked up by the views' task, not while they render")
		filters.refreshHeardByNodeNums(in: context)
		let heardByB = try #require(filters.heardByNodeNums)
		#expect(heardByB == [1, 3, radioB])

		func node(_ num: Int64) -> NodeInfoEntity {
			let node = NodeInfoEntity()
			node.num = num
			return node
		}
		#expect(filters.matches(node(1), heardByNodeNums: heardByB))
		#expect(!filters.matches(node(2), heardByNodeNums: heardByB))
		#expect(filters.matches(node(3), heardByNodeNums: heardByB))
		#expect(filters.matches(node(radioB), heardByNodeNums: heardByB))
	}

	@Test("A radio that's no longer one of the user's radios doesn't filter anything")
	func unknownRadioDoesNotFilter() throws {
		let context = try makeContext()
		context.insert(NodeObservationEntity(radioNum: radioB, nodeNum: 1))
		try context.save()

		let filters = NodeFilterParameters(store: makeDefaults())
		filters.heardByRadio = radioB
		filters.refreshHeardByNodeNums(in: context)
		#expect(filters.heardByNodeNums == nil)
	}
}
