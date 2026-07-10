//
//  LoRaRFHelpers.swift
//  Meshtastic
//
//  RF math for prefilling a Site Planner coverage estimate (spec 015) from the
//  connected radio's configuration. Every constant here is sourced from a real,
//  citable document — see the doc comment on each function — rather than
//  invented, per research.md §4's explicit "don't guess RF values" constraint.
//

import Foundation

enum LoRaRFHelpers {

	/// Receiver sensitivity in dBm for a modem preset, per Meshtastic's own published
	/// radio-settings table (https://meshtastic.org/docs/overview/radio-settings/,
	/// "Presets" section): `sensitivity ≈ txPowerAssumed(22 dBm) − linkBudget`, where
	/// the docs' link-budget column already assumes 22 dBm / 0 dBi.
	///
	/// The eight presets published there cover every pre-2.8 case. The six 2.8-only
	/// presets (Lite/Narrow/Tiny) have no published link-budget entry, but the
	/// firmware's own `config.proto` comments describe each as having a link budget
	/// "comparable to" one of the eight published presets — so those map onto the
	/// sensitivity of the preset they're documented as comparable to, rather than a
	/// guessed number:
	/// - `LITE_FAST`: "Comparable link budget to MEDIUM_FAST"
	/// - `LITE_SLOW`: "Comparable link budget to LONG_FAST"
	/// - `NARROW_FAST`: "Comparable link budget to SHORT_SLOW, but with half the data rate"
	/// - `NARROW_SLOW`: "Comparable link budget and data rate to LONG_FAST"
	/// - `TINY_FAST`: "Comparable link budget and data rate to LONG_FAST"
	/// - `TINY_SLOW`: "Comparable link budget and data rate to LONG_MODERATE"
	static func receiverSensitivityDBm(for preset: ModemPresets) -> Double {
		switch preset {
		case .shortTurbo: return -118.0   // SF7 / 500kHz / 4:5, link budget 140dB
		case .shortFast: return -121.0    // SF7 / 250kHz / 4:5, link budget 143dB
		case .shortSlow: return -123.5    // SF8 / 250kHz / 4:5, link budget 145.5dB
		case .medFast: return -126.0      // SF9 / 250kHz / 4:5, link budget 148dB
		case .medSlow: return -128.5      // SF10 / 250kHz / 4:5, link budget 150.5dB
		case .longTurbo: return -128.0    // SF11 / 500kHz / 4:8, link budget 150dB
		case .longFast: return -131.0     // SF11 / 250kHz / 4:5, link budget 153dB
		case .longModerate: return -134.0 // SF11 / 125kHz / 4:8, link budget 156dB
		case .longSlow: return -136.5     // SF12 / 125kHz / 4:8, link budget 158.5dB (deprecated preset)
		case .liteFast: return -126.0     // comparable to medFast, per config.proto
		case .liteSlow: return -131.0     // comparable to longFast, per config.proto
		case .narrowFast: return -123.5   // comparable to shortSlow, per config.proto
		case .narrowSlow: return -131.0   // comparable to longFast, per config.proto
		case .tinyFast: return -131.0     // comparable to longFast, per config.proto
		case .tinySlow: return -134.0     // comparable to longModerate, per config.proto
		}
	}

	/// Regulatory maximum transmit power in watts for a region, used to resolve the
	/// firmware's `txPower == 0` ("use max legal continuous power") sentinel into an
	/// actual number for the Site Planner's `tx_power` field.
	///
	/// Only regions with a verifiable regulatory figure are hardcoded; the firmware's
	/// *actual* per-region max (which also accounts for hardware limits, not just legal
	/// ones) lives in the `meshtastic/firmware` C++ source, which is out of scope to
	/// fetch for this helper. For every other region this deliberately falls back to
	/// `0.1` W — the Site Planner's own factory default for `tx_power` (research.md §2)
	/// — rather than inventing a number: an unverified guess would be worse than
	/// reusing the same default the remote tool falls back to when nothing is specified.
	static func regionMaxPowerWatts(for region: RegionCodes) -> Double {
		switch region {
		case .us, .anz, .anz433:
			return 1.0 // FCC Part 15.247 (US) / equivalent ISM rules: 1 W conducted in the 902-928 MHz band.
		case .eu868, .eu866, .euN868, .ua868, .ru, .np865, .nz865:
			return 0.025 // ETSI EN 300 220 SRD band, 868 MHz: 25 mW ERP.
		case .eu433, .ua433, .my433, .ph433, .kz433:
			return 0.01 // ETSI EN 300 220 SRD band, 433 MHz: 10 mW ERP.
		default:
			return 0.1 // No verified regional figure — Site Planner's own factory default, not a guess.
		}
	}

	/// Resolves the firmware's `txPower` sentinel (`0` = "use region max") to an actual
	/// wattage for the Site Planner's `tx_power` query field. A non-zero `txPower` is a
	/// dBm value from the radio's own config and is converted directly.
	static func transmitPowerWatts(txPowerDBm: Int32, region: RegionCodes) -> Double {
		guard txPowerDBm != 0 else {
			return regionMaxPowerWatts(for: region)
		}
		return pow(10.0, Double(txPowerDBm) / 10.0) / 1000.0
	}
}
