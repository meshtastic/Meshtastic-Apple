import Foundation
import MeshtasticProtobufs
import Security
import Testing

@testable import Meshtastic

@Suite("iMessage share snapshots")
struct MeshShareSnapshotTests {
	@Test @MainActor func channelEntityPreservesEveryShareableSetting() {
		var incoming = Channel()
		incoming.index = 3
		incoming.role = .secondary
		incoming.settings.id = 0xF1234567
		incoming.settings.name = "Private"
		incoming.settings.psk = Data(repeating: 4, count: 16)
		incoming.settings.uplinkEnabled = true
		incoming.settings.downlinkEnabled = true
		incoming.settings.moduleSettings.positionPrecision = 11
		incoming.settings.moduleSettings.isMuted = true
		let entity = ChannelEntity()

		entity.update(from: incoming)
		let output = entity.settingsProto

		#expect(entity.index == 3)
		#expect(entity.role == Int32(Channel.Role.secondary.rawValue))
		#expect(output.id == 0xF1234567)
		#expect(output.name == "Private")
		#expect(output.psk == Data(repeating: 4, count: 16))
		#expect(output.uplinkEnabled)
		#expect(output.downlinkEnabled)
		#expect(output.moduleSettings.positionPrecision == 11)
		#expect(output.moduleSettings.isMuted)
	}

	@Test func failedRefreshClearsOnlyADifferentRadiosSnapshot() {
		#expect(MeshShareSnapshotBuilder.shouldClearExistingSnapshot(existingNodeNum: 1, attemptedNodeNum: 2))
		#expect(!MeshShareSnapshotBuilder.shouldClearExistingSnapshot(existingNodeNum: 2, attemptedNodeNum: 2))
		#expect(!MeshShareSnapshotBuilder.shouldClearExistingSnapshot(existingNodeNum: nil, attemptedNodeNum: 2))
	}

	@Test func keychainQueryAlwaysUsesDedicatedAccessGroup() {
		let group = "TEAM.gvh.MeshtasticClient.MessagesSharing"

		let query = MeshShareStore.query(accessGroup: group)

		#expect(query[kSecAttrAccessGroup as String] as? String == group)
		#expect(query[kSecAttrService as String] as? String == MeshShareStore.service)
		#expect(query[kSecAttrSynchronizable as String] as? Bool == false)
	}

	@Test func snapshotRoundTripsAndBecomesStaleAfterThirtyDays() throws {
		let now = Date(timeIntervalSince1970: 2_000_000)
		let snapshot = MeshShareSnapshot(
			radioNodeNum: 42,
			radioLongName: "Base Camp",
			radioShortName: "BASE",
			contactURL: "https://meshtastic.org/v/#abc",
			loraConfigData: Data([1]),
			channels: [],
			refreshedAt: now
		)

		let data = try JSONEncoder().encode(snapshot)
		let decoded = try JSONDecoder().decode(MeshShareSnapshot.self, from: data)

		#expect(decoded == snapshot)
		#expect(!snapshot.isStale(at: now.addingTimeInterval(30 * 86_400)))
		#expect(snapshot.isStale(at: now.addingTimeInterval(30 * 86_400 + 1)))
		#expect(
			MeshShareSnapshot(
				radioNodeNum: 42,
				radioLongName: "Base Camp",
				radioShortName: "BASE",
				contactURL: "https://meshtastic.org/v/?exchange=true#abc",
				loraConfigData: Data(),
				channels: [],
				refreshedAt: now
			).contactReplyURL == "https://meshtastic.org/v/#abc"
		)
	}

	@Test func channelSelectionDefaultsToAllAndReplacePreservesLoRa() throws {
		var lora = Config.LoRaConfig()
		lora.hopLimit = 5
		var alpha = ChannelSettings()
		alpha.name = "Alpha"
		alpha.psk = Data([1, 2, 3, 4])
		var beta = ChannelSettings()
		beta.name = "Beta"
		beta.psk = Data([9, 8, 7, 6])
		let snapshot = MeshShareSnapshot(
			radioNodeNum: 42,
			radioLongName: "Base Camp",
			radioShortName: "BASE",
			contactURL: "https://meshtastic.org/v/#abc",
			loraConfigData: try lora.serializedData(),
			channels: [
				MeshShareChannel(index: 0, name: "Alpha", isEncrypted: true, settingsData: try alpha.serializedData()),
				MeshShareChannel(index: 1, name: "Beta", isEncrypted: true, settingsData: try beta.serializedData())
			],
			refreshedAt: .now
		)
		let selection = MeshChannelSelection(snapshot: snapshot)

		#expect(selection.defaultSelectedIndexes == [0, 1])
		let parsed = try MeshtasticChannelURL.parse(
			selection.url(selectedIndexes: [1], mode: .replace)
		)
		#expect(parsed.channelSet.settings.map(\.name) == ["Beta"])
		#expect(parsed.channelSet.loraConfig.hopLimit == 5)
		#expect(parsed.channelSet.settings[0].psk == Data([9, 8, 7, 6]))
	}

	@Test func addModeClearsLoRaAndEmptySelectionFails() throws {
		var channel = ChannelSettings()
		channel.name = "Alpha"
		let snapshot = MeshShareSnapshot(
			radioNodeNum: 42,
			radioLongName: "Base Camp",
			radioShortName: "BASE",
			contactURL: "https://meshtastic.org/v/#abc",
			loraConfigData: try Config.LoRaConfig().serializedData(),
			channels: [
				MeshShareChannel(index: 0, name: "Alpha", isEncrypted: false, settingsData: try channel.serializedData())
			],
			refreshedAt: .now
		)
		let selection = MeshChannelSelection(snapshot: snapshot)

		let parsed = try MeshtasticChannelURL.parse(selection.url(selectedIndexes: [0], mode: .add))
		#expect(parsed.addChannels)
		#expect(!parsed.channelSet.hasLoraConfig)
		#expect(throws: MeshChannelSelection.SelectionError.noChannels) {
			_ = try selection.url(selectedIndexes: [], mode: .replace)
		}
	}
}
