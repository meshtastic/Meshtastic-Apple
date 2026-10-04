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

	/// Uppercased hardware model slugs carrying the `DIY` tag, or nil when the
	/// catalogue could not be read. Nil is "we do not know", and is kept distinct
	/// from an empty set, which would mean "nothing is DIY".
	private static let catalogue: Set<String>? = load()

	/// True if `slug` names a DIY-tagged model.
	///
	/// When the catalogue is unavailable this answers true, so that nothing is hidden
	/// on a guess: the only consumer hides DIY-only settings when this is false, and
	/// "we do not know" must not produce the same result as "not DIY". An absent slug
	/// is not DIY — callers should only ask when a radio is actually connected.
	static func isDIY(slug: String?) -> Bool {
		isDIY(slug: slug, in: catalogue)
	}

	/// The rule with the catalogue injected, so the unavailable case can be tested.
	static func isDIY(slug: String?, in catalogue: Set<String>?) -> Bool {
		guard let catalogue else { return true }
		guard let slug, !slug.isEmpty else { return false }
		return catalogue.contains(slug.uppercased())
	}

	private static func load() -> Set<String>? {
		guard let url = Bundle.main.url(forResource: "DeviceHardware", withExtension: "json"),
			  let data = try? Data(contentsOf: url) else {
			Logger.data.warning("DeviceHardware.json missing; DIY-only settings stay visible")
			return nil
		}
		struct Entry: Decodable {
			let hwModelSlug: String?
			let tags: [String]?
		}
		guard let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
			Logger.data.warning("DeviceHardware.json could not be decoded; DIY-only settings stay visible")
			return nil
		}
		return Set(
			entries
				.filter { ($0.tags ?? []).contains { $0.caseInsensitiveCompare("DIY") == .orderedSame } }
				.compactMap { $0.hwModelSlug?.uppercased() }
		)
	}
}
