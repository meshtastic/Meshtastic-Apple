//
//  EventFirmwareEntity.swift
//  Meshtastic
//
//  Persisted event-firmware display metadata, mirroring the cross-platform
//  `GET https://api.meshtastic.org/resource/eventFirmware` (version 2) payload.
//
//  A device only reports *which* event edition it runs (the stable proto enum
//  `MyNodeInfo.firmwareEdition`); the branding/lifecycle data for each edition
//  lives off-device and is fetched at runtime with a bundled JSON snapshot as
//  the offline fallback — so a new event ships without an app release. This
//  entity is the on-device cache of that data (see design#120).
//

import Foundation
import SwiftData
import SwiftUI

@Model
final class EventFirmwareEntity {

	/// The stable proto edition key, e.g. `"DEFCON"`, `"OPEN_SAUCE"`. This is the enum
	/// name from `FirmwareEdition` and is the join key against the connected device's
	/// reported `firmwareEdition`. Unique so refreshes upsert rather than duplicate.
	@Attribute(.unique) var edition: String = ""

	// MARK: - Identity & copy

	var displayName: String?
	var welcomeMessage: String?
	var tag: String?
	var location: String?
	var domain: String?

	// MARK: - Lifecycle (dates evaluated in `timeZone`)

	/// ISO-8601 calendar date string, e.g. `"2026-08-06"`. Stored as-is from the API;
	/// parsed on demand via `eventStartDate` / `eventEndDate`.
	var eventStart: String?
	var eventEnd: String?
	/// IANA time-zone identifier, e.g. `"America/Los_Angeles"`. Drives when the event is
	/// considered over; falls back to the device's zone when missing/unparseable.
	var timeZone: String?

	// MARK: - Branding

	/// Hex accent color, e.g. `"#0D294A"`. Layered on top of the app chrome instead of a
	/// hardcoded `.orange`. Optional — a missing/invalid value falls back to `.accentColor`.
	var accentColor: String?
	/// Hosted event icon URL (may be nil — not every edition ships one).
	var iconUrl: String?

	// MARK: - Theme (v2, progressively consumed)

	var themeName: String?
	var themeTagline: String?
	/// Ordered palette of hex colors. Non-optional array (SwiftData cannot materialize an
	/// optional value-type array — see `DeviceLinkEntity.regions`, issue #1949).
	var themePalette: [String] = []
	/// Google Font *family names* (not URLs) — resolved via the platform font mechanism,
	/// falling back to the system font when unavailable.
	var themeFontHeading: String?
	var themeFontBody: String?

	// MARK: - Links

	/// Event links (`label`/`url`), JSON-encoded. Decoded on demand via `links`. Stored as a
	/// blob rather than a relationship to keep the whole edition a single upsertable row.
	var linksJSON: String?

	// MARK: - Firmware build (v2, progressively consumed)

	var firmwareSlug: String?
	var firmwareVersion: String?
	var firmwareId: String?
	var firmwareTitle: String?
	var firmwareZipUrl: String?
	var firmwareReleaseNotes: String?

	init() {}

	init(edition: String) {
		self.edition = edition
	}
}

// MARK: - Derived accessors

extension EventFirmwareEntity {

	/// A single event link.
	struct Link: Codable, Identifiable, Hashable {
		let label: String
		let url: String
		var id: String { "\(label)|\(url)" }
	}

	/// The `FirmwareEditions` enum case this row describes, resolved from the stable key.
	var firmwareEdition: FirmwareEditions? {
		FirmwareEditions(editionKey: edition)
	}

	/// Decoded links, or `[]` when absent/unparseable.
	var links: [Link] {
		guard let linksJSON, let data = linksJSON.data(using: .utf8),
			  let decoded = try? JSONDecoder().decode([Link].self, from: data) else {
			return []
		}
		return decoded
	}

