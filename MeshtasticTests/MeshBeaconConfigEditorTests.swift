// MARK: MeshBeaconConfigEditorTests
//
//  Locks down the blocking client-side validation and flag-bitfield handling for the
//  Mesh Beacon module config editor (contract C2, FR-010/FR-011/FR-013, research D4):
//   - the beacon message is capped at 60 UTF-8 bytes (60 ok, 61 blocks save);
//   - the broadcast interval must be ≥ 3600 s (3600 ok, 3599 blocks save);
//   - toggling FLAG_LISTEN_ENABLED / FLAG_BROADCAST_ENABLED preserves every other bit,
//     including the firmware-managed FLAG_LEGACY_SPLIT;
//   - frequency slots survive a load and save, and 0 is treated as unset.
//

import Testing
import Foundation
import MeshtasticProtobufs
@testable import Meshtastic

@Suite("MeshBeaconConfigEditor")
struct MeshBeaconConfigEditorTests {

	// MARK: - Message length (FR-011)

	@Test func message60BytesIsValid() {
		let message = String(repeating: "a", count: 60)
		#expect(MeshBeaconValidation.messageByteCount(message) == 60)
		#expect(MeshBeaconValidation.isMessageValid(message))
	}

	@Test func message61BytesBlocksSave() {
		let message = String(repeating: "a", count: 61)
		#expect(MeshBeaconValidation.messageByteCount(message) == 61)
		#expect(!MeshBeaconValidation.isMessageValid(message))
	}

	@Test func aMessageThatFitTheOldLimitCanBeTooLongNow() {
		// The limit came down from 100. A radio configured before that still reports
		// the longer text, and the editor has to block the save rather than truncate.
		let message = String(repeating: "a", count: 100)
		#expect(!MeshBeaconValidation.isMessageValid(message))
	}

	@Test func messageByteCountUsesUTF8NotCharacters() {
		// A 4-byte emoji: 15 of them = 60 bytes (valid), 16 = 64 bytes (blocks).
		let ok = String(repeating: "😀", count: 15)
		let tooBig = String(repeating: "😀", count: 16)
		#expect(MeshBeaconValidation.messageByteCount(ok) == 60)
		#expect(MeshBeaconValidation.isMessageValid(ok))
		#expect(!MeshBeaconValidation.isMessageValid(tooBig))
	}

	@Test func emptyMessageIsValid() {
		#expect(MeshBeaconValidation.isMessageValid(""))
	}

	// MARK: - Interval (FR-013)

	@Test func interval3600IsValid() {
		#expect(MeshBeaconValidation.isIntervalValid(3600))
	}

	@Test func interval3599BlocksSave() {
		#expect(!MeshBeaconValidation.isIntervalValid(3599))
	}

	@Test func intervalAboveMinimumIsValid() {
		#expect(MeshBeaconValidation.isIntervalValid(7200))
	}

	@Test func intervalZeroBlocksSave() {
		#expect(!MeshBeaconValidation.isIntervalValid(0))
	}

	// MARK: - Flag bitfield preserves other bits (FR-010 / D4)

	@Test func settingListenPreservesLegacySplit() {
		// Start with only FLAG_LEGACY_SPLIT (4) set.
		let start = MeshBeaconFlags.legacySplit
		let result = MeshBeaconFlags.setting(start, MeshBeaconFlags.listenEnabled, to: true)
		#expect(MeshBeaconFlags.has(result, MeshBeaconFlags.listenEnabled))
		#expect(MeshBeaconFlags.has(result, MeshBeaconFlags.legacySplit))
		#expect(result == 5) // 4 | 1
	}

	@Test func clearingListenPreservesLegacySplit() {
		// Start with listen + legacy-split set (1 | 4 = 5).
		let start = MeshBeaconFlags.listenEnabled | MeshBeaconFlags.legacySplit
		let result = MeshBeaconFlags.setting(start, MeshBeaconFlags.listenEnabled, to: false)
		#expect(!MeshBeaconFlags.has(result, MeshBeaconFlags.listenEnabled))
		#expect(MeshBeaconFlags.has(result, MeshBeaconFlags.legacySplit))
		#expect(result == MeshBeaconFlags.legacySplit)
	}

	@Test func togglingBroadcastPreservesListenAndLegacySplit() {
		// listen + legacy-split set, broadcast off; enable broadcast.
		let start = MeshBeaconFlags.listenEnabled | MeshBeaconFlags.legacySplit
		let result = MeshBeaconFlags.setting(start, MeshBeaconFlags.broadcastEnabled, to: true)
		#expect(MeshBeaconFlags.has(result, MeshBeaconFlags.broadcastEnabled))
		#expect(MeshBeaconFlags.has(result, MeshBeaconFlags.listenEnabled))
		#expect(MeshBeaconFlags.has(result, MeshBeaconFlags.legacySplit))
		#expect(result == 7) // 1 | 2 | 4
	}

