// SitePlannerParametersTests.swift
// MeshtasticTests
//
// Locks down the Site Planner flat-query contract (meshtastic/Meshtastic-Apple#2058):
// the query-URL builder, validation bounds, and radio prefill (dBm→W, preset→sensitivity,
// firmware-accurate frequency).

import Testing
import Foundation
import CoreLocation
@testable import Meshtastic

@Suite("SitePlannerParameters")
struct SitePlannerParametersTests {

	private func queryItems(_ url: URL?) -> [String: String] {
		guard let url, let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [:] }
		var dict: [String: String] = [:]
		for item in comps.queryItems ?? [] {
			dict[item.name] = item.value
		}
		return dict
	}

	// MARK: - Query URL

	@Test func buildsFlatQueryWithAutorunAndBridge() throws {
		var params = SitePlannerParameters()
		params.name = "Hill Site"
		params.latitude = 47.6062
		params.longitude = -122.3321
		params.txPowerWatts = 0.1
		params.txFrequencyMHz = 906.875
		params.txHeightMeters = 2
		params.txGainDBi = 2
		params.rxSensitivityDBm = -139
		params.maxRangeKm = 30
		params.colorScale = .viridis

		let url = params.queryURL(autorun: true, bridge: true)
		let items = queryItems(url)

		#expect(url?.absoluteString.hasPrefix("https://site.meshtastic.org/?") == true)
		#expect(items["lat"] == "47.6062")
		#expect(items["lon"] == "-122.3321")
		#expect(items["name"] == "Hill Site")
		#expect(items["tx_power"] == "0.1")
		#expect(items["tx_freq"] == "906.875")
		#expect(items["tx_height"] == "2")   // integer-valued → no trailing .0
		#expect(items["tx_gain"] == "2")
		#expect(items["rx_sensitivity"] == "-139")
		#expect(items["max_range"] == "30")
		#expect(items["color_scale"] == "viridis")
		#expect(items["run"] == "1")
		#expect(items["bridge"] == "1")
	}

	@Test func omitsAutorunBridgeHighResAndEmptyNameWhenNotSet() throws {
		var params = SitePlannerParameters()
		params.latitude = 10
		params.longitude = 10
		params.name = "   " // whitespace only

		let items = queryItems(params.queryURL(autorun: false, bridge: false))
		#expect(items["run"] == nil)
		#expect(items["bridge"] == nil)
		#expect(items["high_res"] == nil)
		#expect(items["name"] == nil)
	}

	@Test func includesHighResWhenEnabled() throws {
		var params = SitePlannerParameters()
		params.latitude = 10
		params.longitude = 10
		params.highResolution = true
		params.maxRangeKm = 70

		let items = queryItems(params.queryURL())
		#expect(items["high_res"] == "1")
	}

	@Test func percentEncodesName() throws {
		var params = SitePlannerParameters()
		params.latitude = 1
		params.longitude = 1
		params.name = "A & B / C"

		let url = params.queryURL()
		// The raw query string must not contain a bare `&` or `/` from the name.
		let raw = url?.query ?? ""
		#expect(raw.contains("name=A%20%26%20B%20/%20C") || raw.contains("name=A%20%26%20B%20%2F%20C"))
		// And decoded round-trips back to the original.
		#expect(queryItems(url)["name"] == "A & B / C")
	}

	// MARK: - Validation

	@Test func zeroZeroCoordinateIsInvalid() {
		var params = SitePlannerParameters()
		params.latitude = 0
		params.longitude = 0
		#expect(params.hasValidCoordinate == false)
		#expect(params.isValid == false)
	}

	@Test func outOfRangeFieldsAreInvalid() {
		var params = SitePlannerParameters()
		params.latitude = 45
		params.longitude = 45
		params.txFrequencyMHz = 5  // below 20 MHz floor
		#expect(params.isValid == false)

		params.txFrequencyMHz = 907
		params.rxSensitivityDBm = -200 // below -150
		#expect(params.isValid == false)
	}

	@Test func highResClampsMaxRangeBounds() {
		var params = SitePlannerParameters()
		params.latitude = 45
		params.longitude = 45
		params.highResolution = true
		params.maxRangeKm = 120 // >70 with high-res
		#expect(params.isValid == false)
		params.maxRangeKm = 70
		#expect(params.isValid == true)
	}

	// MARK: - Prefill

	@Test func wattsFromDBmConversion() {
		#expect(abs(SitePlannerParameters.watts(fromDBm: 30) - 1.0) < 1e-9)
		#expect(abs(SitePlannerParameters.watts(fromDBm: 20) - 0.1) < 1e-9)
		#expect(abs(SitePlannerParameters.watts(fromDBm: 27) - 0.5011872336) < 1e-6)
	}

	@Test func rxSensitivityTableMatchesPlanner() {
		#expect(SitePlannerParameters.rxSensitivity(for: .longFast) == -139)
		#expect(SitePlannerParameters.rxSensitivity(for: .shortFast) == -129)
		#expect(SitePlannerParameters.rxSensitivity(for: .longSlow) == -144.5)
		// Unmapped preset falls back to the planner default.
		#expect(SitePlannerParameters.rxSensitivity(for: .tinyFast) == -130)
	}

	@MainActor
	@Test func prefillFromRadioConfig() {
		let config = LoRaConfigEntity()
		config.regionCode = Int32(RegionCodes.us.rawValue)
		config.modemPreset = Int32(ModemPresets.longFast.rawValue)
		config.usePreset = true
		config.txPower = 27           // dBm
		config.channelNum = 20        // pins the frequency slot

		let coord = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)
		let params = SitePlannerParameters.prefilled(
			name: "Base",
			coordinate: coord,
			loRaConfig: config,
			primaryChannelName: "LongFast"
		)

		#expect(params.name == "Base")
		#expect(params.latitude == 47.6)
		#expect(params.longitude == -122.3)
		#expect(abs(params.txPowerWatts - SitePlannerParameters.watts(fromDBm: 27)) < 1e-9)
		#expect(params.rxSensitivityDBm == -139)
		// US LongFast slot 20 → 902 + 0.125 + 19*0.25 = 906.875 MHz.
		#expect(abs(params.txFrequencyMHz - 906.875) < 1e-6)
	}

	@MainActor
	@Test func prefillKeepsDefaultsWhenTxPowerIsRegionMax() {
		let config = LoRaConfigEntity()
		config.regionCode = Int32(RegionCodes.us.rawValue)
		config.modemPreset = Int32(ModemPresets.longFast.rawValue)
		config.usePreset = true
		config.txPower = 0 // firmware "0 = region max" — can't resolve, keep default

		let params = SitePlannerParameters.prefilled(
			name: "",
			coordinate: nil,
			loRaConfig: config,
			primaryChannelName: "LongFast"
		)
		#expect(params.txPowerWatts == 0.1) // planner default preserved
	}
}
