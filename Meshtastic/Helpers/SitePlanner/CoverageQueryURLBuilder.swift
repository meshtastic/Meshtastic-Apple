//
//  CoverageQueryURLBuilder.swift
//  Meshtastic
//
//  Builds the Site Planner "flat query contract" URL from a CoverageEstimateParameters —
//  see specs/015-site-planner-outbound/contracts/query-contract.md for the exact key list,
//  sourced from meshtastic-site-planner's src/permalink.ts (QUERY_NUM_FIELDS et al.).
//

import Foundation

enum CoverageQueryURLBuilder {

	static let baseURL = "https://site.meshtastic.org/"

	/// Builds the query URL for one estimate run. Only includes keys the caller actually
	/// set (optional fields left `nil` are omitted entirely so the planner's own factory
	/// defaults apply — contracts/query-contract.md's "Construction rule"). `run=1` is
	/// always included; there is no `bridge=1` key (research.md §1 — it doesn't exist in
	/// the shipped contract).
	static func url(for params: CoverageEstimateParameters) -> URL {
		var items: [URLQueryItem] = [
			.init(name: "lat", value: numberString(params.latitude)),
			.init(name: "lon", value: numberString(params.longitude)),
			.init(name: "tx_power", value: numberString(params.transmitPowerWatts)),
			.init(name: "tx_freq", value: numberString(params.transmitFrequencyMHz)),
			.init(name: "tx_height", value: numberString(params.antennaHeightMeters)),
			.init(name: "tx_gain", value: numberString(params.antennaGainDBi)),
			.init(name: "rx_sensitivity", value: numberString(params.receiverSensitivityDBm)),
			.init(name: "rx_height", value: numberString(params.receiverHeightMeters)),
			.init(name: "rx_loss", value: numberString(params.receiverLossDB)),
			.init(name: "max_range", value: numberString(params.maxRangeKm)),
			.init(name: "min_dbm", value: numberString(params.minDBm)),
			.init(name: "max_dbm", value: numberString(params.maxDBm)),
			.init(name: "overlay_transparency", value: numberString(params.overlayTransparencyPercent)),
			.init(name: "color_scale", value: params.colorScale.queryValue),
			.init(name: "radio_climate", value: params.radioClimate.queryValue),
			.init(name: "polarization", value: params.polarization.queryValue)
		]

		if !params.name.isEmpty {
			items.append(.init(name: "name", value: params.name))
		}
		if params.highResolutionTerrain {
			items.append(.init(name: "high_res", value: "1"))
		}
		if let situationFraction = params.situationFraction {
			items.append(.init(name: "situation_fraction", value: numberString(situationFraction)))
		}
		if let timeFraction = params.timeFraction {
			items.append(.init(name: "time_fraction", value: numberString(timeFraction)))
		}
		if let clutterHeight = params.clutterHeightMeters {
			items.append(.init(name: "clutter_height", value: numberString(clutterHeight)))
		}
		if let groundDielectric = params.groundDielectric {
			items.append(.init(name: "ground_dielectric", value: numberString(groundDielectric)))
		}
		if let groundConductivity = params.groundConductivity {
			items.append(.init(name: "ground_conductivity", value: numberString(groundConductivity)))
		}
		if let atmosphereBending = params.atmosphereBending {
			items.append(.init(name: "atmosphere_bending", value: numberString(atmosphereBending)))
		}

		// Always last, always present — this run exists to autorun, never to sit idle.
		items.append(.init(name: "run", value: "1"))

		var components = URLComponents(string: baseURL)!
		components.queryItems = items
		return components.url!
	}

	/// Plain decimal string, locale-independent (`en_US_POSIX`) — a query parameter must
	/// use `.` as the decimal separator regardless of the device's locale, unlike the
	/// user-facing form fields this feeds from (which do respect locale, per the Design
	/// Standards §10 findings in research.md §6).
	private static func numberString(_ value: Double) -> String {
		if value == value.rounded() && abs(value) < 1e15 {
			return String(Int64(value))
		}
		let formatter = NumberFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.numberStyle = .decimal
		formatter.minimumFractionDigits = 0
		formatter.maximumFractionDigits = 8
		formatter.usesGroupingSeparator = false
		return formatter.string(from: NSNumber(value: value)) ?? String(value)
	}
}
