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
}
