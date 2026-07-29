//
//  EventFirmwareMetadataTests.swift
//  MeshtasticTests
//
//  Tests for the event-firmware metadata pipeline: edition-key mapping, hex-color
//  parsing, link round-tripping, and the post-event `hasEnded` lifecycle logic.
//

import Foundation
import SwiftData
import Testing
import SwiftUI
import UIKit
@testable import Meshtastic

@Suite("Event firmware metadata")
struct EventFirmwareMetadataTests {

	// MARK: - Edition key mapping

	@Test func editionKeyRoundTrips() {
		for edition in FirmwareEditions.allCases {
			#expect(FirmwareEditions(editionKey: edition.editionKey) == edition)
		}
	}

	@Test func editionKeyMatchesProtoNames() {
		#expect(FirmwareEditions.defcon.editionKey == "DEFCON")
		#expect(FirmwareEditions.openSauce.editionKey == "OPEN_SAUCE")
		#expect(FirmwareEditions.burningMan.editionKey == "BURNING_MAN")
		#expect(FirmwareEditions.hamvention.editionKey == "HAMVENTION")
		#expect(FirmwareEditions(rawValue: 20)?.editionKey == "FAB")
		#expect(FirmwareEditions.vanilla.editionKey == "VANILLA")
	}

	@Test func unknownEditionKeyReturnsNil() {
		#expect(FirmwareEditions(editionKey: "NOT_A_REAL_EVENT") == nil)
	}

	// MARK: - Color parsing

	@Test func parsesSixDigitHex() {
		#expect(EventFirmwareEntity.color(fromHex: "#0D294A") != nil)
	}

	/// Locks the RGB byte order: `#0D294A` must parse to R=0x0D, G=0x29, B=0x4A (not a swapped
	/// channel order). Asserting the resolved channels, not just non-nil, guards the parser
	/// contract rather than mere liveness.
	@Test func parsesSixDigitHexChannelsInOrder() throws {
		let color = try #require(EventFirmwareEntity.color(fromHex: "#0D294A"))
		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
		#expect(abs(r - 0x0D / 255.0) < 0.01)
		#expect(abs(g - 0x29 / 255.0) < 0.01)
		#expect(abs(b - 0x4A / 255.0) < 0.01)
		#expect(abs(a - 1.0) < 0.01)
	}

	@Test func rejectsMalformedHex() {
		#expect(EventFirmwareEntity.color(fromHex: nil) == nil)
		#expect(EventFirmwareEntity.color(fromHex: "") == nil)
		#expect(EventFirmwareEntity.color(fromHex: "#ZZZ") == nil)
		#expect(EventFirmwareEntity.color(fromHex: "#12345") == nil)
		#expect(EventFirmwareEntity.color(fromHex: "0D294A") == nil)
		#expect(EventFirmwareEntity.color(fromHex: "#800D294A") == nil)
	}

	// MARK: - Links

	@Test func linksRoundTripThroughJSON() {
		let entity = EventFirmwareEntity(edition: "DEFCON")
		let links = [
			EventFirmwareEntity.Link(label: "Event Website", url: "https://defcon.org"),
			EventFirmwareEntity.Link(label: "Mastodon", url: "https://defcon.social")
		]
		entity.setLinks(links)
		#expect(entity.links == links)
	}

	@Test func emptyLinksClearJSON() {
		let entity = EventFirmwareEntity(edition: "DEFCON")
		entity.setLinks([EventFirmwareEntity.Link(label: "x", url: "y")])
		entity.setLinks([])
		#expect(entity.linksJSON == nil)
		#expect(entity.links.isEmpty)
	}

