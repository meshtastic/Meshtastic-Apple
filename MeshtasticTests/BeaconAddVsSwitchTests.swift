// MARK: BeaconAddVsSwitchTests
//
//  Locks down the Add-vs-Switch join decision (contract C6, FR-016/FR-017):
//  - `.add` only when the offered preset + region match the radio AND the offered channel
//    resolves to the radio's current operating frequency slot (no retune / no reboot).
//  - `.switchOnly` on any slot / preset / region mismatch.
//  - `.none` when the beacon offered no channel, or no radio is connected.
//

import Testing
import Foundation
@testable import Meshtastic

@Suite("BeaconAddVsSwitch")
@MainActor
struct BeaconAddVsSwitchTests {

	/// A connected US-region, LongFast radio on a named primary channel "MyMesh".
	private func usLongFastConfig() -> LoRaConfigEntity {
		let config = LoRaConfigEntity()
		config.regionCode = Int32(RegionCodes.us.rawValue)          // 1
		config.modemPreset = Int32(ModemPresets.longFast.rawValue)  // 0
		config.usePreset = true
		config.channelNum = 0
		return config
	}

	private func itu2TinyFastConfig(channelNum: Int32 = 0) -> LoRaConfigEntity {
		let config = LoRaConfigEntity()
		config.regionCode = Int32(RegionCodes.itu22M.rawValue)
		config.modemPreset = Int32(ModemPresets.tinyFast.rawValue)
		config.usePreset = true
		config.channelNum = channelNum
		return config
	}

	// MARK: .add — everything matches

	@Test func addWhenSlotPresetAndRegionMatch() {
		let option = LoRaChannelCalculator.beaconJoinOption(
			hasOfferChannel: true,
			offerChannelName: "MyMesh",          // same name → same slot as the radio's primary
			offeredPreset: .longFast,
			offerRegion: RegionCodes.us.rawValue,
			isConnected: true,
			loRaConfig: usLongFastConfig(),
			primaryChannelName: "MyMesh"
		)
		#expect(option == .add)
	}

	@Test func addWhenBeaconOffersNoRegion() {
		// offerRegion == 0 means the beacon didn't advertise a region → can't be a region mismatch.
		let option = LoRaChannelCalculator.beaconJoinOption(
			hasOfferChannel: true,
			offerChannelName: "MyMesh",
			offeredPreset: .longFast,
			offerRegion: 0,
			isConnected: true,
			loRaConfig: usLongFastConfig(),
			primaryChannelName: "MyMesh"
		)
		#expect(option == .add)
	}

	@Test func addWhenHamBeaconUsesFirmwareDefaultSlot() {
		// "TinyFast" hashes to slot 144, but an unset ITU2_2M channel actually uses
		// the firmware default slot 51 on both meshes.
		let option = LoRaChannelCalculator.beaconJoinOption(
			hasOfferChannel: true,
			offerChannelName: "TinyFast",
			offeredPreset: .tinyFast,
			offerRegion: RegionCodes.itu22M.rawValue,
			isConnected: true,
			loRaConfig: itu2TinyFastConfig(),
			primaryChannelName: "TinyFast"
		)
		#expect(option == .add)
	}

	// MARK: .switchOnly — mismatches

	@Test func switchOnlyOnSlotMismatch() {
		// Offered channel hashes to a different slot than the radio's current primary.
		let option = LoRaChannelCalculator.beaconJoinOption(
			hasOfferChannel: true,
			offerChannelName: "PrivateNet",      // slot 16 vs radio's "MyMesh" slot 41
			offeredPreset: .longFast,
			offerRegion: RegionCodes.us.rawValue,
			isConnected: true,
			loRaConfig: usLongFastConfig(),
			primaryChannelName: "MyMesh"
		)
		#expect(option == .switchOnly)
	}

	@Test func switchOnlyWhenHamRadioPinsDifferentSlot() {
		// The beacon resolves to the region's default slot 51, while this radio is
		// explicitly pinned to slot 52.
		let option = LoRaChannelCalculator.beaconJoinOption(
			hasOfferChannel: true,
			offerChannelName: "TinyFast",
			offeredPreset: .tinyFast,
			offerRegion: RegionCodes.itu22M.rawValue,
			isConnected: true,
			loRaConfig: itu2TinyFastConfig(channelNum: 52),
			primaryChannelName: "TinyFast"
		)
		#expect(option == .switchOnly)
	}

	@Test func switchOnlyOnPresetMismatch() {
		let option = LoRaChannelCalculator.beaconJoinOption(
			hasOfferChannel: true,
			offerChannelName: "MyMesh",
			offeredPreset: .shortFast,           // radio is longFast
			offerRegion: RegionCodes.us.rawValue,
			isConnected: true,
			loRaConfig: usLongFastConfig(),
			primaryChannelName: "MyMesh"
		)
		#expect(option == .switchOnly)
	}

	@Test func switchOnlyOnRegionMismatch() {
		let option = LoRaChannelCalculator.beaconJoinOption(
			hasOfferChannel: true,
			offerChannelName: "MyMesh",
			offeredPreset: .longFast,
			offerRegion: RegionCodes.eu868.rawValue, // radio is US
			isConnected: true,
			loRaConfig: usLongFastConfig(),
			primaryChannelName: "MyMesh"
		)
		#expect(option == .switchOnly)
	}