	@Test func settingAFlagAlreadySetIsIdempotent() {
		let start = MeshBeaconFlags.listenEnabled | MeshBeaconFlags.legacySplit
		let result = MeshBeaconFlags.setting(start, MeshBeaconFlags.listenEnabled, to: true)
		#expect(result == start)
	}

	@Test func hasReturnsFalseForUnsetFlag() {
		#expect(!MeshBeaconFlags.has(MeshBeaconFlags.broadcastEnabled, MeshBeaconFlags.listenEnabled))
	}

	// MARK: - Frequency slots

	/// Decodes what the app would send, the way the radio sees it.
	private func roundTrip(_ values: MeshBeaconConfigValues) throws -> ModuleConfig.MeshBeaconConfig {
		try ModuleConfig.MeshBeaconConfig(serializedBytes: values.config.serializedData())
	}

	private func fullConfig() -> ModuleConfig.MeshBeaconConfig {
		var config = ModuleConfig.MeshBeaconConfig()
		config.flags = 7
		config.broadcastMessage = "Join us"
		var channel = ChannelSettings()
		channel.name = "Seattle"
		channel.psk = Data([1, 2, 3])
		config.broadcastOfferChannel = channel
		config.broadcastOfferRegion = .us
		config.broadcastOfferPreset = .mediumFast
		config.broadcastOfferFrequencySlot = 20
		config.broadcastIntervalSecs = 7200
		var target = ModuleConfig.MeshBeaconConfig.BroadcastTarget()
		target.preset = .longFast
		target.region = .us
		target.channelIndex = 1
		target.frequencySlot = 52
		var plain = ModuleConfig.MeshBeaconConfig.BroadcastTarget()
		plain.channelIndex = 0
		config.broadcastTargets = [target, plain]
		return config
	}

	@Test func slotsSurviveLoadAndSave() throws {
		let values = MeshBeaconConfigValues(config: fullConfig())
		#expect(values.offerFrequencySlot == 20)
		#expect(values.targets.map(\.frequencySlot) == [52, 0])

		let sent = try roundTrip(values)
		#expect(sent.hasBroadcastOfferFrequencySlot)
		#expect(sent.broadcastOfferFrequencySlot == 20)
		#expect(sent.broadcastTargets[0].hasFrequencySlot)
		#expect(sent.broadcastTargets[0].frequencySlot == 52)
		#expect(!sent.broadcastTargets[1].hasFrequencySlot)
	}

	@Test func otherFieldsSurviveLoadAndSave() throws {
		let sent = try roundTrip(MeshBeaconConfigValues(config: fullConfig()))
		#expect(sent == fullConfig())
	}

	@Test func absentSlotsStayAbsent() throws {
		var config = fullConfig()
		config.clearBroadcastOfferFrequencySlot()
		config.broadcastTargets[0].clearFrequencySlot()
		let values = MeshBeaconConfigValues(config: config)
		#expect(values.offerFrequencySlot == 0)
		#expect(values.targets[0].frequencySlot == 0)

		let sent = try roundTrip(values)
		#expect(!sent.hasBroadcastOfferFrequencySlot)
		#expect(!sent.broadcastTargets[0].hasFrequencySlot)
	}

	@Test func zeroSlotIsNeverSent() throws {
		// Another client may send 0, which means unset. Reading it back gives unset, and
		// saving never puts 0 on the wire.
		var config = fullConfig()
		config.broadcastOfferFrequencySlot = 0
		config.broadcastTargets[0].frequencySlot = 0
		let values = MeshBeaconConfigValues(config: config)
		#expect(values.offerFrequencySlot == 0)
		#expect(values.targets[0].frequencySlot == 0)

		let sent = try roundTrip(values)
		#expect(!sent.hasBroadcastOfferFrequencySlot)
		#expect(!sent.broadcastTargets[0].hasFrequencySlot)
	}

	@Test func unsetFieldsStayUnset() throws {
		// No offered channel or preset, no target preset or channel index: none appear on save.
		var config = ModuleConfig.MeshBeaconConfig()
		config.flags = 1
		config.broadcastIntervalSecs = 3600
		config.broadcastTargets = [ModuleConfig.MeshBeaconConfig.BroadcastTarget()]
		let sent = try roundTrip(MeshBeaconConfigValues(config: config))
		#expect(sent == config)
	}

	@Test func slotRange() {
		let count = MeshBeaconSlots.slotCount(region: Int32(RegionCodes.us.rawValue), preset: Int32(ModemPresets.longFast.rawValue))
		#expect(count == 104)
		#expect(MeshBeaconSlots.isValid(0, count: count))
		#expect(MeshBeaconSlots.isValid(1, count: count))
		#expect(MeshBeaconSlots.isValid(104, count: count))
		#expect(!MeshBeaconSlots.isValid(105, count: count))
		#expect(!MeshBeaconSlots.isValid(-1, count: count))
	}

	@Test func slotCountIsUnknownWithoutAPreset() {
		#expect(MeshBeaconSlots.slotCount(region: Int32(RegionCodes.us.rawValue), preset: -1) == 0)
		#expect(MeshBeaconSlots.isValid(300, count: 0))
	}
}