	/// Persist `links` back into `linksJSON`.
	func setLinks(_ links: [Link]) {
		guard !links.isEmpty, let data = try? JSONEncoder().encode(links),
			  let string = String(data: data, encoding: .utf8) else {
			linksJSON = nil
			return
		}
		linksJSON = string
	}

	/// The accent color as a SwiftUI `Color`, or nil when no valid hex was provided.
	var accentColorValue: Color? {
		Self.color(fromHex: accentColor)
	}

	/// Parse a `#RRGGBB` / `#AARRGGBB` (or bare-hex) string into a `Color`. Returns nil on
	/// a missing or malformed value so callers can fall back to `.accentColor`.
	static func color(fromHex hex: String?) -> Color? {
		guard var value = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
			return nil
		}
		if value.hasPrefix("#") { value.removeFirst() }
		guard value.count == 6 || value.count == 8, let int = UInt64(value, radix: 16) else {
			return nil
		}
		let r, g, b, a: Double
		if value.count == 8 {
			a = Double((int & 0xFF00_0000) >> 24) / 255
			r = Double((int & 0x00FF_0000) >> 16) / 255
			g = Double((int & 0x0000_FF00) >> 8) / 255
			b = Double(int & 0x0000_00FF) / 255
		} else {
			a = 1
			r = Double((int & 0xFF0000) >> 16) / 255
			g = Double((int & 0x00FF00) >> 8) / 255
			b = Double(int & 0x0000FF) / 255
		}
		return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
	}

	/// The end date parsed at the *end* of the calendar day, in the edition's IANA time zone
	/// (falling back to the device's current zone when the identifier is missing/unknown).
	/// Returns nil for a missing/unparseable `eventEnd` — callers treat nil as "not ended".
	var eventEndDate: Date? {
		Self.endOfDay(from: eventEnd, timeZoneIdentifier: timeZone)
	}

	/// The start date parsed at the start of the calendar day, in the edition's time zone.
	var eventStartDate: Date? {
		Self.startOfDay(from: eventStart, timeZoneIdentifier: timeZone)
	}

	/// Whether the event has ended relative to `now` (default: current time).
	///
	/// True only when `eventEnd` parses to a date whose end-of-day (in the edition's zone) is
	/// in the past. A missing or unparseable `eventEnd` returns `false` — an event must never
	/// be counted as ended without a valid end date (mirrors Android `hasEnded()`).
	func hasEnded(now: Date = Date()) -> Bool {
		guard let end = eventEndDate else { return false }
		return end < now
	}

	private static func calendar(for timeZoneIdentifier: String?) -> Calendar {
		var calendar = Calendar(identifier: .gregorian)
		if let id = timeZoneIdentifier, let zone = TimeZone(identifier: id) {
			calendar.timeZone = zone
		}
		return calendar
	}

	private static func startOfDay(from dateString: String?, timeZoneIdentifier: String?) -> Date? {
		guard let components = dateComponents(from: dateString) else { return nil }
		return calendar(for: timeZoneIdentifier).date(from: components)
	}

	private static func endOfDay(from dateString: String?, timeZoneIdentifier: String?) -> Date? {
		guard var components = dateComponents(from: dateString) else { return nil }
		// End of the calendar day (23:59:59) so an all-day event isn't marked over at midnight.
		components.hour = 23
		components.minute = 59
		components.second = 59
		return calendar(for: timeZoneIdentifier).date(from: components)
	}

	/// Parse a `"YYYY-MM-DD"` string into date components, or nil when malformed.
	private static func dateComponents(from dateString: String?) -> DateComponents? {
		guard let dateString, !dateString.isEmpty else { return nil }
		// Accept a leading date even if a time portion is present (e.g. "2026-08-06T00:00:00Z").
		let datePart = dateString.split(separator: "T").first.map(String.init) ?? dateString
		let parts = datePart.split(separator: "-")
		guard parts.count == 3,
			  let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
			  (1...12).contains(month), (1...31).contains(day) else {
			return nil
		}
		var components = DateComponents()
		components.year = year
		components.month = month
		components.day = day
		return components
	}
}