	@Test func switchOnlyWhenConfigMissing() {
		// Connected + has channel but no synced LoRa config → can't verify the slot, never Add.
		let option = LoRaChannelCalculator.beaconJoinOption(
			hasOfferChannel: true,
			offerChannelName: "MyMesh",
			offeredPreset: .longFast,
			offerRegion: RegionCodes.us.rawValue,
			isConnected: true,
			loRaConfig: nil,
			primaryChannelName: "MyMesh"
		)
		#expect(option == .switchOnly)
	}

	// MARK: .none — no channel / not connected

	@Test func noneWhenNoOfferChannel() {
		let option = LoRaChannelCalculator.beaconJoinOption(
			hasOfferChannel: false,
			offerChannelName: "MyMesh",
			offeredPreset: .longFast,
			offerRegion: RegionCodes.us.rawValue,
			isConnected: true,
			loRaConfig: usLongFastConfig(),
			primaryChannelName: "MyMesh"
		)
		#expect(option == .none)
	}

	@Test func noneWhenOfferChannelNameEmpty() {
		let option = LoRaChannelCalculator.beaconJoinOption(
			hasOfferChannel: true,
			offerChannelName: "",
			offeredPreset: .longFast,
			offerRegion: RegionCodes.us.rawValue,
			isConnected: true,
			loRaConfig: usLongFastConfig(),
			primaryChannelName: "MyMesh"
		)
		#expect(option == .none)
	}

	@Test func noneWhenNotConnected() {
		let option = LoRaChannelCalculator.beaconJoinOption(
			hasOfferChannel: true,
			offerChannelName: "MyMesh",
			offeredPreset: .longFast,
			offerRegion: RegionCodes.us.rawValue,
			isConnected: false,
			loRaConfig: usLongFastConfig(),
			primaryChannelName: "MyMesh"
		)
		#expect(option == .none)
	}

	// MARK: - A beacon that pins its own frequency slot

	/// Computed the same way the decision computes it, so these cases do not hard-code
	/// a hash result that a region-table change would quietly invalidate.
	private func usLongFastRadioSlot() -> Int {
		LoRaChannelCalculator(config: usLongFastConfig()).effectiveChannelSlot(primaryName: "MyMesh")
	}

	@Test func aPinnedSlotAwayFromTheRadioBlocksAdd() {
		// The offered name derives to the radio's own slot, so before the pin was read
		// this said Add — and the added channel would have sat on a frequency the mesh
		// is not on, with nothing on screen to say so.
		let option = LoRaChannelCalculator.beaconJoinOption(
			hasOfferChannel: true,
			offerChannelName: "MyMesh",
			offeredPreset: .longFast,
			offerRegion: RegionCodes.us.rawValue,
			offeredFrequencySlot: usLongFastRadioSlot() + 1,
			isConnected: true,
			loRaConfig: usLongFastConfig(),
			primaryChannelName: "MyMesh"
		)
		#expect(option == .switchOnly)
	}

	@Test func aPinnedSlotOnTheRadioAllowsAdd() {
		let calculator = LoRaChannelCalculator(config: usLongFastConfig())
		#expect(
			calculator.slotForChannelName("SomeOtherMesh") != usLongFastRadioSlot(),
			"this case only means something while the offered name derives somewhere else")

