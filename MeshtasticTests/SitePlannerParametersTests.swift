// SitePlannerParametersTests.swift
// MeshtasticTests
//
// Validation bounds and radio prefill for the coverage estimate (dBm→W, preset→sensitivity,
// firmware-accurate frequency).

import Testing
import Foundation
import CoreLocation
@testable import Meshtastic

@Suite("SitePlannerParameters")
struct SitePlannerParametersTests {

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
		params.txFrequencyMHz = 20  // below P.1812's 30 MHz floor
		#expect(params.isValid == false)

		params.txFrequencyMHz = 7000 // above its 6 GHz ceiling
		#expect(params.isValid == false)

		params.txFrequencyMHz = 907
		params.rxSensitivityDBm = -200 // below -150
		#expect(params.isValid == false)

		params.rxSensitivityDBm = -130
		params.rxHeightMeters = -1
		#expect(params.isValid == false)

		params.rxHeightMeters = 1
		params.maxRangeKm = 151
		#expect(params.isValid == false)
		params.maxRangeKm = 150
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