	@Test func unsafeLinksAreDiscarded() {
		let entity = EventFirmwareEntity(edition: "DEFCON")
		entity.setLinks([
			EventFirmwareEntity.Link(label: "Secure", url: "https://defcon.org"),
			EventFirmwareEntity.Link(label: "Insecure", url: "http://defcon.org"),
			EventFirmwareEntity.Link(label: "Custom Scheme", url: "meshtastic:///settings")
		])

		#expect(entity.links == [
			EventFirmwareEntity.Link(label: "Secure", url: "https://defcon.org")
		])
	}

	@Test func unsafeCachedLinksAreDiscardedWhenRead() throws {
		let entity = EventFirmwareEntity(edition: "DEFCON")
		let cached = [
			EventFirmwareEntity.Link(label: "Secure", url: "https://defcon.org"),
			EventFirmwareEntity.Link(label: "Insecure", url: "http://defcon.org")
		]
		let data = try JSONEncoder().encode(cached)
		entity.linksJSON = String(data: data, encoding: .utf8)

		#expect(entity.links == [
			EventFirmwareEntity.Link(label: "Secure", url: "https://defcon.org")
		])
	}

	@Test func iconURLRequiresHTTPS() {
		let entity = EventFirmwareEntity(edition: "DEFCON")
		entity.iconUrl = "http://api.meshtastic.org/icon.png"
		#expect(entity.iconURL == nil)

		entity.iconUrl = "  https://api.meshtastic.org/icon.png  "
		#expect(entity.iconURL?.absoluteString == "https://api.meshtastic.org/icon.png")
	}

	@Test func eventURLsRejectUserInfoAndMalformedAuthorities() {
		#expect(EventFirmwareURLPolicy.httpsURL(
			from: "https://api.meshtastic.org@evil.example/icon.png"
		) == nil)
		#expect(EventFirmwareURLPolicy.httpsURL(from: "https://:443/icon.png") == nil)
		#expect(EventFirmwareURLPolicy.httpsURL(from: "https:///icon.png") == nil)
	}

	// MARK: - Manifest decoding

	@Test func malformedManifestEntryDoesNotDiscardValidEntries() throws {
		let data = try #require("""
		{
		  "version": 2,
		  "editions": [
		    {"displayName": "Missing edition"},
		    {"edition": "DEFCON", "displayName": "DEF CON 34", "unknownFutureField": true},
		    {"edition": "BURNING_MAN", "links": [{"label": 42, "url": "https://example.com"}]}
		  ]
		}
		""".data(using: .utf8))

		let manifest = try EventFirmwareManifestDecoder.decode(data)

		#expect(manifest.editions.count == 1)
		#expect(manifest.editions.first?.edition == "DEFCON")
		#expect(manifest.editions.first?.displayName == "DEF CON 34")
	}

	@Test func emptyEditionIsDiscarded() throws {
		let data = try #require("""
		{"version": 2, "editions": [{"edition": ""}, {"edition": "FAB"}]}
		""".data(using: .utf8))

		let manifest = try EventFirmwareManifestDecoder.decode(data)

		#expect(manifest.editions.map(\.edition) == ["FAB"])
	}

	// MARK: - hasEnded lifecycle

	@Test func pastEventHasEnded() {
		let entity = EventFirmwareEntity(edition: "DEFCON")
		entity.eventEnd = "2020-01-02"
		entity.timeZone = "America/Los_Angeles"
		#expect(entity.hasEnded() == true)
	}

	@Test func futureEventHasNotEnded() {
		let entity = EventFirmwareEntity(edition: "DEFCON")
		entity.eventEnd = "2999-01-02"
		entity.timeZone = "America/Los_Angeles"
		#expect(entity.hasEnded() == false)
	}

	@Test func missingEndDateNeverCountsAsEnded() {
		let entity = EventFirmwareEntity(edition: "DEFCON")
		entity.eventEnd = nil
		#expect(entity.hasEnded() == false)
	}

	@Test func unparseableEndDateNeverCountsAsEnded() {
		let entity = EventFirmwareEntity(edition: "DEFCON")
		entity.eventEnd = "not-a-date"
		#expect(entity.hasEnded() == false)
	}

	@Test func endOfDayBoundaryIsRespected() {
		// The event ends 2026-05-17 in New York. At 22:00 UTC on that day it is still ~18:00
		// local — the event must NOT be considered ended until end-of-day local time.
		let entity = EventFirmwareEntity(edition: "HAMVENTION")
		entity.eventEnd = "2026-05-17"
		entity.timeZone = "America/New_York"
		var comps = DateComponents()
		comps.year = 2026; comps.month = 5; comps.day = 17; comps.hour = 22
		comps.timeZone = TimeZone(identifier: "UTC")
		let duringLastDay = Calendar(identifier: .gregorian).date(from: comps)!
		#expect(entity.hasEnded(now: duringLastDay) == false)
	}

	@Test func finalFractionalSecondOfEventDayHasNotEnded() throws {
		let entity = EventFirmwareEntity(edition: "HAMVENTION")
		entity.eventEnd = "2026-05-17"
		entity.timeZone = "America/New_York"
		var components = DateComponents()
		components.year = 2026
		components.month = 5
		components.day = 17
		components.hour = 23
		components.minute = 59
		components.second = 59
		components.nanosecond = 500_000_000
		components.timeZone = TimeZone(identifier: "America/New_York")
		let duringFinalSecond = try #require(Calendar(identifier: .gregorian).date(from: components))

		#expect(entity.hasEnded(now: duringFinalSecond) == false)
	}

	@Test func firstInstantAfterEventDayHasEnded() throws {
		let entity = EventFirmwareEntity(edition: "HAMVENTION")
		entity.eventEnd = "2026-05-17"
		entity.timeZone = "America/New_York"
		var components = DateComponents()
		components.year = 2026
		components.month = 5
		components.day = 18
		components.timeZone = TimeZone(identifier: "America/New_York")
		let nextDay = try #require(Calendar(identifier: .gregorian).date(from: components))

		#expect(entity.hasEnded(now: nextDay) == true)
	}

	@Test func impossibleCalendarDateNeverCountsAsEnded() {
		let entity = EventFirmwareEntity(edition: "HAMVENTION")
		entity.eventEnd = "2026-02-30"
		entity.timeZone = "America/New_York"

		#expect(entity.hasEnded(now: .distantFuture) == false)
	}

	@Test func firmwareEditionResolvesFromKey() {
		let entity = EventFirmwareEntity(edition: "OPEN_SAUCE")
		#expect(entity.firmwareEdition == .openSauce)
	}

	// MARK: - Presentation

	@Test func presentationRequiresConnectedEventWithMatchingMetadata() throws {
		let fab = EventFirmwareEntity(edition: "FAB")
		fab.displayName = "FAB26 Boston"

		let presentation = try #require(EventFirmwarePresentation.resolve(
			isConnected: true,
			edition: FirmwareEditions(rawValue: 20) ?? .vanilla,
			metadata: [fab],
			deviceFirmwareVersion: "2.7.27.d250d89"
		))

		#expect(presentation.edition.rawValue == 20)
		#expect(presentation.info === fab)
		#expect(presentation.deviceFirmwareVersion == "2.7.27.d250d89")
	}

	@Test func presentationKeepsStandardBrandingWithoutCompleteContext() {
		let defcon = EventFirmwareEntity(edition: "DEFCON")

		#expect(EventFirmwarePresentation.resolve(
			isConnected: false,
			edition: .defcon,
			metadata: [defcon],
			deviceFirmwareVersion: nil
		) == nil)
		#expect(EventFirmwarePresentation.resolve(
			isConnected: true,
			edition: .vanilla,
			metadata: [defcon],
			deviceFirmwareVersion: nil
		) == nil)
		#expect(EventFirmwarePresentation.resolve(
			isConnected: true,
			edition: .openSauce,
			metadata: [defcon],
			deviceFirmwareVersion: nil
		) == nil)
	}

	@Test func bundledArtworkExistsOnlyForShippedEditionIcons() {
		#expect(FirmwareEditions.hamvention.bundledIconAssetName == "EventFirmwareHAMVENTION")
		#expect(FirmwareEditions(rawValue: 20)?.bundledIconAssetName == "EventFirmwareFAB")
		#expect(FirmwareEditions.defcon.bundledIconAssetName == "EventFirmwareDEFCON")
		#expect(FirmwareEditions.openSauce.bundledIconAssetName == nil)
		#expect(FirmwareEditions.burningMan.bundledIconAssetName == nil)
		#expect(FirmwareEditions.vanilla.bundledIconAssetName == nil)
	}

	// MARK: - Firmware build comparison

	@Test func normalizedVersionStripsLeadingVAndWhitespace() {
		#expect(EventFirmwareEntity.normalizedVersion("  v2.7.23  ") == "2.7.23")
		#expect(EventFirmwareEntity.normalizedVersion("2.7.23") == "2.7.23")
		#expect(EventFirmwareEntity.normalizedVersion(nil) == nil)
		#expect(EventFirmwareEntity.normalizedVersion("") == nil)
	}

	@Test func firmwareComparisonMatchesOnEqualVersion() {
		let entity = EventFirmwareEntity(edition: "HAMVENTION")
		entity.firmwareVersion = "2.7.23.07741e6"
		if case .matches = entity.firmwareComparison(againstDeviceVersion: "v2.7.23.07741e6") {} else {
			Issue.record("expected .matches")
		}
	}

	@Test func firmwareComparisonMatchesOnTruncatedDeviceVersion() {
		// The device reports a shorter version than the full event build — still a match.
		let entity = EventFirmwareEntity(edition: "HAMVENTION")
		entity.firmwareVersion = "2.7.23.07741e6"
		if case .matches = entity.firmwareComparison(againstDeviceVersion: "2.7.23") {} else {
			Issue.record("expected .matches on prefix")
		}
	}

	@Test func firmwareComparisonUpdateAvailableOnDifferentBuild() {
		let entity = EventFirmwareEntity(edition: "HAMVENTION")
		entity.firmwareVersion = "2.7.23.07741e6"
		if case .updateAvailable = entity.firmwareComparison(againstDeviceVersion: "2.6.11.aaaaaaa") {} else {
			Issue.record("expected .updateAvailable")
		}
	}

	@Test func firmwareComparisonRespectsDotBoundary() {
		// "2.7.2" is a bare-string prefix of "2.7.23" but a DIFFERENT version — must not match.
		let entity = EventFirmwareEntity(edition: "HAMVENTION")
		entity.firmwareVersion = "2.7.2"
		if case .updateAvailable = entity.firmwareComparison(againstDeviceVersion: "2.7.23") {} else {
			Issue.record("expected .updateAvailable across the dot boundary")
		}
	}

	@Test func firmwareComparisonUnknownWhenVersionMissing() {
		let entity = EventFirmwareEntity(edition: "DEFCON")
		entity.firmwareVersion = nil
		if case .unknown = entity.firmwareComparison(againstDeviceVersion: "2.7.23") {} else {
			Issue.record("expected .unknown when event version missing")
		}
	}

	// MARK: - Theme fonts

	@Test func fontResolverRejectsUnavailableFamily() {
		#expect(EventFirmwareFontResolver.isFamilyAvailable("NoSuchFontFamily_ZZZ") == false)
		#expect(EventFirmwareFontResolver.isFamilyAvailable(nil) == false)
		#expect(EventFirmwareFontResolver.isFamilyAvailable("") == false)
	}

	@Test func fontResolverDetectsSystemFamily() {
		// Helvetica ships on every iOS device; case-insensitive lookup should find it.
		#expect(EventFirmwareFontResolver.isFamilyAvailable("Helvetica") == true)
		#expect(EventFirmwareFontResolver.isFamilyAvailable("helvetica") == true)
	}

	// MARK: - Palette & dates

	@Test func paletteColorsSkipMalformedEntries() {
		let entity = EventFirmwareEntity(edition: "DEFCON")
		entity.themePalette = ["#0D294A", "not-a-color", "#E0004E"]
		#expect(entity.paletteColors.count == 2)
	}

	@Test func brandPalettePrefersAuthoredColorsAndDeduplicatesCaseInsensitively() {
		let entity = EventFirmwareEntity(edition: "DEFCON")
		entity.themePrimaryColor = "#0D294A"
		entity.themeSecondaryColor = "#017FA4"
		entity.themeAccentColor = "#E0004E"
		entity.themePalette = ["#0D294A", "not-a-color", "#E0004E", "#0d294a"]

		#expect(entity.brandPaletteHexes == ["#0D294A", "#E0004E"])
		#expect(entity.paletteColors.count == 2)
	}

	@Test func brandPaletteFallsBackToNamedColorsThenTopLevelAccent() {
		let entity = EventFirmwareEntity(edition: "BURNING_MAN")
		entity.accentColor = "#EC8819"
		entity.themePrimaryColor = "#EC8819"
		entity.themeSecondaryColor = "#F1B435"
		entity.themeAccentColor = "#ec8819"

		#expect(entity.brandPaletteHexes == ["#EC8819", "#F1B435"])

		let accentOnly = EventFirmwareEntity(edition: "BURNING_MAN")
		accentOnly.accentColor = "#EC8819"
		#expect(accentOnly.brandPaletteHexes == ["#EC8819"])
		#expect(accentOnly.paletteColors.count == 1)
	}

	@Test func accessibleTintUsesFirstCandidateWithThreeToOneContrast() {
		let entity = EventFirmwareEntity(edition: "FAB")
		entity.themeAccentColor = "#EAB14B"
		entity.themePalette = ["#13293D", "#BF2620"]

		#expect(entity.accessibleTintHex(for: .light) == "#13293D")
		#expect(entity.accessibleTintHex(for: .dark) == "#EAB14B")
	}

	@Test func accessibleTintAdjustsSaturatedBrandColorInsteadOfFallingBackToAppBlue() {
		let entity = EventFirmwareEntity(edition: "BURNING_MAN")
		entity.themeAccentColor = "#EC8819"
		entity.themePalette = ["#EC8819"]

		let tint = entity.accessibleTintHex(for: .light)

		#expect(tint != nil)
		#expect(tint != "#EC8819")
		#expect(tint?.hasPrefix("#") == true)
	}

	@Test func invalidTintCandidatesReturnNil() {
		let entity = EventFirmwareEntity(edition: "FAB")
		entity.themeAccentColor = "yellow"
		entity.themePalette = ["#FFFFFF"]

		#expect(entity.accessibleTintHex(for: .light) == nil)
	}

	@Test func headerForegroundTracksAccentLuminance() {
		#expect(EventFirmwareEntity.prefersDarkForeground(forHex: "#FFFFFF") == true)
		#expect(EventFirmwareEntity.prefersDarkForeground(forHex: "#13293D") == false)
		#expect(EventFirmwareEntity.prefersDarkForeground(forHex: "invalid") == nil)
	}

	// MARK: - Image validation

	@Test func imageValidatorAcceptsSmallPNG() throws {
		let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
		let image = renderer.image { context in
			UIColor.red.setFill()
			context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
		}
		let png = try #require(image.pngData())

		#expect(EventFirmwareImageValidator.image(from: png) != nil)
	}

	@Test func imageValidatorRejectsMarkupAndOversizedDimensions() {
		#expect(EventFirmwareImageValidator.image(from: Data("<svg/>".utf8)) == nil)
		#expect(EventFirmwareImageValidator.isDecodedSizeAllowed(width: 1_024, height: 1_024))
		#expect(!EventFirmwareImageValidator.isDecodedSizeAllowed(width: 8_192, height: 8_192))
	}

	// MARK: - Refresh policy

	@Test func refreshPolicyRateLimitsRecentAttempts() {
		let now = Date(timeIntervalSince1970: 1_000_000)

		#expect(!EventFirmwareRefreshPolicy.shouldRefresh(
			lastAttempt: now.addingTimeInterval(-60),
			now: now
		))
		#expect(EventFirmwareRefreshPolicy.shouldRefresh(
			lastAttempt: now.addingTimeInterval(-7 * 60 * 60),
			now: now
		))
		#expect(EventFirmwareRefreshPolicy.shouldRefresh(
			lastAttempt: now.addingTimeInterval(60),
			now: now
		))
	}

	@Test func formattedDateRangeProducesRange() {
		let entity = EventFirmwareEntity(edition: "DEFCON")
		entity.eventStart = "2026-08-06"
		entity.eventEnd = "2026-08-09"
		entity.timeZone = "America/Los_Angeles"
		let range = entity.formattedDateRange
		#expect(range != nil)
		#expect(range?.contains("–") == true)
	}

	@Test func formattedDateRangeNilWhenNoDates() {
		let entity = EventFirmwareEntity(edition: "DEFCON")
		#expect(entity.formattedDateRange == nil)
	}
}

@Suite("Event firmware cache merge", .serialized)
@MainActor
struct EventFirmwareCacheMergeTests {

	private func makeContainer() throws -> ModelContainer {
		let schema = Schema([EventFirmwareEntity.self])
		let configuration = ModelConfiguration(
			"EventFirmwareCacheMerge-\(UUID().uuidString)",
			schema: schema,
			isStoredInMemoryOnly: true
		)
		return try ModelContainer(for: schema, configurations: configuration)
	}

	private func payloads(from json: String) throws -> [EventFirmwarePayload] {
		let data = try #require(json.data(using: .utf8))
		return try EventFirmwareManifestDecoder.decode(data).editions
	}

	@Test func bundledSeedDoesNotOverwriteNewerLiveMetadata() async throws {
		let container = try makeContainer()
		let api = MeshtasticAPI(container: container, startupRefresh: false)
		let live = try payloads(from: """
		{"version":2,"editions":[{
		  "edition":"DEFCON",
		  "displayName":"DEF CON Live",
		  "welcomeMessage":"Fresh from API"
		}]}
		""")
		let bundled = try payloads(from: """
		{"version":2,"editions":[{
		  "edition":"DEFCON",
		  "displayName":"Bundled DEF CON",
		  "welcomeMessage":"Older bundle"
		}]}
		""")

		await api.importEventEditions(live, overwriteExisting: true)
		await api.importEventEditions(bundled, overwriteExisting: false)

		let rows = try container.mainContext.fetch(FetchDescriptor<EventFirmwareEntity>())
		let defcon = try #require(rows.first { $0.edition == "DEFCON" })
		#expect(defcon.displayName == "DEF CON Live")
		#expect(defcon.welcomeMessage == "Fresh from API")
	}

	@Test func partialLiveManifestPreservesCachedFieldsAndOtherEditions() async throws {
		let container = try makeContainer()
		let api = MeshtasticAPI(container: container, startupRefresh: false)
		let complete = try payloads(from: """
		{"version":2,"editions":[
		  {
		    "edition":"DEFCON",
		    "displayName":"DEF CON 34",
		    "welcomeMessage":"Welcome",
		    "links":[{"label":"Event","url":"https://defcon.org"}],
		    "theme":{"tagline":"Old tagline","palette":["#0D294A","#E0004E"]}
		  },
		  {"edition":"FAB","displayName":"FAB26 Boston"}
		]}
		""")
		let partial = try payloads(from: """
		{"version":2,"editions":[{
		  "edition":"DEFCON",
		  "links":[{"label":"Unsafe","url":"javascript:alert(1)"}],
		  "theme":{"tagline":"Updated tagline","palette":["not-a-color"]}
		}]}
		""")

		await api.importEventEditions(complete, overwriteExisting: true)
		await api.importEventEditions(partial, overwriteExisting: true)

		let rows = try container.mainContext.fetch(FetchDescriptor<EventFirmwareEntity>())
		let defcon = try #require(rows.first { $0.edition == "DEFCON" })
		#expect(defcon.displayName == "DEF CON 34")
		#expect(defcon.welcomeMessage == "Welcome")
		#expect(defcon.themeTagline == "Updated tagline")
		#expect(defcon.links == [EventFirmwareEntity.Link(label: "Event", url: "https://defcon.org")])
		#expect(defcon.themePalette == ["#0D294A", "#E0004E"])
		#expect(rows.contains { $0.edition == "FAB" && $0.displayName == "FAB26 Boston" })
	}
}
