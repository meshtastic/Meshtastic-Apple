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
import ImageIO
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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

	/// Hex accent color, e.g. `"#0D294A"`. Used inside the dedicated event information
	/// surface. Optional — a missing/invalid value falls back to `.accentColor`.
	var accentColor: String?
	/// Hosted event icon URL (may be nil — not every edition ships one).
	var iconUrl: String?

	// MARK: - Theme (v2, progressively consumed)

	var themeName: String?
	var themeTagline: String?
	/// Named brand colors used when a manifest does not provide an authored palette.
	var themePrimaryColor: String?
	var themeSecondaryColor: String?
	/// The theme's high-energy accent candidate. It is used for small marks only after
	/// satisfying the 3:1 graphical-object contrast requirement against the current surface.
	var themeAccentColor: String?
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
		return decoded.filter { EventFirmwareURLPolicy.httpsURL(from: $0.url) != nil }
	}

	/// Persist `links` back into `linksJSON`.
	func setLinks(_ links: [Link]) {
		let safeLinks = links.filter { EventFirmwareURLPolicy.httpsURL(from: $0.url) != nil }
		guard !safeLinks.isEmpty, let data = try? JSONEncoder().encode(safeLinks),
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

	/// The hosted icon URL after applying the manifest's HTTPS-only navigation policy.
	var iconURL: URL? {
		EventFirmwareURLPolicy.httpsURL(from: iconUrl)
	}

	/// Parse a strict `#RRGGBB` string into a `Color`. Returns nil on a missing or malformed
	/// value so callers can drop untrusted manifest colors instead of misrepresenting the brand.
	static func color(fromHex hex: String?) -> Color? {
		guard let rawValue = hex?.trimmingCharacters(in: .whitespacesAndNewlines),
			  rawValue.count == 7,
			  rawValue.first == "#" else {
			return nil
		}
		let value = String(rawValue.dropFirst())
		guard let int = UInt64(value, radix: 16) else {
			return nil
		}
		let r = Double((int & 0xFF0000) >> 16) / 255
		let g = Double((int & 0x00FF00) >> 8) / 255
		let b = Double(int & 0x0000FF) / 255
		return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
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
		guard let components = Self.dateComponents(from: eventEnd) else { return false }
		let calendar = Self.calendar(for: timeZone)
		guard let end = calendar.date(from: components) else { return false }
		return calendar.compare(now, to: end, toGranularity: .day) == .orderedDescending
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
		guard let dateString, dateString.count == 10 else { return nil }
		let parts = dateString.split(separator: "-", omittingEmptySubsequences: false)
		guard parts.count == 3,
			  let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
			  (1...12).contains(month), (1...31).contains(day) else {
			return nil
		}
		var components = DateComponents()
		components.year = year
		components.month = month
		components.day = day
		var validationCalendar = Calendar(identifier: .gregorian)
		validationCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
		guard let date = validationCalendar.date(from: components) else { return nil }
		let validated = validationCalendar.dateComponents([.year, .month, .day], from: date)
		guard validated.year == year, validated.month == month, validated.day == day else {
			return nil
		}
		return components
	}

	/// A human-readable, locale-aware event date range (e.g. "Aug 6 – 9, 2026"), or nil when no
	/// dates parse. Uses `DateIntervalFormatter` so range separators and same-day collapsing
	/// follow the user's locale.
	var formattedDateRange: String? {
		let zone: TimeZone? = timeZone.flatMap { TimeZone(identifier: $0) }
		switch (eventStartDate, eventEndDate) {
		case let (start?, end?):
			let formatter = DateIntervalFormatter()
			formatter.dateStyle = .medium
			formatter.timeStyle = .none
			if let zone { formatter.timeZone = zone }
			return formatter.string(from: start, to: end)
		case let (single?, nil), let (nil, single?):
			let formatter = DateFormatter()
			formatter.dateStyle = .medium
			formatter.timeStyle = .none
			if let zone { formatter.timeZone = zone }
			return formatter.string(from: single)
		default:
			return nil
		}
	}
}

// MARK: - Manifest URL policy

enum EventFirmwareURLPolicy {

	/// Event metadata may only navigate to or fetch from an absolute HTTPS URL.
	static func httpsURL(from value: String?) -> URL? {
		guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
			  !value.isEmpty,
			  let components = URLComponents(string: value),
			  components.scheme?.lowercased() == "https",
			  components.host?.isEmpty == false,
			  components.user == nil,
			  components.password == nil,
			  let url = components.url else {
			return nil
		}
		return url
	}
}

// MARK: - Firmware build comparison

