//
//  CoverageEstimateParameters.swift
//  Meshtastic
//
//  The transient (never persisted) parameter set for one Site Planner coverage
//  estimate run — see specs/015-site-planner-outbound/data-model.md. Enum cases
//  and their query-string values are sourced from meshtastic-site-planner's own
//  `src/engine/params.ts` (CLIMATE_CODES, POLARIZATION_CODES) and
//  `src/render/colormaps.ts` (COLORMAP_NAMES) — not invented.
//

import Foundation

/// ITM radio climate, per `meshtastic-site-planner`'s `CLIMATE_CODES`.
enum RadioClimate: String, CaseIterable, Identifiable {
	case equatorial
	case continentalSubtropical
	case maritimeSubtropical
	case desert
	case continentalTemperate
	case maritimeTemperateLand
	case maritimeTemperateSea

	var id: String { queryValue }

	/// The exact string this must be sent as — matches the planner's `CLIMATE_CODES` keys.
	var queryValue: String {
		switch self {
		case .equatorial: return "equatorial"
		case .continentalSubtropical: return "continental_subtropical"
		case .maritimeSubtropical: return "maritime_subtropical"
		case .desert: return "desert"
		case .continentalTemperate: return "continental_temperate"
		case .maritimeTemperateLand: return "maritime_temperate_land"
		case .maritimeTemperateSea: return "maritime_temperate_sea"
		}
	}

	/// The planner's own factory default (`continental_temperate`) when nothing is specified.
	static let `default` = RadioClimate.continentalTemperate
}

/// Antenna polarization, per `meshtastic-site-planner`'s `POLARIZATION_CODES`.
enum Polarization: String, CaseIterable, Identifiable {
	case horizontal
	case vertical

	var id: String { rawValue }
	var queryValue: String { rawValue }

	static let `default` = Polarization.vertical
}

/// Coverage overlay color palette, per `meshtastic-site-planner`'s `COLORMAP_NAMES`
/// (the `HEX_LUTS` keys in `src/render/colormaps.ts`) — exactly six values, no more.
enum ColorScale: String, CaseIterable, Identifiable {
	case plasma
	case viridis
	case cmRMap
	case cool
	case turbo
	case jet

	var id: String { queryValue }

	/// The exact string this must be sent as — `CMRmap` is mixed-case in the planner's
	/// own list, unlike every other value.
	var queryValue: String {
		switch self {
		case .cmRMap: return "CMRmap"
		default: return rawValue
		}
	}

	static let `default` = ColorScale.plasma
}

/// One user-configured Site Planner coverage estimate request. Grouped exactly like
/// the flat query contract's sections (contracts/query-contract.md) so the form's
/// section layout maps 1:1 onto this type.
struct CoverageEstimateParameters {

	// MARK: Site / Transmitter
	/// The site name sent to the planner (→ `properties.name` on the exported GeoJSON).
	/// Friendly (e.g. the node's long name); distinct from the overlay/file name — see
	/// `overlayName(date:)`.
	var name: String
	/// Stable identifier for the estimated site — the node's hex id (`!a1b2c3d4`) when
	/// estimated from a node (US1), `nil` from the map entry point (US2, no node). Drives
	/// the overlay/file name so stored coverage maps are identifiable per-node.
	var siteIdentifier: String?
	var latitude: Double
	var longitude: Double
	var transmitPowerWatts: Double
	var transmitFrequencyMHz: Double
	var antennaHeightMeters: Double = 2
	var antennaGainDBi: Double = 2

	// MARK: Receiver
	var receiverSensitivityDBm: Double = -130
	var receiverHeightMeters: Double = 1
	var receiverLossDB: Double = 2

	// MARK: Simulation
	var maxRangeKm: Double = 30
	var highResolutionTerrain: Bool = false
	var situationFraction: Double?
	var timeFraction: Double?

	// MARK: Environment (advanced)
	var clutterHeightMeters: Double?
	var groundDielectric: Double?
	var groundConductivity: Double?
	var atmosphereBending: Double?
	var radioClimate: RadioClimate = .default
	var polarization: Polarization = .default

	// MARK: Display
	var minDBm: Double = -130
	var maxDBm: Double = -80
	var overlayTransparencyPercent: Double = 50
	var colorScale: ColorScale = .default

	init(
		name: String,
		latitude: Double,
		longitude: Double,
		transmitPowerWatts: Double,
		transmitFrequencyMHz: Double
	) {
		self.name = name
		self.latitude = latitude
		self.longitude = longitude
		self.transmitPowerWatts = transmitPowerWatts
		self.transmitFrequencyMHz = transmitFrequencyMHz
	}
}

// MARK: - Validation (data-model.md "Validation rules")

enum CoverageEstimateValidationError: LocalizedError, Equatable {
	case missingPosition
	case receiverSensitivityOutOfRange
	case maxRangeExceedsCap(highResCapKm: Double, standardCapKm: Double)

	var errorDescription: String? {
		switch self {
		case .missingPosition:
			return "A site position is required before running a coverage estimate.".localized
		case .receiverSensitivityOutOfRange:
			return "Receiver sensitivity must be between -150 and -30 dBm.".localized
		case .maxRangeExceedsCap(let highResCap, let standardCap):
			return String(
				format: "Max range must be %.0f km or less (%.0f km with high-resolution terrain).".localized,
				standardCap, highResCap
			)
		}
	}
}

extension CoverageEstimateParameters {

	private static let receiverSensitivityRange: ClosedRange<Double> = -150...(-30)
	private static let standardMaxRangeKm: Double = 150
	private static let highResMaxRangeKm: Double = 70

	/// The name for the imported coverage overlay: the node id when estimated from a node
	/// (US1), otherwise the site name (US2, map entry point), suffixed with the estimate
	/// `date`. `date` is injected rather than read from `Date()` so this stays unit-testable.
	///
	/// Date-only, `yyyy-MM-dd`, formatted with a fixed POSIX locale — this is a stored file
	/// identifier (sortable, filesystem-safe, stable), deliberately NOT the OS-locale date
	/// format that governs *displayed* dates (Design Standards §10.6).
	func overlayName(date: Date) -> String {
		let base = (siteIdentifier?.isEmpty == false ? siteIdentifier! : name)
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "yyyy-MM-dd"
		return "\(base) \(formatter.string(from: date))"
	}

	/// Every validation failure for the current values, per data-model.md. Empty means
	/// the parameters are safe to send.
	func validationErrors() -> [CoverageEstimateValidationError] {
		var errors: [CoverageEstimateValidationError] = []

		if !CLLocationCoordinate2DIsValid(latitude: latitude, longitude: longitude) {
			errors.append(.missingPosition)
		}
		if !Self.receiverSensitivityRange.contains(receiverSensitivityDBm) {
			errors.append(.receiverSensitivityOutOfRange)
		}
		let cap = highResolutionTerrain ? Self.highResMaxRangeKm : Self.standardMaxRangeKm
		if maxRangeKm > cap {
			errors.append(.maxRangeExceedsCap(highResCapKm: Self.highResMaxRangeKm, standardCapKm: Self.standardMaxRangeKm))
		}

		return errors
	}

	var isValid: Bool { validationErrors().isEmpty }

	/// `(0, 0)` is technically decodable but never a real transmitter site in this app
	/// (no node legitimately sits at the null island) — treated as "no position set."
	private func CLLocationCoordinate2DIsValid(latitude: Double, longitude: Double) -> Bool {
		guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return false }
		return latitude != 0 || longitude != 0
	}
}
