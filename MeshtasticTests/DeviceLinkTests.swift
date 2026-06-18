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

// MARK: - SwiftData migration probe (drives the #1949 schema-versioning decision)
//
// These tests reproduce the exact `regions` change (optional `[String]?` -> non-optional
// `[String]`) in miniature on a REAL on-disk store, to empirically answer two questions the
// production fix depends on:
//   1. Does simply changing the property in place (same schema version, no migration plan) let
//      an existing store reopen, or does ModelContainer init THROW (which in production routes
//      into Persistence.swift's data-wiping recovery path)?
//   2. Does a bumped schema version + custom migration stage that drops the affected rows let
//      the store reopen cleanly while PRESERVING unrelated data?
//
// The three `Link` types are nested in enums so SwiftData gives them the same entity name
// ("Link") across versions — the same mechanism that makes DeviceLinkEntity one logical entity
// across schema versions.

enum MigProbeOld: VersionedSchema {
	static var versionIdentifier = Schema.Version(1, 0, 0)
	static var models: [any PersistentModel.Type] { [Link.self, Keeper.self] }

	@Model final class Link {
		@Attribute(.unique) var code: String = ""
		var regions: [String]?
		init(code: String = "", regions: [String]? = nil) { self.code = code; self.regions = regions }
	}
	/// Stand-in for unrelated user data (nodes/messages) that must survive any migration.
	@Model final class Keeper {
		@Attribute(.unique) var id: Int = 0
		var note: String = ""
		init(id: Int = 0, note: String = "") { self.id = id; self.note = note }
	}
}

/// Same version identifier as `MigProbeOld` but the new shape — mimics editing the model in
/// place without bumping the schema version (the current production diff).
enum MigProbeInPlace: VersionedSchema {
	static var versionIdentifier = Schema.Version(1, 0, 0)
	static var models: [any PersistentModel.Type] { [Link.self, Keeper.self] }

	@Model final class Link {
		@Attribute(.unique) var code: String = ""
		var regions: [String] = []
		init(code: String = "", regions: [String] = []) { self.code = code; self.regions = regions }
	}
	@Model final class Keeper {
		@Attribute(.unique) var id: Int = 0
		var note: String = ""
		init(id: Int = 0, note: String = "") { self.id = id; self.note = note }
	}
}

/// Bumped version with the new shape — the V2 approach.
enum MigProbeNew: VersionedSchema {
	static var versionIdentifier = Schema.Version(2, 0, 0)
	static var models: [any PersistentModel.Type] { [Link.self, Keeper.self] }

	@Model final class Link {
		@Attribute(.unique) var code: String = ""
		var regions: [String] = []
		init(code: String = "", regions: [String] = []) { self.code = code; self.regions = regions }
	}
	@Model final class Keeper {
		@Attribute(.unique) var id: Int = 0
		var note: String = ""
		init(id: Int = 0, note: String = "") { self.id = id; self.note = note }
	}
}

/// Faithful to the current production `MeshtasticMigrationPlan`: a single schema at the
/// unchanged version, no stages.
enum MigProbeInPlacePlan: SchemaMigrationPlan {
	static var schemas: [any VersionedSchema.Type] { [MigProbeInPlace.self] }
	static var stages: [MigrationStage] { [] }
}

enum MigProbePlan: SchemaMigrationPlan {
	static var schemas: [any VersionedSchema.Type] { [MigProbeOld.self, MigProbeNew.self] }
	static var stages: [MigrationStage] {
		[
			.custom(
				fromVersion: MigProbeOld.self,
				toVersion: MigProbeNew.self,
				willMigrate: { context in
					// Drop the affected rows via a batch delete (does NOT materialize the
					// un-materializable optional-array attribute) before the shape change applies.
					try? context.delete(model: MigProbeOld.Link.self)
					try? context.save()
				},
				didMigrate: nil
			)
		]
	}
}

@MainActor
@Suite("SwiftData optional-array migration probe (#1949)")
struct MigrationProbeTests {

	private func tempStoreURL() -> URL {
		URL.temporaryDirectory.appending(path: "migprobe-\(UUID().uuidString).store")
	}

	/// Writes an old-shape store (optional regions) with one Link and one Keeper.
	private func seedOldStore(at url: URL) throws {
		let container = try ModelContainer(
			for: MigProbeOld.Link.self, MigProbeOld.Keeper.self,
			configurations: ModelConfiguration(schema: Schema(versionedSchema: MigProbeOld.self), url: url)
		)
		let ctx = ModelContext(container)
		ctx.insert(MigProbeOld.Link(code: "rokland", regions: ["US", "CA"]))
		ctx.insert(MigProbeOld.Keeper(id: 1, note: "precious"))
		try ctx.save()
	}

	/// THE key safety guard for #1949: reopening a v2.7.13-shaped store (optional `regions`)
	/// with the new non-optional shape — same schema version, empty-stage plan, exactly the
	/// production diff — must NOT throw (a throw routes into Persistence.swift's data-wiping
	/// recovery), must preserve unrelated data, and must preserve the stored region values.
	@Test("In-place optional->non-optional reopen is non-destructive (no version bump)")
	func testInPlaceReopenPreservesData() throws {
		let url = tempStoreURL()
		try seedOldStore(at: url)

		let container = try ModelContainer(
			for: MigProbeInPlace.Link.self, MigProbeInPlace.Keeper.self,
			migrationPlan: MigProbeInPlacePlan.self,
			configurations: ModelConfiguration(schema: Schema(versionedSchema: MigProbeInPlace.self), url: url)
		)
		let ctx = ModelContext(container)

		// Unrelated user data (the nodes/messages analogue) survives.
		#expect(try ctx.fetch(FetchDescriptor<MigProbeInPlace.Keeper>()).contains { $0.note == "precious" })
		// The previously-optional row materializes under the new shape with its value intact —
		// SwiftData lightweight migration maps [String]? -> [String] without loss.
		let link = try ctx.fetch(FetchDescriptor<MigProbeInPlace.Link>()).first { $0.code == "rokland" }
		#expect(link?.regions == ["US", "CA"])
		// Store remains usable.
		ctx.insert(MigProbeInPlace.Link(code: "after", regions: ["JP"]))
		#expect(throws: Never.self) { try ctx.save() }
	}

	/// Documents that the heavier V2 approach (bumped version + custom stage that drops the
	/// disposable rows) also works — kept as a reference for if a future change to this entity
	/// is NOT lightweight-migratable and genuinely needs a versioned stage.
	@Test("Versioned migration with a custom clear stage also reopens non-destructively")
	func testVersionedMigration() throws {
		let url = tempStoreURL()
		try seedOldStore(at: url)

		let container = try ModelContainer(
			for: MigProbeNew.Link.self, MigProbeNew.Keeper.self,
			migrationPlan: MigProbePlan.self,
			configurations: ModelConfiguration(schema: Schema(versionedSchema: MigProbeNew.self), url: url)
		)
		let ctx = ModelContext(container)
		// Unrelated data survives the migration.
		#expect(try ctx.fetch(FetchDescriptor<MigProbeNew.Keeper>()).contains { $0.note == "precious" })
		// The affected (disposable) rows were cleared by the stage; the new shape is usable.
		ctx.insert(MigProbeNew.Link(code: "fresh", regions: ["DE"]))
		try ctx.save()
		#expect(try ctx.fetch(FetchDescriptor<MigProbeNew.Link>()).contains { $0.code == "fresh" && $0.regions == ["DE"] })
	}
}
