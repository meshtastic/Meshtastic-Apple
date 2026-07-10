// MARK: CoverageQueryURLBuilderTests
//
//  Locks down the exact query-key names and the omission rule from
//  specs/015-site-planner-outbound/contracts/query-contract.md.
//

import Testing
import Foundation
@testable import Meshtastic

@Suite("CoverageQueryURLBuilder")
struct CoverageQueryURLBuilderTests {

	private func params() -> CoverageEstimateParameters {
		CoverageEstimateParameters(
			name: "U-District Solar",
			latitude: 47.6062,
			longitude: -122.3321,
			transmitPowerWatts: 0.1,
			transmitFrequencyMHz: 915
		)
	}

	private func queryItems(for params: CoverageEstimateParameters) -> [String: String] {
		let url = CoverageQueryURLBuilder.url(for: params)
		let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
		var result: [String: String] = [:]
		for item in components.queryItems ?? [] {
			result[item.name] = item.value
		}
		return result
	}

	@Test func baseURLIsCorrect() {
		let url = CoverageQueryURLBuilder.url(for: params())
		#expect(url.absoluteString.hasPrefix("https://site.meshtastic.org/?"))
	}

	@Test func requiredKeysAlwaysPresent() {
		let items = queryItems(for: params())
		for key in ["lat", "lon", "tx_power", "tx_freq", "tx_height", "tx_gain",
					"rx_sensitivity", "rx_height", "rx_loss", "max_range",
					"min_dbm", "max_dbm", "overlay_transparency", "color_scale",
					"radio_climate", "polarization", "run"] {
			#expect(items[key] != nil, "missing required key \(key)")
		}
	}

	@Test func runIsAlwaysOne() {
		#expect(queryItems(for: params())["run"] == "1")
	}

	@Test func noBridgeKeyEver() {
		// research.md §1: the shipped contract has no bridge=1 flag. Never add one.
		#expect(queryItems(for: params())["bridge"] == nil)
	}

	@Test func optionalKeysOmittedWhenNil() {
		var p = params()
		p.situationFraction = nil
		p.timeFraction = nil
		p.clutterHeightMeters = nil
		p.groundDielectric = nil
		p.groundConductivity = nil
		p.atmosphereBending = nil
		let items = queryItems(for: p)
		for key in ["situation_fraction", "time_fraction", "clutter_height",
					"ground_dielectric", "ground_conductivity", "atmosphere_bending"] {
			#expect(items[key] == nil, "\(key) should be omitted when unset")
		}
	}

	@Test func optionalKeysPresentWhenSet() {
		var p = params()
		p.situationFraction = 0.5
		p.clutterHeightMeters = 3.0
		let items = queryItems(for: p)
		#expect(items["situation_fraction"] == "0.5")
		#expect(items["clutter_height"] == "3")
	}

	@Test func highResOmittedByDefault() {
		#expect(queryItems(for: params())["high_res"] == nil)
	}

	@Test func highResPresentWhenTrue() {
		var p = params()
		p.highResolutionTerrain = true
		#expect(queryItems(for: p)["high_res"] == "1")
	}

	@Test func colorScaleUsesExactPlannerCasing() {
		var p = params()
		p.colorScale = .cmRMap
		#expect(queryItems(for: p)["color_scale"] == "CMRmap")
	}

	@Test func integerValuedDoublesSendNoDecimalPoint() {
		let items = queryItems(for: params())
		#expect(items["tx_freq"] == "915")
	}

	@Test func fractionalValuesUsePeriodDecimalRegardlessOfLocale() {
		var p = params()
		p.transmitPowerWatts = 0.1
		#expect(queryItems(for: p)["tx_power"] == "0.1")
	}

	@Test func nameIsIncludedWhenNonEmpty() {
		#expect(queryItems(for: params())["name"] == "U-District Solar")
	}
}
