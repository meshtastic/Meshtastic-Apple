//
//  DIYHardware.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/13/26.
//
import Foundation
import OSLog

/// Which hardware models are tagged DIY in the bundled device catalogue.
///
/// Read once from `DeviceHardware.json` — the same file that seeds
/// `DeviceHardwareEntity` — rather than fetched from SwiftData, because this is
/// consulted for every search result and a fetch per keystroke would not do.
///
/// The tag marks a product LINE, not how a particular unit was assembled. A
/// hand-wired board reporting a commercial model is tagged as that model, so this
/// is a hint, not a fact. Spec 019 FR-012a takes that trade deliberately: it hides
/// GPIO settings from search on commercial hardware, and they stay reachable by
/// opening the screen.
enum DIYHardware {

	/// Uppercased hardware model slugs carrying the `DIY` tag.
	static let slugs: Set<String> = load()

	/// True if `slug` names a DIY-tagged model. An unknown or absent slug is not
	/// DIY — but callers should only ask when a radio is actually connected, since
	/// "we do not know" and "not DIY" are different answers.
	static func isDIY(slug: String?) -> Bool {
		guard let slug, !slug.isEmpty else { return false }
		return slugs.contains(slug.uppercased())
	}

	private static func load() -> Set<String> {
		guard let url = Bundle.main.url(forResource: "DeviceHardware", withExtension: "json"),
			  let data = try? Data(contentsOf: url) else {
			Logger.data.warning("DeviceHardware.json missing; treating no hardware as DIY")
			return []
		}
		struct Entry: Decodable {
			let hwModelSlug: String?
			let tags: [String]?
		}
		guard let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
			Logger.data.warning("DeviceHardware.json could not be decoded; treating no hardware as DIY")
			return []
		}
		return Set(
			entries
				.filter { ($0.tags ?? []).contains { $0.caseInsensitiveCompare("DIY") == .orderedSame } }
				.compactMap { $0.hwModelSlug?.uppercased() }
		)
	}
}
