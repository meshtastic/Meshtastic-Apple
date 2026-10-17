//
//  ShowcaseCatalog.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
import Foundation
import simd
@preconcurrency import SwiftData

/// The makers the showcase shows. The raw value is the hardware catalog's tag for the maker.
enum ShowcaseVendor: String, CaseIterable, Sendable {
	case rak = "RAK"
	case seeed = "Seeed"
	case elecrow = "Elecrow"
	case muzi = "muzi"
	case heltec = "Heltec"
	case lilygo = "LilyGo"

	/// The maker's name as it brands itself, for the cards on the tables.
	var name: String {
		switch self {
		case .rak: "RAKwireless"
		case .seeed: "Seeed Studio"
		case .elecrow: "Elecrow"
		case .muzi: "muzi works"
		case .heltec: "Heltec"
		case .lilygo: "LILYGO"
		}
	}

	/// RAK on the front table with muzi works after it, then Seeed, Elecrow, Heltec and LILYGO, one
	/// table each toward the back wall. Makers that share a row stand one after the other, each
	/// behind its own brand card.
	var row: ShowcaseDisplayRow {
		switch self {
		case .rak, .muzi: Self.row(on: .table1)
		case .seeed: Self.row(on: .table2)
		case .elecrow: Self.row(on: .table3)
		case .heltec: Self.row(on: .table4)
		case .lilygo: Self.row(on: .table5)
		}
	}

	private static func row(on table: ShowcaseAnchor) -> ShowcaseDisplayRow {
		ShowcaseDisplayRow(table: table, depthOffset: 0, height: 0, length: ShowcaseRoomGeometry.tableLength, centerX: 0)
	}

	/// Front of the room first.
	var displayOrder: Int {
		switch self {
		case .rak: 0
		case .muzi: 1
		case .seeed: 2
		case .elecrow: 3
		case .heltec: 4
		case .lilygo: 5
		}
	}

	/// The vendor from a hardware record's tags, or from the model's name when untagged.
	static func from(tags: [String], modelName: String) -> ShowcaseVendor? {
		for tag in tags {
			if let vendor = ShowcaseVendor.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(tag) == .orderedSame }) {
				return vendor
			}
		}
		let name = modelName.lowercased()
		if name.hasPrefix("rak") { return .rak }
		if name.hasPrefix("thinknode") || name.hasPrefix("crowpanel") { return .elecrow }
		if name.hasPrefix("seeed") || name.hasPrefix("wio") || name.hasPrefix("tracker-t1000") { return .seeed }
		if name.hasPrefix("muzi") { return .muzi }
		if name.hasPrefix("heltec") { return .heltec }
		if name.hasPrefix("lilygo") || name.hasPrefix("t-") || name.hasPrefix("tbeam") || name.hasPrefix("tlora")
			|| name.hasPrefix("tdeck") || name.hasPrefix("t5s3") || name.hasPrefix("techo") || name.hasPrefix("mini-epaper") {
			return .lilygo
		}
		return nil
	}
}

/// A device in the hardware catalog, as much of it as the showroom needs.
struct ShowcaseHardwareRecord: Codable, Equatable, Sendable {
	let hwModel: Int?
	let hwModelSlug: String?
	let platformioTarget: String?
	let displayName: String?
	let tags: [String]?
	let images: [String]?
	/// `SupportLevel`'s raw value; nil when the catalog doesn't say.
	var supportLevel: Int?

	/// The showcase is for devices we recommend, so legacy and discontinued devices are left off
	/// the tables. Everything else stays on: flagship and niche, a record that doesn't give a
	/// level, and a level newer than this build knows.
	var isShowcased: Bool {
		guard let supportLevel, let level = SupportLevel(rawValue: supportLevel) else { return true }
		return level != .legacy && level != .discontinued
	}
}

/// One model on a display table: an example of a device, not a node on the mesh.
struct ShowcaseItem: Identifiable, Equatable, Sendable {
	/// The model's file name without extension, the same as its SVG's.
	let id: String
	let vendor: ShowcaseVendor
	/// The devices drawn with this model, e.g. a board sold bare and in a kit.
	let deviceNames: [String]
	/// Their firmware targets, which the purchase links are keyed by.
	let targets: [String]
	/// What tells this model apart from others drawn for the same devices, e.g. a screen size or
	/// "case"; nil when it is the only one.
	var variant: String?

	var title: String {
		let name = deviceNames.first ?? id
		return variant.map { "\(name) (\($0))" } ?? name
	}

	/// The title without the maker in front, for a card that names the maker above it. The
	/// catalog's names are uneven: "Seeed Card Tracker T1000-E" has it, "ThinkNode M2" doesn't.
	var nameWithoutMaker: String {
		let prefix = vendor.rawValue + " "
		guard title.count > prefix.count, title.lowercased().hasPrefix(prefix.lowercased()) else { return title }
		return String(title.dropFirst(prefix.count))
	}
}

