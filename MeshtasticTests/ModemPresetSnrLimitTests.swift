// MARK: ModemPresetSnrLimitTests
//
//  Locks down the per-preset SNR demodulation floors returned by
//  `ModemPresets.snrLimit()`, which feed `getLoRaSignalStrength()` / `getSnrColor()`.
//  Regression coverage for issue #2041: LongSlow is SF12 (~-20 dB floor), not the
//  SF7 -7.5 dB value it was previously (mis)assigned. See Android's corrected
//  ChannelOption.kt table (meshtastic/Meshtastic-Android#5446).
//

import Testing
import Foundation
@testable import Meshtastic

@Suite("ModemPresetSnrLimit")
struct ModemPresetSnrLimitTests {

	// MARK: The fix

	@Test("LongSlow uses the SF12 demodulation floor (-20 dB)")
	func longSlowSnrFloorIsSF12() {
		#expect(ModemPresets.longSlow.snrLimit() == -20)
	}

	// MARK: Table guards (representative presets, matching Android)

	@Test("Representative preset SNR floors match the cross-platform table")
	func representativeFloorsMatchTable() {
		#expect(ModemPresets.longFast.snrLimit() == -17.5)
		#expect(ModemPresets.longModerate.snrLimit() == -17.5)
		#expect(ModemPresets.longTurbo.snrLimit() == -12.5)
		#expect(ModemPresets.medSlow.snrLimit() == -15)
		#expect(ModemPresets.medFast.snrLimit() == -12.5)
		#expect(ModemPresets.shortSlow.snrLimit() == -10)
		#expect(ModemPresets.shortFast.snrLimit() == -7.5)
		#expect(ModemPresets.shortTurbo.snrLimit() == -7.5)
	}

	// MARK: Regression scenario from the issue

	@Test("A -15 dB SNR LongSlow link rates as Good, not Bad")
	func longSlowGoodLinkRatesGood() {
		// -15 dB SNR is 5 dB above the correct -20 dB LongSlow floor.
		// With the old -7.5 dB floor this was mis-rated .bad.
		#expect(getLoRaSignalStrength(snr: -15, rssi: 0, preset: .longSlow) == .good)
		#expect(getSnrColor(snr: -15, preset: .longSlow) == .green)
	}

	@Test("A LongSlow link at the floor is not rated Good")
	func longSlowAtFloorNotGood() {
		// At exactly the floor, snr is not strictly greater, so it should not be .good.
		#expect(getLoRaSignalStrength(snr: -20, rssi: 0, preset: .longSlow) != .good)
	}
}
