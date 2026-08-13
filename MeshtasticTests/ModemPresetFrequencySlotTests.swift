// MARK: ModemPresetFrequencySlotTests
//
//  Locks down the firmware-accurate frequency-slot derivation in LoRaChannelCalculator
//  (contract C5, FR-017). The slot is `djb2(name) % numChannels + 1` when channelNum == 0;
//  a non-zero channelNum pins the operating slot. slotForChannelName always derives from the
//  name and ignores the channelNum override.
//

import Testing
import Foundation
@testable import Meshtastic

@Suite("ModemPresetFrequencySlot")
@MainActor
struct ModemPresetFrequencySlotTests {

	/// A US-region, LongFast, preset-based config — the default public-channel case.
	private func usLongFastConfig(channelNum: Int32 = 0) -> LoRaConfigEntity {
		let config = LoRaConfigEntity()
		config.regionCode = Int32(RegionCodes.us.rawValue)      // 1
		config.modemPreset = Int32(ModemPresets.longFast.rawValue) // 0
		config.usePreset = true
		config.channelNum = channelNum
		return config
	}

	// MARK: Known firmware vectors (US region, LongFast → 104 channels)

	@Test func usLongFastHasExpectedChannelCount() {
		// freqStart 902, freqEnd 928, bandwidth 0.25 MHz → floor(26/0.25) = 104 channels.
		let calc = LoRaChannelCalculator(config: usLongFastConfig())
		// "LongFast" hashes into slot 20 on the 104-channel US band.
		#expect(calc.slotForChannelName("LongFast") == 20)
	}

	@Test func knownVectorsForUSLongFast() {
		let calc = LoRaChannelCalculator(config: usLongFastConfig())
		#expect(calc.slotForChannelName("MyMesh") == 41)
		#expect(calc.slotForChannelName("PrivateNet") == 16)
		#expect(calc.slotForChannelName("SecretBase") == 39)
	}

	// MARK: Determinism

	@Test func sameNameYieldsSameSlot() {
		let calc = LoRaChannelCalculator(config: usLongFastConfig())
		#expect(calc.slotForChannelName("Camp Alpha") == calc.slotForChannelName("Camp Alpha"))
	}

	@Test func differentNamesYieldDifferentSlots() {
		let calc = LoRaChannelCalculator(config: usLongFastConfig())
		#expect(calc.slotForChannelName("MyMesh") != calc.slotForChannelName("PrivateNet"))
	}

	@Test func slotIsWithinChannelRange() {
		let calc = LoRaChannelCalculator(config: usLongFastConfig())
		for name in ["a", "LongFast", "MyMesh", "🛰️ Base", "zzzzzzzz"] {
			let slot = calc.slotForChannelName(name)
			#expect(slot >= 1 && slot <= 104)
		}
	}

	// MARK: channelNum override semantics

	@Test func effectiveSlotRespectsChannelNumOverride() {
		let calc = LoRaChannelCalculator(config: usLongFastConfig(channelNum: 7))
		// With channelNum pinned, the operating slot is fixed regardless of name.
		#expect(calc.effectiveChannelSlot(primaryName: "MyMesh") == 7)
	}

	@Test func effectiveSlotDerivesFromNameWhenNoOverride() {
		let calc = LoRaChannelCalculator(config: usLongFastConfig(channelNum: 0))
		#expect(calc.effectiveChannelSlot(primaryName: "MyMesh") == 41)
	}

	@Test func slotForChannelNameIgnoresChannelNumOverride() {
		// slotForChannelName is always name-derived (the beacon channel's own slot), even when the
		// radio's channelNum is pinned — this is the distinction the Add-vs-Switch gate relies on.
		let calc = LoRaChannelCalculator(config: usLongFastConfig(channelNum: 7))
		#expect(calc.slotForChannelName("MyMesh") == 41)
	}

	// MARK: Frequency derivation

	@Test func frequencyForUSSlotIsWithinBand() {
		let calc = LoRaChannelCalculator(config: usLongFastConfig())
		// slot 20 → 902 + 0.125 + 19 * 0.25 = 906.875 MHz
		let freq = calc.radioFrequencyMHz(slot: 20)
		#expect(abs(freq - 906.875) < 0.001)
	}

	// MARK: Narrow single-channel regions

	@Test func eu868IsSingleChannel() {
		let config = LoRaConfigEntity()
		config.regionCode = Int32(RegionCodes.eu868.rawValue)
		config.modemPreset = Int32(ModemPresets.longFast.rawValue)
		config.usePreset = true
		let calc = LoRaChannelCalculator(config: config)
		// freqStart 869.4, freqEnd 869.65, bw 0.25 → floor(0.25/0.25) = 1 channel → always slot 1.
		#expect(calc.slotForChannelName("MyMesh") == 1)
		#expect(calc.slotForChannelName("Other") == 1)
	}
}
