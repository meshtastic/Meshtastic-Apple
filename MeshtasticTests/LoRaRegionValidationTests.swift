//
//  LoRaRegionValidationTests.swift
//  MeshtasticTests
//

import Testing
@testable import Meshtastic

@Suite("LoRa region validation")
struct LoRaRegionValidationTests {

	@Test("Known regions can be saved")
	func knownRegionIsSupported() {
		#expect(LoRaRegionValidation.supportedRegion(rawValue: RegionCodes.us.rawValue) == .us)
	}

	@Test("Unknown regions cannot be saved")
	func unknownRegionIsUnsupported() {
		#expect(LoRaRegionValidation.supportedRegion(rawValue: Int.max) == nil)
	}
}
