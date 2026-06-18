//
//  DeviceLinkTests.swift
//  MeshtasticTests
//

import Testing
import SwiftData
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
		#expect(mp.regions.contains("US"))
		#expect(!mp.regions.contains("DE"))
	}

	@Test("Worldwide marketplace and non-marketplace links both have empty regions")
	func testRegionSemantics() {
		// `regions` is intentionally non-optional (see issue #1949). The "is this a
		// marketplace?" distinction that `nil` used to carry now lives on `isMarketplace`.
		let worldwide = DeviceLinkEntity(shortCode: "aliexpress-rak4631", isMarketplace: true, targets: ["rak4631"], regions: [])
		let vendor = DeviceLinkEntity(shortCode: "rak4631", isVendor: true, targets: ["rak4631"])
		#expect(worldwide.isMarketplace)
		#expect(worldwide.regions.isEmpty)
		#expect(!vendor.isMarketplace)
		#expect(vendor.regions.isEmpty)
	}

	// MARK: - Visibility rule (DeviceLinkEntity.isVisible, used by DeviceLinksSection)

	@Test("Vendor link always shows for a matching target regardless of region")
	func testVendorAlwaysVisible() {
		let vendor = DeviceLinkEntity(shortCode: "rak4631", isVendor: true, targets: ["rak4631"])
		#expect(vendor.isVisible(forTarget: "rak4631", userRegion: "DE"))
		#expect(!vendor.isVisible(forTarget: "heltec_v3", userRegion: "DE"))
	}

	@Test("Worldwide marketplace (empty regions) shows in every region")
	func testWorldwideMarketplaceVisible() {
		let worldwide = DeviceLinkEntity(shortCode: "aliexpress-rak4631", isMarketplace: true, targets: ["rak4631"], regions: [])
		#expect(worldwide.isVisible(forTarget: "rak4631", userRegion: "US"))
		#expect(worldwide.isVisible(forTarget: "rak4631", userRegion: "JP"))
	}

	@Test("Region-gated marketplace only shows in listed regions")
	func testRegionGatedMarketplaceVisibility() {
		let mp = DeviceLinkEntity(shortCode: "rokland-rak4631", isMarketplace: true, targets: ["rak4631"], regions: ["US", "CA"])
		#expect(mp.isVisible(forTarget: "rak4631", userRegion: "US"))
		#expect(!mp.isVisible(forTarget: "rak4631", userRegion: "DE"))
	}
}

// MARK: - Persistence regression (issue #1949)

/// Guards the schema shape behind issue #1949: a `DeviceLinkEntity` whose `regions` was an
/// *optional* array of a value type (`[String]?`) could not be materialized by SwiftData/Core
/// Data, so `context.save()` crashed with "Could not materialize Objective-C class named
/// \"Array\" ... attribute named regions". Because sending a message flushes the shared
/// context, every send crashed. `regions` is now a non-optional `[String]`; these tests assert
/// that inserting links with `regions` populated and saving — alone, and alongside a
/// `MessageEntity` as a message send does — succeeds and round-trips. (The `[String]?` shape
/// no longer exists to be exercised; these lock in that the supported shape persists cleanly.)
@MainActor
@Suite("DeviceLink Persistence (issue #1949)")
struct DeviceLinkPersistenceTests {

	@Test("Saving a link with regions does not crash and round-trips")
	func testSavingLinkWithRegionsRoundTrips() throws {
		let context = ModelContext(sharedModelContainer)
		let code = "regression-1949-\(UUID().uuidString)"
		context.insert(DeviceLinkEntity(
			shortCode: code,
			originalUrl: "https://msh.to/\(code)",
			isMarketplace: true,
			targets: ["rak4631"],
			regions: ["US", "CA"]
		))

		// Before the fix this call crashed (uncatchable Objective-C exception).
		try context.save()

		let fetched = try context.fetch(FetchDescriptor<DeviceLinkEntity>(predicate: #Predicate { $0.shortCode == code }))
		#expect(fetched.count == 1)
		#expect(fetched.first?.regions == ["US", "CA"])
		#expect(fetched.first?.targets == ["rak4631"])
	}

	@Test("Empty and non-marketplace regions round-trip")
	func testEmptyAndNonMarketplaceRegionsRoundTrip() throws {
		let context = ModelContext(sharedModelContainer)
		let worldwideCode = "regression-1949-ww-\(UUID().uuidString)"
		let vendorCode = "regression-1949-v-\(UUID().uuidString)"
		context.insert(DeviceLinkEntity(shortCode: worldwideCode, isMarketplace: true, targets: ["x"], regions: []))
		context.insert(DeviceLinkEntity(shortCode: vendorCode, isVendor: true, targets: ["x"]))

		try context.save()

		let ww = try context.fetch(FetchDescriptor<DeviceLinkEntity>(predicate: #Predicate { $0.shortCode == worldwideCode })).first
		let vendor = try context.fetch(FetchDescriptor<DeviceLinkEntity>(predicate: #Predicate { $0.shortCode == vendorCode })).first
		#expect(ww?.regions == [])
		#expect(vendor?.regions == [])
	}

	/// Mirrors the issue #1949 crash path: links with `regions` are already in the store,
	/// then an unrelated entity is inserted and the context flushed — exactly what happens
	/// when a message is sent (`AccessoryManager.sendMessage` calls `context.save()`).
	@Test("Flushing the context alongside a message does not crash")
	func testFlushingContextWithMessageDoesNotCrash() throws {
		let context = ModelContext(sharedModelContainer)
		let code = "regression-1949-flush-\(UUID().uuidString)"
		context.insert(DeviceLinkEntity(shortCode: code, isMarketplace: true, targets: ["rak4631"], regions: ["US"]))
		try context.save()

		// Now insert a message and save again, as AccessoryManager.sendMessage does — this is
		// the flush that crashed in #1949 while a regions-bearing link was in the store.
		// Use a deterministic, distinctive id: messageId is @Attribute(.unique) and the
		// in-memory store is shared across suites, so a random id could collide (other suites
		// use small fixed ids like 1, 2, 12345, 70001).
		let messageId = Int64(UInt32.max) - 1949
		let message = MessageEntity()
		message.messageId = messageId
		message.messagePayload = "hello"
		context.insert(message)
		try context.save()

		let link = try context.fetch(FetchDescriptor<DeviceLinkEntity>(predicate: #Predicate { $0.shortCode == code })).first
		#expect(link?.regions == ["US"])
		let savedMessage = try context.fetch(FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.messageId == messageId })).first
		#expect(savedMessage?.messagePayload == "hello")
	}
}
