//
//  SitePlannerParameters.swift
//  Meshtastic
//
//  The inputs to an in-app coverage estimate. Defaults and names follow the
//  Meshtastic Site Planner (https://site.meshtastic.org), so an estimate here
//  and one there start from the same transmitter.
//

import Foundation
import CoreLocation

/// The coverage-map colour palette. Raw values are the planner's colormap names.
enum SitePlannerColorScale: String, CaseIterable, Identifiable, Hashable {
	case mesh
	case plasma
	case viridis
	case cmrmap = "CMRmap"
	case cool
	case turbo
	case jet

	var id: String { rawValue }

	/// Human-facing palette name for the picker.
	var displayName: String {
		switch self {
		case .mesh: return "Mesh"
		case .plasma: return "Plasma"
		case .viridis: return "Viridis"
		case .cmrmap: return "CMRmap"
		case .cool: return "Cool"
		case .turbo: return "Turbo"
		case .jet: return "Jet"
		}
	}
}

/// An in-app coverage-estimate request, mirroring the planner's `Site Parameters`
/// panels, with the planner's defaults.
struct SitePlannerParameters: Equatable, Sendable {

	// MARK: Site / Transmitter
	var name: String = ""
	var latitude: Double = 0
	var longitude: Double = 0
	/// Transmit power in **watts** (wire unit). Planner default 0.1 W (30 dBm).
	var txPowerWatts: Double = 0.1
	/// Centre frequency in MHz. Planner default 907.
	var txFrequencyMHz: Double = 907
	/// Antenna height above ground in metres. Planner default 2.
	var txHeightMeters: Double = 2
	/// Antenna gain in dBi. Planner default 2.
	var txGainDBi: Double = 2

	// MARK: Receiver
	/// Receiver sensitivity / coverage threshold in dBm. Planner default -130.
	var rxSensitivityDBm: Double = -130
	/// Receiver antenna height above ground in metres. Default 1, a handheld.
	var rxHeightMeters: Double = 1

	// MARK: Simulation Options
	/// Maximum simulation range in km. Planner default 30; at most 150.
	var maxRangeKm: Double = 30

	// MARK: Display
	var colorScale: SitePlannerColorScale = .mesh

	// MARK: - Validation bounds
	/// ITU-R P.1812's range, which kp1812 enforces.
	static let frequencyRange: ClosedRange<Double> = 30...6000
	static let rxSensitivityRange: ClosedRange<Double> = -150...(-30)
	static let latitudeRange: ClosedRange<Double> = -90...90
	static let longitudeRange: ClosedRange<Double> = -180...180
	static let maxRangeBounds: ClosedRange<Double> = 1...150

	/// A `0,0` fix is the firmware's "no position" sentinel — never a valid transmitter.
	var hasValidCoordinate: Bool {
		guard Self.latitudeRange.contains(latitude), Self.longitudeRange.contains(longitude) else { return false }
		return !(latitude == 0 && longitude == 0)
	}

	/// Whether every field is inside the accepted ranges and coordinates are usable.
	var isValid: Bool {
		hasValidCoordinate
			&& txPowerWatts > 0
			&& Self.frequencyRange.contains(txFrequencyMHz)
			&& txHeightMeters >= 0
			&& Self.rxSensitivityRange.contains(rxSensitivityDBm)
			&& rxHeightMeters >= 0
			&& Self.maxRangeBounds.contains(maxRangeKm)
	}
}

// MARK: - Radio prefill

extension SitePlannerParameters {

	/// Watts from device transmit power in dBm: `W = 10^((dBm − 30) / 10)`.
	static func watts(fromDBm dBm: Double) -> Double {
		pow(10, (dBm - 30) / 10)
	}

	/// Receiver sensitivity (dBm) for a modem preset, per the planner's `parameters.md`
	/// per-preset table. Unmapped presets fall back to the planner default (-130).
	static func rxSensitivity(for preset: ModemPresets) -> Double {
		switch preset {
		case .shortTurbo: return -126
		case .shortFast: return -129
		case .shortSlow: return -131.5
		case .medFast: return -134
		case .medSlow: return -136.5
		case .longFast: return -139
		case .longModerate: return -142
		case .longSlow: return -144.5
		default: return -130
		}
	}

	/// Build parameters prefilled from the connected radio where possible:
	/// transmit frequency (computed primary-channel MHz), transmit power
	/// (device dBm → W, guarding the firmware "0 = region max" case) and a
	/// receiver sensitivity mapped from the modem preset. Antenna gain/height
	/// aren't in device config, so they keep the planner defaults.
	static func prefilled(
		name: String,
		coordinate: CLLocationCoordinate2D?,
		loRaConfig: LoRaConfigEntity?,
		primaryChannelName: String
	) -> SitePlannerParameters {
		var params = SitePlannerParameters()
		params.name = name
		if let coordinate {
			params.latitude = coordinate.latitude
			params.longitude = coordinate.longitude
		}

		guard let loRaConfig else { return params }

		// Frequency — reuse the firmware-accurate slot math.
		let calculator = LoRaChannelCalculator(config: loRaConfig)
		let slot = calculator.effectiveChannelSlot(primaryName: primaryChannelName)
		let frequency = calculator.radioFrequencyMHz(slot: slot)
		if frequency > 0 {
			params.txFrequencyMHz = frequency
		}

		// Transmit power — device stores dBm; 0 means "region max", which we can't
		// resolve here, so leave the planner default in that case.
		if loRaConfig.txPower > 0 {
			params.txPowerWatts = watts(fromDBm: Double(loRaConfig.txPower))
		}

		// Receiver sensitivity — from the modem preset when using a preset.
		if loRaConfig.usePreset, let preset = ModemPresets(rawValue: Int(loRaConfig.modemPreset)) {
			params.rxSensitivityDBm = rxSensitivity(for: preset)
		}

		return params
	}
}
