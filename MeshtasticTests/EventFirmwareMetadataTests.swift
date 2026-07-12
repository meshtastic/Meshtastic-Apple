//
//  EventFirmwareMetadataTests.swift
//  MeshtasticTests
//
//  Tests for the event-firmware metadata pipeline: edition-key mapping, hex-color
//  parsing, link round-tripping, and the post-event `hasEnded` lifecycle logic.
//

import Foundation
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
		#expect(FirmwareEditions.vanilla.editionKey == "VANILLA")
	}

	@Test func unknownEditionKeyReturnsNil() {
		#expect(FirmwareEditions(editionKey: "NOT_A_REAL_EVENT") == nil)
	}

	// MARK: - Color parsing

	@Test func parsesSixDigitHex() {
		#expect(EventFirmwareEntity.color(fromHex: "#0D294A") != nil)
		#expect(EventFirmwareEntity.color(fromHex: "0D294A") != nil)
	}

	@Test func parsesEightDigitHexWithAlpha() {
		#expect(EventFirmwareEntity.color(fromHex: "#FF0D294A") != nil)
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

	/// Locks the 8-digit interpretation as `#AARRGGBB`: `#800D294A` → A=0x80, R=0x0D.
	@Test func parsesEightDigitHexAsAARRGGBB() throws {
		let color = try #require(EventFirmwareEntity.color(fromHex: "#800D294A"))
		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
		#expect(abs(a - 0x80 / 255.0) < 0.01)
		#expect(abs(r - 0x0D / 255.0) < 0.01)
		#expect(abs(g - 0x29 / 255.0) < 0.01)
		#expect(abs(b - 0x4A / 255.0) < 0.01)
	}

	@Test func rejectsMalformedHex() {
		#expect(EventFirmwareEntity.color(fromHex: nil) == nil)
		#expect(EventFirmwareEntity.color(fromHex: "") == nil)
		#expect(EventFirmwareEntity.color(fromHex: "#ZZZ") == nil)
		#expect(EventFirmwareEntity.color(fromHex: "#12345") == nil)
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

	@Test func firmwareEditionResolvesFromKey() {
		let entity = EventFirmwareEntity(edition: "OPEN_SAUCE")
		#expect(entity.firmwareEdition == .openSauce)
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
