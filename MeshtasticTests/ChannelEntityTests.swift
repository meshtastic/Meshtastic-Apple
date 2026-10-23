import Foundation
import Testing
import SwiftData
@testable import Meshtastic

@MainActor
@Suite("ChannelEntity")
struct ChannelEntityTests {
	let context = ModelContext(sharedModelContainer)

	@Test("Default init values")
	func channelEntityDefaultInit() {
		let channel = ChannelEntity()
		#expect(!channel.downlinkEnabled)
		#expect(channel.id == 0)
		#expect(channel.index == 0)
		#expect(!channel.mute)
		#expect(channel.name == nil)
		#expect(channel.positionPrecision == 32)
		#expect(channel.psk == nil)
		#expect(channel.role == 0)
		#expect(!channel.uplinkEnabled)
		#expect(channel.myInfoChannel == nil)
	}

	@Test("Insert and fetch by id")
	func channelEntityInsertAndFetch() throws {
		let channel = ChannelEntity()
		channel.id = 42
		channel.name = "Test Channel"
		channel.uplinkEnabled = true
		context.insert(channel)
		try context.save()

		let descriptor = FetchDescriptor<ChannelEntity>(predicate: #Predicate { $0.id == 42 })
		let fetched = try context.fetch(descriptor)
		#expect(fetched.count == 1)
		let first = try #require(fetched.first)
		#expect(first.name == "Test Channel")
		#expect(first.uplinkEnabled)
	}
}
