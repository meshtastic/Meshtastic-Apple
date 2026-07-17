//
//  SitePlannerParameters.swift
//  Meshtastic
//
//  The flat query contract used to drive the hosted Meshtastic Site Planner
//  (https://site.meshtastic.org) for an in-app coverage estimate. A partial
//  transmitter is merged over the planner's own defaults, so the app never needs
//  the planner's internal schema — it only sends the keys the user can edit.
//
//  Contract reference: meshtastic/Meshtastic-Apple#2058 and
//  meshtastic/meshtastic-site-planner#73 / #74.
//

import Foundation
import CoreLocation

/// The coverage-map colour palette (`color_scale` query key). Raw values are the
/// exact planner tokens; an unknown token falls back to `plasma` planner-side.
enum SitePlannerColorScale: String, CaseIterable, Identifiable, Hashable {
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
/// panels. Defaults equal a fresh planner session so an untouched form is a no-op
/// merge (see the Default column in the issue's flat-query contract table).
struct SitePlannerParameters: Equatable {

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

	// MARK: Simulation Options
	/// Maximum simulation range in km. Planner default 30; ≤150, or ≤70 with high-res.
	var maxRangeKm: Double = 30
	/// High-resolution terrain (30 m). Caps `maxRangeKm` at 70 when enabled.
	var highResolution: Bool = false

	// MARK: Display
	var colorScale: SitePlannerColorScale = .turbo

	// MARK: - Validation bounds (mirror the planner's `store.ts` / input ranges)
	static let frequencyRange: ClosedRange<Double> = 20...20_000
	static let rxSensitivityRange: ClosedRange<Double> = -150...(-30)
	static let latitudeRange: ClosedRange<Double> = -90...90
	static let longitudeRange: ClosedRange<Double> = -180...180
	static let maxRangeStandard: ClosedRange<Double> = 1...150
	static let maxRangeHighRes: ClosedRange<Double> = 1...70

	/// The allowed max-range span for the current high-res selection.
	var maxRangeBounds: ClosedRange<Double> {
		highResolution ? Self.maxRangeHighRes : Self.maxRangeStandard
	}

	/// A `0,0` fix is the firmware's "no position" sentinel — never a valid transmitter.
	var hasValidCoordinate: Bool {
		guard Self.latitudeRange.contains(latitude), Self.longitudeRange.contains(longitude) else { return false }
		return !(latitude == 0 && longitude == 0)
	}

	/// Whether every field is inside the planner's accepted ranges and coordinates are usable.
	var isValid: Bool {
		hasValidCoordinate
			&& txPowerWatts > 0
			&& Self.frequencyRange.contains(txFrequencyMHz)
			&& txHeightMeters >= 0
			&& Self.rxSensitivityRange.contains(rxSensitivityDBm)
			&& maxRangeBounds.contains(maxRangeKm)
	}

	// MARK: - Query URL

	/// The hosted planner base URL.
	static let plannerBaseURL = "https://site.meshtastic.org/"

	/// Builds `https://site.meshtastic.org/?<flat query>`.
	/// - Parameters:
	///   - autorun: append `run=1` so the planner computes on load (no click).
	///   - bridge: append `bridge=1` so a native embed delivers via the JS bridge
	///     instead of the share sheet.
	func queryURL(autorun: Bool = true, bridge: Bool = false) -> URL? {
		guard var components = URLComponents(string: Self.plannerBaseURL) else { return nil }

		var items: [URLQueryItem] = [
			URLQueryItem(name: "lat", value: Self.wire(latitude)),
			URLQueryItem(name: "lon", value: Self.wire(longitude)),
			URLQueryItem(name: "tx_power", value: Self.wire(txPowerWatts)),
			URLQueryItem(name: "tx_freq", value: Self.wire(txFrequencyMHz)),
			URLQueryItem(name: "tx_height", value: Self.wire(txHeightMeters)),
			URLQueryItem(name: "tx_gain", value: Self.wire(txGainDBi)),
			URLQueryItem(name: "rx_sensitivity", value: Self.wire(rxSensitivityDBm)),
			URLQueryItem(name: "max_range", value: Self.wire(maxRangeKm)),
			URLQueryItem(name: "color_scale", value: colorScale.rawValue)
		]

		let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
		if !trimmedName.isEmpty {
			// URLQueryItem percent-encodes the value for us.
			items.append(URLQueryItem(name: "name", value: trimmedName))
		}
		if highResolution {
			items.append(URLQueryItem(name: "high_res", value: "1"))
		}
		if autorun {
			items.append(URLQueryItem(name: "run", value: "1"))
		}
		if bridge {
			items.append(URLQueryItem(name: "bridge", value: "1"))
		}

		components.queryItems = items
		// URLComponents encodes `+` in a query value as a literal `+`, which the
		// planner would read as a space. None of our numeric values contain `+`,
		// and names are handled by URLQueryItem, so no extra escaping is needed.
		return components.url
	}

	/// Locale-independent numeric formatting for the wire (always a `.` decimal
	/// separator; integers render without a trailing `.0`).
	private static func wire(_ value: Double) -> String {
		if value == value.rounded() && abs(value) < 1e15 {
			return String(Int(value))
		}
		return String(value)
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
