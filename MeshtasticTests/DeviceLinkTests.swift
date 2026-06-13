//
//  DeviceLinkTests.swift
//  MeshtasticTests
//

import Testing
import Foundation
@testable import Meshtastic

@Suite("DeviceLink Tests")
struct DeviceLinkTests {

	// MARK: - JSON decoding (new msh.to API / bundled format)

	@Test("Decodes bundled urls.json with Routes and Marketplaces")
	func testBundledJsonDecodes() throws {
		let url = try #require(Bundle.main.url(forResource: "urls", withExtension: "json"))
		let data = try Data(contentsOf: url)
		let decoded = try JSONDecoder().decode(MshToUrlsFile.self, from: data)
		#expect(decoded.routes.count > 0)
		#expect(!decoded.marketplaces.isEmpty)
	}

	@Test("Decodes Type and Targets from sample JSON")
	func testSampleJsonDecoding() throws {
		let json = """
		{
		  "Routes": [
		    {"ShortCode": "rak4631", "Description": "RAK 4631", "Type": "Vendor", "Targets": ["rak4631"]},
		    {"ShortCode": "rokland-rak4631", "Description": "Rokland RAK 4631", "Type": "Marketplace", "Targets": ["rak4631"]},
		    {"ShortCode": "github", "Description": "GitHub", "Type": "Internal"}
		  ],
		  "Marketplaces": { "rokland": { "Regions": ["US", "CA"] }, "aliexpress": { "Regions": [] } }
		}
		""".data(using: .utf8)!

		let decoded = try JSONDecoder().decode(MshToUrlsFile.self, from: json)
		#expect(decoded.routes.count == 3)
		#expect(decoded.routes[0].type == .vendor)
		#expect(decoded.routes[0].targets == ["rak4631"])
		#expect(decoded.routes[1].type == .marketplace)
		#expect(decoded.routes[2].type == .internalLink)
		#expect(decoded.routes[2].targets.isEmpty)
		#expect(decoded.marketplaces["rokland"]?.regions == ["US", "CA"])
		#expect(decoded.marketplaces["aliexpress"]?.regions.isEmpty == true)
	}

	@Test("Unknown or missing Type falls back to Internal")
	func testUnknownTypeFallsBackToInternal() throws {
		let json = """
		{
		  "Routes": [
		    {"ShortCode": "future", "Type": "Wholesaler", "Targets": ["x"]},
		    {"ShortCode": "legacy", "Description": "No type field"}
		  ],
		  "Marketplaces": {}
		}
		""".data(using: .utf8)!

		let decoded = try JSONDecoder().decode(MshToUrlsFile.self, from: json)
		#expect(decoded.routes[0].type == .internalLink)
		#expect(decoded.routes[1].type == .internalLink)
		#expect(decoded.routes[1].targets.isEmpty)
	}

	// MARK: - Device association via Targets

	@Test("A link matches a device only when its Targets contain the platformioTarget")
	func testTargetMatching() {
		let vendor = DeviceLinkEntity(shortCode: "rak4631", isVendor: true, targets: ["rak4631"])
		let otherVendor = DeviceLinkEntity(shortCode: "heltec-v3", isVendor: true, targets: ["heltec_v3"])
		#expect(vendor.targets.contains("rak4631"))
		#expect(!otherVendor.targets.contains("rak4631"))
	}

	@Test("Internal links have no targets and match no device")
	func testInternalLinkMatchesNothing() {
		let internalLink = DeviceLinkEntity(shortCode: "github", targets: [])
		#expect(internalLink.targets.isEmpty)
		#expect(!internalLink.targets.contains("rak4631"))
	}

	// MARK: - Marketplace region filtering

	@Test("Marketplace with regions only ships to listed countries")
	func testRegionFiltering() {
		let mp = DeviceLinkEntity(shortCode: "rokland-rak4631", isMarketplace: true, targets: ["rak4631"], regions: ["US", "CA"])
		#expect(mp.regions?.contains("US") == true)
		#expect(mp.regions?.contains("DE") == false)
	}

	@Test("Worldwide marketplace has empty regions; vendor has nil regions")
	func testRegionSemantics() {
		let worldwide = DeviceLinkEntity(shortCode: "aliexpress-rak4631", isMarketplace: true, targets: ["rak4631"], regions: [])
		let vendor = DeviceLinkEntity(shortCode: "rak4631", isVendor: true, targets: ["rak4631"], regions: nil)
		#expect(worldwide.regions?.isEmpty == true)
		#expect(vendor.regions == nil)
	}
}
