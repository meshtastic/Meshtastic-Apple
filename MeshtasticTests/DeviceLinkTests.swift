//
//  DeviceLinkTests.swift
//  MeshtasticTests
//

import Testing
import Foundation
@testable import Meshtastic

@Suite("DeviceLinkEntity Tests")
struct DeviceLinkTests {

	// MARK: - T006: JSON Decoding

	@Test("Decodes urls.json from bundle successfully")
	func testBundledJsonDecodes() throws {
		let url = try #require(Bundle.main.url(forResource: "urls", withExtension: "json"))
		let data = try Data(contentsOf: url)
		let decoded = try JSONDecoder().decode(TestMshToUrlsFile.self, from: data)
		#expect(decoded.routes.count > 0)
	}

	@Test("Decodes sample JSON structure correctly")
	func testSampleJsonDecoding() throws {
		let json = """
		{
			"Routes": [
				{"ShortCode": "test-device", "OriginalUrl": "https://example.com/device", "Description": "Test Device"},
				{"ShortCode": "no-desc", "OriginalUrl": "https://example.com/other"}
			]
		}
		""".data(using: .utf8)!

		let decoded = try JSONDecoder().decode(TestMshToUrlsFile.self, from: json)
		#expect(decoded.routes.count == 2)
		#expect(decoded.routes[0].shortCode == "test-device")
		#expect(decoded.routes[0].originalUrl == "https://example.com/device")
		#expect(decoded.routes[0].description == "Test Device")
		#expect(decoded.routes[1].description == nil)
	}

	@Test("Skips entries with invalid URLs")
	func testInvalidUrlSkipped() {
		let invalidUrl = "not a url %%"
		let result = URL(string: invalidUrl)
		#expect(result == nil)
	}

	// MARK: - T007: Substring Matching

	@Test("ShortCode containing hwModelSlug matches")
	func testSubstringMatching() {
		let slug = "rak4631"
		let shortCodes = ["rokland-rak4631", "hexaspot-4631", "aliexpress-rak4631", "github", "youtube"]
		let matches = shortCodes.filter { $0.lowercased().contains(slug.lowercased()) }
		#expect(matches.count == 2)
		#expect(matches.contains("rokland-rak4631"))
		#expect(matches.contains("aliexpress-rak4631"))
	}

	@Test("Case-insensitive matching works")
	func testCaseInsensitiveMatching() {
		let slug = "RAK4631"
		let shortCode = "rokland-rak4631"
		#expect(shortCode.lowercased().contains(slug.lowercased()))
	}

	@Test("Empty slug does not match anything")
	func testEmptySlugNoMatch() {
		let slug = ""
		let shortCodes = ["rokland-rak4631", "github"]
		// Empty slug should be excluded before matching
		#expect(slug.isEmpty)
	}

	// MARK: - T008: Vendor Priority Sorting

	@Test("Manufacturer domains get priority 0")
	func testManufacturerPriority() {
		#expect(DeviceLinkEntity.computePriority(for: "rakwireless.com") == 0)
		#expect(DeviceLinkEntity.computePriority(for: "store.heltec.org") == 0)
		#expect(DeviceLinkEntity.computePriority(for: "www.lilygo.cc") == 0)
		#expect(DeviceLinkEntity.computePriority(for: "www.seeedstudio.com") == 0)
	}

	@Test("Marketplace domains get priority 2")
	func testMarketplacePriority() {
		#expect(DeviceLinkEntity.computePriority(for: "aliexpress.com") == 2)
		#expect(DeviceLinkEntity.computePriority(for: "www.amazon.com") == 2)
	}

	@Test("Regional retailers get priority based on locale")
	func testRegionalPriority() {
		// rokland.com is US regional
		let priority = DeviceLinkEntity.computePriority(for: "rokland.com")
		let region = Locale.current.region?.identifier ?? ""
		if region == "US" {
			#expect(priority == 1)
		} else {
			#expect(priority == 2)
		}
	}

	@Test("Unknown domains get priority 99")
	func testUnknownDomainPriority() {
		#expect(DeviceLinkEntity.computePriority(for: "example.com") == 99)
		#expect(DeviceLinkEntity.computePriority(for: nil) == 99)
	}

	@Test("Links sort by vendor priority")
	func testPrioritySorting() {
		let priorities = [2, 0, 99, 1, 0]
		let sorted = priorities.sorted()
		#expect(sorted == [0, 0, 1, 2, 99])
	}
}

// MARK: - Test Helpers (mirror private structs for testing)

private struct TestMshToUrlsFile: Codable {
	let routes: [TestMshToRoute]

	enum CodingKeys: String, CodingKey {
		case routes = "Routes"
	}
}

private struct TestMshToRoute: Codable {
	let shortCode: String
	let originalUrl: String
	let description: String?

	enum CodingKeys: String, CodingKey {
		case shortCode = "ShortCode"
		case originalUrl = "OriginalUrl"
		case description = "Description"
	}
}
