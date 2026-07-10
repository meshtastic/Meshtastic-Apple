// MARK: LoRaRFHelpersTests
//
//  Locks down the sourced RF constants in LoRaRFHelpers — see the doc comments on
//  each function under test for citations (meshtastic.org radio-settings docs,
//  config.proto comments, FCC/ETSI regulatory limits).
//

import Testing
import Foundation
@testable import Meshtastic

@Suite("LoRaRFHelpers")
struct LoRaRFHelpersTests {

	// MARK: Sensitivity — published presets (meshtastic.org radio-settings table)

	@Test func sensitivityForPublishedPresets() {
		#expect(LoRaRFHelpers.receiverSensitivityDBm(for: .shortTurbo) == -118.0)
		#expect(LoRaRFHelpers.receiverSensitivityDBm(for: .shortFast) == -121.0)
		#expect(LoRaRFHelpers.receiverSensitivityDBm(for: .shortSlow) == -123.5)
		#expect(LoRaRFHelpers.receiverSensitivityDBm(for: .medFast) == -126.0)
		#expect(LoRaRFHelpers.receiverSensitivityDBm(for: .medSlow) == -128.5)
		#expect(LoRaRFHelpers.receiverSensitivityDBm(for: .longTurbo) == -128.0)
		#expect(LoRaRFHelpers.receiverSensitivityDBm(for: .longFast) == -131.0)
		#expect(LoRaRFHelpers.receiverSensitivityDBm(for: .longModerate) == -134.0)
		#expect(LoRaRFHelpers.receiverSensitivityDBm(for: .longSlow) == -136.5)
	}

	/// Longer spreading factor / narrower bandwidth must always yield better (more
	/// negative) sensitivity than a shorter/wider one — a monotonicity sanity check
	/// independent of the exact published numbers.
	@Test func sensitivityIsMonotonicWithRange() {
		#expect(LoRaRFHelpers.receiverSensitivityDBm(for: .longSlow) < LoRaRFHelpers.receiverSensitivityDBm(for: .longFast))
		#expect(LoRaRFHelpers.receiverSensitivityDBm(for: .longFast) < LoRaRFHelpers.receiverSensitivityDBm(for: .medFast))
		#expect(LoRaRFHelpers.receiverSensitivityDBm(for: .medFast) < LoRaRFHelpers.receiverSensitivityDBm(for: .shortFast))
	}

	// MARK: Sensitivity — 2.8-only presets (config.proto "comparable link budget to X")

	@Test func sensitivityForComparablePresetsMatchesTheirReference() {
		#expect(LoRaRFHelpers.receiverSensitivityDBm(for: .liteFast) == LoRaRFHelpers.receiverSensitivityDBm(for: .medFast))
		#expect(LoRaRFHelpers.receiverSensitivityDBm(for: .liteSlow) == LoRaRFHelpers.receiverSensitivityDBm(for: .longFast))
		#expect(LoRaRFHelpers.receiverSensitivityDBm(for: .narrowFast) == LoRaRFHelpers.receiverSensitivityDBm(for: .shortSlow))
		#expect(LoRaRFHelpers.receiverSensitivityDBm(for: .narrowSlow) == LoRaRFHelpers.receiverSensitivityDBm(for: .longFast))
		#expect(LoRaRFHelpers.receiverSensitivityDBm(for: .tinyFast) == LoRaRFHelpers.receiverSensitivityDBm(for: .longFast))
		#expect(LoRaRFHelpers.receiverSensitivityDBm(for: .tinySlow) == LoRaRFHelpers.receiverSensitivityDBm(for: .longModerate))
	}

	// MARK: Region max power

	@Test func usMaxPowerIsOneWatt() {
		#expect(LoRaRFHelpers.regionMaxPowerWatts(for: .us) == 1.0)
	}

	@Test func eu868MaxPowerIsTwentyFiveMilliwatts() {
		#expect(LoRaRFHelpers.regionMaxPowerWatts(for: .eu868) == 0.025)
	}

	@Test func unverifiedRegionFallsBackToPlannerDefault() {
		// Any region without a hardcoded regulatory figure must fall back to 0.1 W —
		// the Site Planner's own factory default — never an invented number.
		#expect(LoRaRFHelpers.regionMaxPowerWatts(for: .jp) == 0.1)
		#expect(LoRaRFHelpers.regionMaxPowerWatts(for: .kr) == 0.1)
	}

	// MARK: Transmit power resolution (the txPower==0 sentinel)

	@Test func zeroTxPowerResolvesToRegionMax() {
		#expect(LoRaRFHelpers.transmitPowerWatts(txPowerDBm: 0, region: .us) == 1.0)
	}

	@Test func nonZeroTxPowerConvertsDBmToWatts() {
		// 20 dBm == 0.1 W, 30 dBm == 1.0 W (standard dBm-to-watts conversion).
		#expect(abs(LoRaRFHelpers.transmitPowerWatts(txPowerDBm: 20, region: .us) - 0.1) < 0.0001)
		#expect(abs(LoRaRFHelpers.transmitPowerWatts(txPowerDBm: 30, region: .us) - 1.0) < 0.0001)
	}
}
