//
//  DisplayNameSurfaceTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/8/26.
//

import Testing
@testable import Meshtastic

/// Screens on this device name a node by its local display name; what leaves the device keeps
/// the broadcast long name (#2950).
@Suite("Display name surfaces", .serialized)
struct DisplayNameSurfaceTests {

	private let nodeNum: Int64 = 0x2950_0001

	private func makeNode(longName: String?) -> NodeInfoEntity {
		let user = UserEntity()
		user.num = nodeNum
		user.longName = longName
		user.shortName = "BB"
		let node = NodeInfoEntity()
		node.num = nodeNum
		node.user = user
		return node
	}

	@Test("With no display name, the broadcast long name is used")
	func noDisplayName() {
		NodeDisplayNameStore.setDisplayName(nil, for: nodeNum)
		let user = makeNode(longName: "Ballard Beacon").user
		#expect(user?.localLongName == "Ballard Beacon")
		#expect(TraceRouteLegs.NodeDetails(node: makeNode(longName: "Ballard Beacon")).longName == "Ballard Beacon")
	}

	@Test("With no names at all, callers keep their own fallback")
	func noNames() {
		NodeDisplayNameStore.setDisplayName(nil, for: nodeNum)
		#expect(makeNode(longName: nil).user?.localLongName == nil)
	}

	@Test("A display name replaces the long name on screen")
	func displayNameSet() {
		NodeDisplayNameStore.setDisplayName("Mom's Radio", for: nodeNum)
		defer { NodeDisplayNameStore.setDisplayName(nil, for: nodeNum) }
		#expect(makeNode(longName: "Ballard Beacon").user?.localLongName == "Mom's Radio")
		#expect(makeNode(longName: nil).user?.localLongName == "Mom's Radio")
		#expect(TraceRouteLegs.NodeDetails(node: makeNode(longName: "Ballard Beacon")).longName == "Mom's Radio")
	}

	@Test("The trace route share image keeps the broadcast long name")
	func shareKeepsBroadcastName() {
		NodeDisplayNameStore.setDisplayName("Mom's Radio", for: nodeNum)
		defer { NodeDisplayNameStore.setDisplayName(nil, for: nodeNum) }
		let details = TraceRouteLegs.NodeDetails(node: makeNode(longName: "Ballard Beacon"), broadcastName: true)
		#expect(details.longName == "Ballard Beacon")
	}

	@Test("Setting and clearing a name is seen on the next read")
	func storeReadsBackChanges() {
		NodeDisplayNameStore.setDisplayName("First", for: nodeNum)
		#expect(NodeDisplayNameStore.displayName(for: nodeNum) == "First")
		#expect(NodeDisplayNameStore.hasDisplayNames)
		NodeDisplayNameStore.setDisplayName("Second", for: nodeNum)
		#expect(NodeDisplayNameStore.displayName(for: nodeNum) == "Second")
		NodeDisplayNameStore.setDisplayName(nil, for: nodeNum)
		#expect(NodeDisplayNameStore.displayName(for: nodeNum) == nil)
	}
}
