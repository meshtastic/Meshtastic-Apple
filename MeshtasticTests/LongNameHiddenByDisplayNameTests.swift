//
//  LongNameHiddenByDisplayNameTests.swift
//  MeshtasticTests
//

import Testing
@testable import Meshtastic

/// Node details shows a Long Name row only while a local display name hides the node's
/// broadcast long name.
@Suite("Long name hidden by display name", .serialized)
struct LongNameHiddenByDisplayNameTests {

	private let nodeNum: Int64 = 0x2604_0001

	private func makeUser(longName: String?) -> UserEntity {
		let user = UserEntity()
		user.num = nodeNum
		user.longName = longName
		return user
	}

	@Test("No display name means no Long Name row")
	func noDisplayName() {
		NodeDisplayNameStore.setDisplayName(nil, for: nodeNum)
		#expect(makeUser(longName: "Ballard Beacon").longNameHiddenByDisplayName == nil)
	}

	@Test("A display name shows the broadcast long name, not the display name")
	func displayNameSet() {
		NodeDisplayNameStore.setDisplayName("Mom's Radio", for: nodeNum)
		defer { NodeDisplayNameStore.setDisplayName(nil, for: nodeNum) }
		#expect(makeUser(longName: "Ballard Beacon").longNameHiddenByDisplayName == "Ballard Beacon")
	}

	@Test("A display name with no long name means no Long Name row", arguments: [nil, ""] as [String?])
	func displayNameWithoutLongName(longName: String?) {
		NodeDisplayNameStore.setDisplayName("Mom's Radio", for: nodeNum)
		defer { NodeDisplayNameStore.setDisplayName(nil, for: nodeNum) }
		#expect(makeUser(longName: longName).longNameHiddenByDisplayName == nil)
	}
}