/// Result of comparing an edition's `firmware{}.version` against the connected device's
/// reported firmware version. We deliberately avoid semantic ordering — event builds carry
/// custom commit suffixes (e.g. `2.7.23.07741e6`) that don't order meaningfully — so any
/// mismatch is surfaced as `updateAvailable` and the user decides.
enum EventFirmwareVersionComparison {
	case unknown          // missing version on either side
	case matches          // device already runs the event build
	case updateAvailable  // event build differs from the device
}

extension EventFirmwareEntity {

	/// Normalize a version string for comparison: trim whitespace and strip a leading `v`.
	static func normalizedVersion(_ version: String?) -> String? {
		guard let value = version?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
			return nil
		}
		return value.hasPrefix("v") ? String(value.dropFirst()) : value
	}

	/// Compare this edition's firmware build against the connected device's firmware version.
	/// A *dot-boundary* prefix match either way counts as `matches` so a truncated device
	/// version (e.g. `"2.7.23"`) still lines up with the full event build
	/// (`"2.7.23.07741e6"`), without a bare-substring false positive (`"2.7.2"` must NOT match
	/// `"2.7.23"`).
	func firmwareComparison(againstDeviceVersion deviceVersion: String?) -> EventFirmwareVersionComparison {
		guard let event = Self.normalizedVersion(firmwareVersion),
			  let device = Self.normalizedVersion(deviceVersion) else {
			return .unknown
		}
		if event == device || device.hasPrefix(event + ".") || event.hasPrefix(device + ".") {
			return .matches
		}
		return .updateAvailable
	}

	/// The event's authored palette, or its named brand colors when no palette was supplied.
	/// Invalid colors are dropped and duplicates are removed while preserving author order.
	var brandPaletteHexes: [String] {
		let authored = Self.canonicalPalette(themePalette)
		if !authored.isEmpty {
			return authored
		}
		return Self.canonicalPalette([
			themePrimaryColor,
			themeSecondaryColor,
			themeAccentColor,
			accentColor
		].compactMap { $0 })
	}

	/// The palette colors as SwiftUI `Color`s, skipping any malformed hex entries.
	var paletteColors: [Color] {
		brandPaletteHexes.compactMap { Self.color(fromHex: $0) }
	}

	/// Select the first theme accent/palette candidate that clears the WCAG 3:1 contrast
	/// requirement for graphical objects against a light or dark system surface.
	func accessibleTintHex(for colorScheme: ColorScheme) -> String? {
		let backgroundLuminance = colorScheme == .dark ? 0.0 : 1.0
		let preferredHighlight = [themeAccentColor, themeSecondaryColor]
			.compactMap { $0 }
			.first { Self.color(fromHex: $0) != nil }
		let candidates = Self.canonicalPalette(
			[preferredHighlight].compactMap { $0 } + brandPaletteHexes
		)
		if let candidate = candidates.first(where: { candidate in
			guard let foreground = Self.relativeLuminance(fromHex: candidate) else { return false }
			let lighter = max(foreground, backgroundLuminance)
			let darker = min(foreground, backgroundLuminance)
			return (lighter + 0.05) / (darker + 0.05) >= 3
		}) {
			return candidate
		}

		// Some event colors are vivid but slightly too light for controls on the light system
		// background (Burning Man orange is one example). Preserve the hue by moving the first
		// saturated brand candidate toward the opposite system extreme until it clears 3:1.
		return candidates.lazy.compactMap {
			Self.contrastAdjustedTintHex($0, for: colorScheme)
		}.first
	}

	/// Whether black content has better contrast than white content over a manifest color.
	static func prefersDarkForeground(forHex hex: String?) -> Bool? {
		guard let hex, let luminance = relativeLuminance(fromHex: hex) else { return nil }
		let blackContrast = (luminance + 0.05) / 0.05
		let whiteContrast = 1.05 / (luminance + 0.05)
		return blackContrast >= whiteContrast
	}

	private static func relativeLuminance(fromHex hex: String) -> Double? {
		guard hex.count == 7, hex.first == "#", let value = UInt64(hex.dropFirst(), radix: 16) else {
			return nil
		}
		let red = Double((value & 0xFF0000) >> 16) / 255
		let green = Double((value & 0x00FF00) >> 8) / 255
		let blue = Double(value & 0x0000FF) / 255
		let components = [red, green, blue].map { component in
			component <= 0.04045
				? component / 12.92
				: pow((component + 0.055) / 1.055, 2.4)
		}
		return 0.2126 * components[0] + 0.7152 * components[1] + 0.0722 * components[2]
	}

	private static func contrastAdjustedTintHex(
		_ hex: String,
		for colorScheme: ColorScheme
	) -> String? {
		guard hex.count == 7,
			  hex.first == "#",
			  let value = UInt64(hex.dropFirst(), radix: 16) else {
			return nil
		}
		let components = [
			Double((value & 0xFF0000) >> 16) / 255,
			Double((value & 0x00FF00) >> 8) / 255,
			Double(value & 0x0000FF) / 255
		]
		guard let maximum = components.max(),
			  let minimum = components.min(),
			  maximum - minimum >= 0.15 else {
			return nil
		}

		let backgroundLuminance = colorScheme == .dark ? 0.0 : 1.0
		for step in 1...100 {
			let fraction = Double(step) / 100
			let adjusted = components.map { component in
				colorScheme == .dark
					? component + ((1 - component) * fraction)
					: component * (1 - fraction)
			}
			let adjustedHex = String(
				format: "#%02X%02X%02X",
				Int((adjusted[0] * 255).rounded()),
				Int((adjusted[1] * 255).rounded()),
				Int((adjusted[2] * 255).rounded())
			)
			guard let foreground = relativeLuminance(fromHex: adjustedHex) else { continue }
			let lighter = max(foreground, backgroundLuminance)
			let darker = min(foreground, backgroundLuminance)
			if (lighter + 0.05) / (darker + 0.05) >= 3 {
				return adjustedHex
			}
		}
		return nil
	}

	private static func canonicalPalette(_ values: [String]) -> [String] {
		var seen = Set<String>()
		return values.compactMap { value in
			let canonical = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
			guard color(fromHex: canonical) != nil, seen.insert(canonical).inserted else {
				return nil
			}
			return canonical
		}
	}
}

