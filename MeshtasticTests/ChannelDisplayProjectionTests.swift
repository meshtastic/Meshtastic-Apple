import Testing
@testable import Meshtastic

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

	private func channel(index: Int32, name: String) -> ChannelEntity {
		let channel = ChannelEntity()
		channel.index = index
		channel.name = name
		return channel
	}
}