enum ShowcaseCatalog {
	/// The models there are, matched to the catalog's devices. A device uses a model when the model
	/// is named after its firmware target, or else when the model is one of its images (a model can
	/// arrive before the catalog points the device at its image). Models no device uses are left
	/// out, as are models from other makers and models whose devices are all legacy or
	/// discontinued. Sorted by vendor, then name.
	static func items(models: Set<String>, hardware: [ShowcaseHardwareRecord]) -> [ShowcaseItem] {
		let modelKeys = Set(models.map { $0.lowercased() })
		let hardware = hardware.filter(\.isShowcased)
		// Models that are some device's own, by firmware target.
		let ownModels = Set(hardware.compactMap { $0.platformioTarget?.lowercased() }).intersection(modelKeys)
		var items: [ShowcaseItem] = []
		for model in models {
			let key = model.lowercased()
			let devices = hardware.filter { record in
				let target = record.platformioTarget?.lowercased()
				if target == key { return true }
				// A device with a model of its own isn't listed under another device's model it
				// shares an image with, but is under its own variants (a board and its case).
				if let target, modelKeys.contains(target), ownModels.contains(key) { return false }
				return (record.images ?? []).contains("\(model).svg")
			}
			guard !devices.isEmpty,
				  let vendor = devices.lazy.compactMap({ ShowcaseVendor.from(tags: $0.tags ?? [], modelName: model) }).first
			else { continue }
			// The device named after the model first, then the rest alphabetically.
			let ordered = devices.sorted { lhs, rhs in
				let lhsExact = lhs.platformioTarget?.lowercased() == key, rhsExact = rhs.platformioTarget?.lowercased() == key
				if lhsExact != rhsExact { return lhsExact }
				return (lhs.displayName ?? "") < (rhs.displayName ?? "")
			}
			var names: [String] = []
			for name in ordered.compactMap(\.displayName) where !names.contains(name) {
				names.append(name)
			}
			items.append(ShowcaseItem(
				id: model,
				vendor: vendor,
				deviceNames: names,
				targets: Array(Set(ordered.compactMap(\.platformioTarget))).sorted()
			))
		}
		// Models drawn for the same devices are told apart by the rest of their names.
		for group in Dictionary(grouping: items.indices, by: { items[$0].deviceNames }).values where group.count > 1 {
			for (index, variant) in zip(group, variants(of: group.map { items[$0].id })) {
				items[index].variant = variant
			}
		}
		return items.sorted { lhs, rhs in
			if lhs.vendor != rhs.vendor { return lhs.vendor.displayOrder < rhs.vendor.displayOrder }
			return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
		}
	}

	/// What follows the words the names share: "crowpanel_2_4" and "crowpanel_2_8" give "2.4" and
	/// "2.8"; "rak4631" and "rak4631_case" give nil and "case".
	static func variants(of names: [String]) -> [String?] {
		let words = names.map { $0.split(whereSeparator: { $0 == "_" || $0 == "-" }).map(String.init) }
		var shared = 0
		// Only words with letters are shared; a size like "2_4" stays whole.
		while let first = words.first, shared < first.count, first[shared].contains(where: \.isLetter),
			  words.allSatisfy({ shared < $0.count && $0[shared] == first[shared] }) {
			shared += 1
		}
		return words.map { name in
			let rest = Array(name.dropFirst(shared))
			guard !rest.isEmpty else { return nil }
			return rest.allSatisfy({ $0.allSatisfy(\.isNumber) }) ? rest.joined(separator: ".") : rest.joined(separator: " ")
		}
	}

	/// The catalog the app keeps fresh from the API, or the one bundled with it when that is empty.
	static func hardware(in container: ModelContainer) async -> [ShowcaseHardwareRecord] {
		let reader = await Task.detached { ShowcaseHardwareReader(modelContainer: container) }.value
		let stored = await reader.records()
		return stored.isEmpty ? bundledHardware() : stored
	}

	/// The hardware catalog bundled with the app.
	static func bundledHardware(in bundle: Bundle = .main) -> [ShowcaseHardwareRecord] {
		guard let url = bundle.url(forResource: "DeviceHardware", withExtension: "json"),
			  let data = try? Data(contentsOf: url) else { return [] }
		return (try? JSONDecoder().decode([ShowcaseHardwareRecord].self, from: data)) ?? []
	}

	/// The models bundled with the app (visionOS builds only).
	static func bundledModels(in bundle: Bundle = .main) -> Set<String> {
		Set((bundle.urls(forResourcesWithExtension: "usdz", subdirectory: nil) ?? []).map {
			$0.deletingPathExtension().lastPathComponent
		})
	}
}

/// A run of a display table that one maker's models stand along, in the table's own space:
/// `depthOffset` toward the viewer from the table's middle, `height` above its top (the riser),
/// and `length` of table centered at `centerX`.
struct ShowcaseDisplayRow: Equatable, Sendable {
	let table: ShowcaseAnchor
	let depthOffset: Float
	let height: Float
	let length: Float
	let centerX: Float

}

/// Spreads a row's models along it: the space left over is shared out evenly, between the models
/// and at both ends.
enum ShowcaseRowPacking {
	/// The center of each model along a row of `length`, measured from the row's middle. When the
	/// models are wider than the row they touch and run past its ends, centered.
	static func centers(widths: [Float], length: Float) -> [Float] {
		guard !widths.isEmpty else { return [] }
		let total = widths.reduce(0, +)
		let gap = max(0, (length - total) / Float(widths.count + 1))
		var x = -(total + gap * Float(widths.count - 1)) / 2
		return widths.map { width in
			defer { x += width + gap }
			return x + width / 2
		}
	}
}

/// Reads the hardware catalog out of SwiftData on its own context, off the main actor.
@ModelActor
actor ShowcaseHardwareReader {
	func records() -> [ShowcaseHardwareRecord] {
		let devices = (try? modelContext.fetch(FetchDescriptor<DeviceHardwareEntity>())) ?? []
		return devices.map { device in
			ShowcaseHardwareRecord(
				hwModel: Int(device.hwModel),
				hwModelSlug: device.hwModelSlug,
				platformioTarget: device.platformioTarget,
				displayName: device.displayName,
				tags: device.tags.map(\.tag),
				images: device.images.compactMap(\.fileName),
				supportLevel: device.supportLevel
			)
		}
	}
}