// MARK: - Event image validation

enum EventFirmwareImageValidator {

	static let maximumEncodedBytes = 2 * 1_024 * 1_024
	static let maximumDecodedPixelCount = 4_000_000

	static func isDecodedSizeAllowed(width: Int, height: Int) -> Bool {
		guard width > 0, height > 0 else { return false }
		let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
		return !overflow && pixelCount <= maximumDecodedPixelCount
	}

	/// Decode only bounded PNG/JPEG artwork. Other formats and malformed image data fall back
	/// to the bundled edition artwork or standard Meshtastic logo.
	static func image(from data: Data) -> UIImage? {
		guard data.count <= maximumEncodedBytes,
			  let source = CGImageSourceCreateWithData(data as CFData, nil),
			  let typeIdentifier = CGImageSourceGetType(source) as String?,
			  typeIdentifier == UTType.png.identifier || typeIdentifier == UTType.jpeg.identifier,
			  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
			  let width = properties[kCGImagePropertyPixelWidth] as? Int,
			  let height = properties[kCGImagePropertyPixelHeight] as? Int,
			  isDecodedSizeAllowed(width: width, height: height),
			  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
			return nil
		}
		return UIImage(cgImage: cgImage)
	}
}

// MARK: - Theme fonts

/// Resolves an edition's `theme.fonts` (Google Font *family names*, not URLs) into SwiftUI
/// fonts. A family is used only when it is actually registered on this device (bundled or
/// installed via a font provider); otherwise the system font is used. This mirrors the
/// platform-specific font resolution the cross-platform spec calls for — the payload ships a
/// family name, and each client resolves it however it can, falling back to the system font
/// (design#120 / Android #6163).
enum EventFirmwareFontResolver {

	/// Whether a font *family* is available on this device.
	static func isFamilyAvailable(_ family: String?) -> Bool {
		guard let family = family?.trimmingCharacters(in: .whitespacesAndNewlines), !family.isEmpty else {
			return false
		}
		let target = family.lowercased()
		if UIFont.familyNames.contains(where: { $0.lowercased() == target }) {
			return true
		}
		// Also accept an exact PostScript/face name (some families register only a face name).
		return UIFont(name: family, size: 12) != nil
	}

	/// A SwiftUI font for `family` at `size` (scaling with Dynamic Type relative to `textStyle`),
	/// or the system font for that text style when the family isn't available on this device.
	static func font(family: String?, size: CGFloat, relativeTo textStyle: Font.TextStyle) -> Font {
		guard isFamilyAvailable(family), let family else {
			return .system(textStyle)
		}
		// Prefer the family's first concrete face name; fall back to the family string itself.
		if let faceName = UIFont.fontNames(forFamilyName: family).first {
			return .custom(faceName, size: size, relativeTo: textStyle)
		}
		return .custom(family, size: size, relativeTo: textStyle)
	}
}
