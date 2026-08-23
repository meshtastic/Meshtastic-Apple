import Testing
@testable import Meshtastic
import MeshtasticProtobufs

@Suite("Channel display projection")
struct ChannelDisplayProjectionTests {
	@Test("Duplicate-index channels are projected without mutating the source relationship")
	func duplicateIndexChannelsRemainInSourceRelationship() {
		let stalePrimary = channel(index: 0, name: "Stale Primary")
		let freshPrimary = channel(index: 0, name: "Fresh Primary")
		let secondary = channel(index: 1, name: "Secondary")
		let myInfo = MyInfoEntity()
		myInfo.channels = [stalePrimary, freshPrimary, secondary]

		let displayChannels = projectedDisplayChannels(from: myInfo.channels)

		#expect(displayChannels.map(\.name) == ["Fresh Primary", "Secondary"])
		#expect(myInfo.channels.map(\.name) == ["Stale Primary", "Fresh Primary", "Secondary"])
	}

	@Test("Eight raw rows with a duplicate index still offer the missing secondary slot")
	func duplicateRawRowsUseValidUniqueIndexesForAddCapacity() {
		let channels = [
			channel(index: 0, name: "Legacy Primary"),
			channel(index: 0, name: "Current Primary"),
			channel(index: 1, name: "One"),
			channel(index: 2, name: "Two"),
			channel(index: 3, name: "Three"),
			channel(index: 4, name: "Four"),
			channel(index: 5, name: "Five"),
			channel(index: 6, name: "Six")
		]

		#expect(channels.count == 8)
		#expect(validUniqueChannelIndexes(from: channels) == [0, 1, 2, 3, 4, 5, 6])
		#expect(nextAvailableSecondaryChannelIndex(from: channels) == 7)
	}

	@Test("Sharing legacy duplicate rows serializes one ordered channel per valid index")
	@MainActor
	func sharingDuplicateIndexesSerializesOnlyOnePrimaryAndSevenChannels() throws {
		let stalePrimary = channel(index: 0, name: "Stale Primary")
		stalePrimary.role = 1
		let freshPrimary = channel(index: 0, name: "Fresh Primary")
		freshPrimary.role = 1
		let secondaries = (1...6).map { index -> ChannelEntity in
			let channel = channel(index: Int32(index), name: "Secondary \(index)")
			channel.role = 2
			return channel
		}
		var channelSet = ChannelSet()
		channelSet.settings = channelSettingsForSharing(
			from: [stalePrimary, freshPrimary] + secondaries,
			includedIndexes: Set(Int32(0)...Int32(7))
		)
		let serialized = try channelSet.serializedData()
		let decoded = try ChannelSet(serializedBytes: serialized)

		#expect(decoded.settings.map(\.name) == [
			"Fresh Primary", "Secondary 1", "Secondary 2", "Secondary 3",
			"Secondary 4", "Secondary 5", "Secondary 6"
		])
		#expect(decoded.settings.count <= 8)
		#expect(decoded.settings.filter { $0.name == "Fresh Primary" }.count == 1)
	}

	private func channel(index: Int32, name: String) -> ChannelEntity {
		let channel = ChannelEntity()
		channel.index = index
		channel.name = name
		return channel
	}
}
