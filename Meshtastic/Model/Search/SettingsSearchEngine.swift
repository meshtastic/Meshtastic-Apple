//
//  SettingsSearchEngine.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/13/26.
//
import Foundation

/// Matches a query against the settings index and orders what it finds.
///
/// Pure and state-free: the index is static, and everything that varies per query
/// — whether a radio is connected, what it currently holds — arrives as
/// `Availability`. That keeps ranking testable without a radio.
enum SettingsSearchEngine {

	/// What the app knows at query time. Everything here changes; the index does not.
	struct Availability {
		let isConnected: Bool
		/// Whether the connected hardware model is tagged DIY.
		let isDIYHardware: Bool
		/// Values the connected radio currently holds, keyed as the registry keys
		/// them (`"meshtastic.Config.LoRaConfig#8"`). Used to decide whether a
		/// deprecated setting is still worth showing so it can be migrated off.
		let currentValues: Set<String>

		static let disconnected = Availability(isConnected: false, isDIYHardware: false, currentValues: [])
	}

	/// Queries shorter than this match nothing. One character matches most of the
	/// index, which is noise rather than a result.
	static let minimumQueryLength = 2

	// Weights, highest first. A match in a control's own name is what a user
	// expects first, however many keywords a rival entry carries.
	private static let exactLabel = 1000
	private static let labelPrefix = 500
	private static let labelContains = 250
	private static let keywordMatch = 100
	private static let subtitleMatch = 50

	/// Results for `query`, ordered, with hidden entries removed.
	static func search(
		_ query: String,
		in index: [SettingsSearchEntry],
		availability: Availability
	) -> [SettingsSearchResult] {
		let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard trimmed.count >= minimumQueryLength else { return [] }

		var results: [SettingsSearchResult] = []
		for entry in index {
			guard let score = score(entry, for: trimmed), score > 0 else { continue }
			let visibility = visibility(for: entry, availability: availability)
			if case .hidden = visibility { continue }
			results.append(SettingsSearchResult(entry: entry, score: score, visibility: visibility))
		}

		// Ties break by section then label, so the same query always produces the
		// same list. Sorting by score alone is unstable and would reorder results
		// between keystrokes that produced identical scores.
		return results.sorted { lhs, rhs in
			if lhs.score != rhs.score { return lhs.score > rhs.score }
			if lhs.entry.listSection != rhs.entry.listSection {
				return lhs.entry.listSection.rawValue < rhs.entry.listSection.rawValue
			}
			if lhs.entry.label != rhs.entry.label { return lhs.entry.label < rhs.entry.label }
			return lhs.entry.destination.rawValue < rhs.entry.destination.rawValue
		}
	}

	/// Field-weighted score, or nil if nothing matched.
	///
	/// `localizedStandardContains` throughout: case- and diacritic-insensitive, so
	/// "resume" finds "résumé". Not `lowercased().contains`, which is neither.
	static func score(_ entry: SettingsSearchEntry, for query: String) -> Int? {
		var total = 0

		if entry.label.localizedStandardCompare(query) == .orderedSame {
			total += exactLabel
		} else if entry.label.hasPrefixStandard(query) {
			total += labelPrefix
		} else if entry.label.localizedStandardContains(query) {
			total += labelContains
		}

		if entry.keywords.contains(where: { $0.localizedStandardContains(query) }) {
			total += keywordMatch
		}

		if let subtitle = entry.subtitle, subtitle.localizedStandardContains(query) {
			total += subtitleMatch
		}

		return total > 0 ? total : nil
	}

	/// How a result should be presented, given what the app currently knows.
	static func visibility(
		for entry: SettingsSearchEntry,
		availability: Availability
	) -> SettingsSearchVisibility {
		let metadata = entry.field?.metadata

		// Deprecated settings are hidden unless the radio is actually using one, in
		// which case it needs to be findable so it can be migrated off. Mirrors the
		// rule DeviceConfig already applies to the role picker.
		if metadata?.deprecated == true {
			guard let field = entry.field,
				  availability.currentValues.contains("\(field.messageName)#\(field.tag)") else {
				return .hidden
			}
			return .deEmphasised(reason: String(
				localized: "Deprecated — move to a supported setting",
				comment: "Why a settings search result is de-emphasised"))
		}

		// The DIY tag marks a product line, not how a particular unit was assembled,
		// so this hides GPIO settings on a hand-wired commercial board. They stay
		// reachable by opening the screen. When disconnected the hardware is unknown,
		// and showing is better than hiding on an assumption.
		if metadata?.diyOnly == true, availability.isConnected, !availability.isDIYHardware {
			return .hidden
		}

		if metadata?.adminOnly == true {
			return .deEmphasised(reason: String(
				localized: "Advanced setting",
				comment: "Why a settings search result is de-emphasised"))
		}

		if entry.requiresConnection, !availability.isConnected {
			return .deEmphasised(reason: String(
				localized: "Needs a connected radio",
				comment: "Why a settings search result is de-emphasised"))
		}

		return .normal
	}
}

private extension String {
	/// Case- and diacritic-insensitive prefix test, matching the semantics of
	/// `localizedStandardContains`.
	func hasPrefixStandard(_ prefix: String) -> Bool {
		guard let range = range(of: prefix, options: [.caseInsensitive, .diacriticInsensitive]) else {
			return false
		}
		return range.lowerBound == startIndex
	}
}
