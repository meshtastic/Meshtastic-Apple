// MARK: CoverageEstimateParametersTests
//
//  Locks down the validation rules from specs/015-site-planner-outbound/data-model.md,
//  and the exact query-string values for the enum types (sourced from
//  meshtastic-site-planner's CLIMATE_CODES / POLARIZATION_CODES / COLORMAP_NAMES).
//

import Testing
import Foundation
@testable import Meshtastic

@Suite("CoverageEstimateParameters")
struct CoverageEstimateParametersTests {

	private func validParams() -> CoverageEstimateParameters {
		CoverageEstimateParameters(
			name: "Test Site",
			latitude: 47.6062,
			longitude: -122.3321,
			transmitPowerWatts: 0.1,
			transmitFrequencyMHz: 915
		)
	}

	@Test func defaultParametersAreValid() {
		#expect(validParams().isValid)
	}

	@Test func missingPositionIsInvalid() {
		var params = validParams()
		params.latitude = 0
		params.longitude = 0
		#expect(params.validationErrors().contains(.missingPosition))
	}

	@Test func outOfRangeLatitudeIsInvalid() {
		var params = validParams()
		params.latitude = 91
		#expect(params.validationErrors().contains(.missingPosition))
	}

	@Test func receiverSensitivityWithinRangeIsValid() {
		var params = validParams()
		params.receiverSensitivityDBm = -150
		#expect(params.isValid)
		params.receiverSensitivityDBm = -30
		#expect(params.isValid)
	}

	@Test func receiverSensitivityOutOfRangeIsInvalid() {
		var params = validParams()
		params.receiverSensitivityDBm = -151
		#expect(params.validationErrors().contains(.receiverSensitivityOutOfRange))
		params.receiverSensitivityDBm = -29
		#expect(params.validationErrors().contains(.receiverSensitivityOutOfRange))
	}

	@Test func maxRangeWithinStandardCapIsValid() {
		var params = validParams()
		params.maxRangeKm = 150
		#expect(params.isValid)
	}

	@Test func maxRangeOverStandardCapIsInvalid() {
		var params = validParams()
		params.maxRangeKm = 151
		#expect(params.validationErrors().contains { if case .maxRangeExceedsCap = $0 { return true }; return false })
	}

	@Test func maxRangeOverHighResCapIsInvalid() {
		var params = validParams()
		params.highResolutionTerrain = true
		params.maxRangeKm = 71
		#expect(params.validationErrors().contains { if case .maxRangeExceedsCap = $0 { return true }; return false })
	}

	@Test func maxRangeAtHighResCapIsValid() {
		var params = validParams()
		params.highResolutionTerrain = true
		params.maxRangeKm = 70
		#expect(params.isValid)
	}

	// MARK: Enum query-string values (must match meshtastic-site-planner exactly)

	@Test func radioClimateQueryValues() {
		#expect(RadioClimate.equatorial.queryValue == "equatorial")
		#expect(RadioClimate.continentalSubtropical.queryValue == "continental_subtropical")
		#expect(RadioClimate.maritimeSubtropical.queryValue == "maritime_subtropical")
		#expect(RadioClimate.desert.queryValue == "desert")
		#expect(RadioClimate.continentalTemperate.queryValue == "continental_temperate")
		#expect(RadioClimate.maritimeTemperateLand.queryValue == "maritime_temperate_land")
		#expect(RadioClimate.maritimeTemperateSea.queryValue == "maritime_temperate_sea")
		#expect(RadioClimate.default == .continentalTemperate)
	}

	@Test func polarizationQueryValues() {
		#expect(Polarization.horizontal.queryValue == "horizontal")
		#expect(Polarization.vertical.queryValue == "vertical")
		#expect(Polarization.default == .vertical)
	}

	@Test func colorScaleQueryValues() {
		#expect(ColorScale.plasma.queryValue == "plasma")
		#expect(ColorScale.viridis.queryValue == "viridis")
		#expect(ColorScale.cmRMap.queryValue == "CMRmap")
		#expect(ColorScale.cool.queryValue == "cool")
		#expect(ColorScale.turbo.queryValue == "turbo")
		#expect(ColorScale.jet.queryValue == "jet")
		#expect(ColorScale.default == .plasma)
		#expect(ColorScale.allCases.count == 6)
	}
}