		let option = LoRaChannelCalculator.beaconJoinOption(
			hasOfferChannel: true,
			offerChannelName: "SomeOtherMesh",
			offeredPreset: .longFast,
			offerRegion: RegionCodes.us.rawValue,
			offeredFrequencySlot: usLongFastRadioSlot(),
			isConnected: true,
			loRaConfig: usLongFastConfig(),
			primaryChannelName: "MyMesh"
		)
		#expect(option == .add)
	}

	@Test func noPinKeepsTheDerivedSlot() {
		// The common case: a beacon that sends no slot still resolves by name.
		let option = LoRaChannelCalculator.beaconJoinOption(
			hasOfferChannel: true,
			offerChannelName: "MyMesh",
			offeredPreset: .longFast,
			offerRegion: RegionCodes.us.rawValue,
			offeredFrequencySlot: nil,
			isConnected: true,
			loRaConfig: usLongFastConfig(),
			primaryChannelName: "MyMesh"
		)
		#expect(option == .add)
	}

	@Test func aBeaconReadsZeroAsNoPinAtAll() {
		// The proto says 0 means the same as omitting the field, so the entity must not
		// hand a 0 to the decision as if it were slot zero.
		let beacon = DiscoveredBeaconEntity()
		beacon.offerFrequencySlot = 0
		#expect(beacon.offeredFrequencySlot == nil)

		beacon.offerFrequencySlot = 42
		#expect(beacon.offeredFrequencySlot == 42)
	}

	// MARK: - Pinned slot checked against the region

	@Test func aPinnedSlotPastTheRegionIsNotJoinable() {
		// US LongFast has far fewer than 500 slots; tuning there would be off-band.
		let option = LoRaChannelCalculator.beaconJoinOption(
			hasOfferChannel: true,
			offerChannelName: "MyMesh",
			offeredPreset: .longFast,
			offerRegion: RegionCodes.us.rawValue,
			offeredFrequencySlot: 500,
			isConnected: true,
			loRaConfig: usLongFastConfig(),
			primaryChannelName: "MyMesh"
		)
		#expect(option == .none)
	}

	@Test func aPinnedSlotIsCheckedAgainstTheOfferedPreset() {
		// The last US LongFast slot does not exist on a wider preset with fewer slots.
		let lastLongFastSlot = LoRaChannelCalculator(config: usLongFastConfig()).numChannels()
		#expect(LoRaChannelCalculator.isValidBeaconSlot(lastLongFastSlot, regionCode: RegionCodes.us.rawValue, preset: .longFast))
		#expect(!LoRaChannelCalculator.isValidBeaconSlot(lastLongFastSlot, regionCode: RegionCodes.us.rawValue, preset: .shortTurbo))
	}

	@Test func aPresetWiderThanTheRegionHasNoValidSlot() {
		// EU868 is 250 kHz wide; ShortTurbo needs 500 kHz. The firmware refuses it, even though
		// the slot count used for the channel-name hash still rounds up to one.
		let eu868 = RegionCodes.eu868.rawValue
		#expect(!LoRaChannelCalculator.isValidBeaconSlot(1, regionCode: eu868, preset: .shortTurbo))
		#expect(LoRaChannelCalculator.isValidBeaconSlot(1, regionCode: eu868, preset: .longFast))
		let calculator = LoRaChannelCalculator(
			regionCode: eu868, usePreset: true, modemPreset: ModemPresets.shortTurbo.rawValue,
			channelNum: 0, bandwidth: 0, overrideFrequency: 0
		)
		#expect(calculator.numChannels() == 1)
	}

	@Test func theLastRoundedSlotIsAcceptedLikeTheFirmware() {
		// PH433 is 1.7 MHz wide, so LongFast rounds to 7 slots. The firmware accepts slot 7
		// (and can hash a channel name onto it), so the app does too; slot 8 is past the count.
		let ph433 = RegionCodes.ph433.rawValue
		#expect(LoRaChannelCalculator.isValidBeaconSlot(7, regionCode: ph433, preset: .longFast))
		#expect(!LoRaChannelCalculator.isValidBeaconSlot(8, regionCode: ph433, preset: .longFast))
		let ua433 = RegionCodes.ua433.rawValue
		#expect(LoRaChannelCalculator.isValidBeaconSlot(7, regionCode: ua433, preset: .longFast))
		#expect(!LoRaChannelCalculator.isValidBeaconSlot(8, regionCode: ua433, preset: .longFast))
	}

	@Test func slotBoundsAreOneBased() {
		let us = RegionCodes.us.rawValue
		#expect(!LoRaChannelCalculator.isValidBeaconSlot(0, regionCode: us, preset: .longFast))
		#expect(LoRaChannelCalculator.isValidBeaconSlot(1, regionCode: us, preset: .longFast))
		#expect(!LoRaChannelCalculator.isValidBeaconSlot(-1, regionCode: us, preset: .longFast))
	}

	// MARK: - A beacon with no preset means the region's default

	@Test func noPresetMeansLongFastWithoutARegionMap() {
		let option = LoRaChannelCalculator.beaconJoinOption(
			hasOfferChannel: true,
			offerChannelName: "MyMesh",
			offeredPreset: nil,
			offerRegion: RegionCodes.us.rawValue,
			isConnected: true,
			loRaConfig: usLongFastConfig(),
			primaryChannelName: "MyMesh"
		)
		#expect(option == .add)
	}

	@Test func noPresetUsesTheRegionDefaultFromTheRadio() {
		// The radio says US defaults to LongTurbo, so a preset-less beacon is not on this
		// LongFast radio's preset.
		let usTurbo = RegionPresetInfo(presets: [.longFast, .longTurbo], defaultPreset: .longTurbo, licensedOnly: false)
		let option = LoRaChannelCalculator.beaconJoinOption(
			hasOfferChannel: true,
			offerChannelName: "MyMesh",
			offeredPreset: nil,
			offerRegion: RegionCodes.us.rawValue,
			regionPresets: [.us: usTurbo],
			isConnected: true,
			loRaConfig: usLongFastConfig(),
			primaryChannelName: "MyMesh"
		)
		#expect(option == .switchOnly)
	}

	@Test func beaconPresetPrefersTheOfferThenTheRegionDefault() {
		let usTurbo = RegionPresetInfo(presets: [.longFast, .longTurbo], defaultPreset: .longTurbo, licensedOnly: false)
		#expect(LoRaChannelCalculator.beaconPreset(offered: .shortFast, regionInfo: usTurbo) == .shortFast)
		#expect(LoRaChannelCalculator.beaconPreset(offered: nil, regionInfo: usTurbo) == .longTurbo)
		#expect(LoRaChannelCalculator.beaconPreset(offered: nil, regionInfo: nil) == .longFast)
	}
}
