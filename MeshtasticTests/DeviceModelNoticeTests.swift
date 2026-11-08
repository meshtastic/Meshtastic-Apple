//
//  DeviceModelNoticeTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/8/26.
//

import Foundation
import Testing
@testable import Meshtastic

@Suite("Device model copyright notice")
struct DeviceModelNoticeTests {

	private func notice(_ name: String) throws -> String? {
		let url = try #require(Bundle.main.url(forResource: name, withExtension: "usdz"))
		return DeviceModelNotice.copyright(inUSDZ: url)
	}

	@Test("A device model carries the 3d-assets notice in full")
	func deviceModel() throws {
		let text = try #require(try notice("rak4631"))
		#expect(text.hasPrefix("Copyright © 2026 Meshtastic LLC."))
		#expect(text.contains("not covered by the GNU GPLv3"))
		#expect(text.hasSuffix("grants no right to either."))
	}

	@Test("Chirpy carries his own notice")
	func chirpy() throws {
		let text = try #require(try notice(DeviceModelCatalog.chirpy))
		#expect(text.contains("Chirpy"))
	}

	@Test("Every bundled device model has a notice")
	func everyBundledModel() throws {
		for name in DeviceModelCatalog.modelNames {
			guard let url = Bundle.main.url(forResource: name, withExtension: "usdz") else { continue }
			#expect(DeviceModelNotice.copyright(inUSDZ: url) != nil, "\(name)")
		}
	}

	@Test("A model without a notice, or a file that isn't a model, has none")
	func noNotice() throws {
		#expect(try notice("banana_for_scale") == nil)
		#expect(DeviceModelNotice.copyright(inUSDZData: Data("not a model".utf8)) == nil)
		#expect(DeviceModelNotice.copyright(inUSDZData: Data()) == nil)
	}
}
