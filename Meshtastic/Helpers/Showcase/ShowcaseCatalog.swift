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

	/// The maker's name as it brands itself, for the cards on the tables.
	var name: String {
		switch self {
		case .rak: "RAKwireless"
		case .seeed: "Seeed Studio"
		case .elecrow: "Elecrow"
		case .muzi: "muzi works"
		}
	}

	/// RAK along the front of the front table, Seeed on its riser behind, and Elecrow, whose radios
	/// are the tallest, on the higher back table, with muzi works after it. Makers that share a row
	/// stand one after the other, each behind its own brand card.
	var row: ShowcaseDisplayRow {
		switch self {
		case .rak:
			// Leaves the front table's right end for the connected radio.
			ShowcaseDisplayRow(table: .tableFront, depthOffset: 0.16, height: 0, length: 1.35, centerX: -0.22)
		case .seeed:
			ShowcaseDisplayRow(table: .tableFront, depthOffset: ShowcaseRoomGeometry.riserOffset, height: ShowcaseRoomGeometry.riserHeight, length: ShowcaseRoomGeometry.tableLength, centerX: 0)
		case .elecrow, .muzi:
			ShowcaseDisplayRow(table: .tableBack, depthOffset: 0, height: 0, length: ShowcaseRoomGeometry.tableLength, centerX: 0)
		}
	}

	/// Front of the room first.
	var displayOrder: Int {
		switch self {
		case .rak: 0
		case .seeed: 1
		case .elecrow: 2
		case .muzi: 3
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

	/// The showcase is for devices we recommend: flagship and niche. Legacy and discontinued
	/// devices are left off the tables; a record that doesn't give a level stays on.
	var isShowcased: Bool {
		guard let supportLevel, let level = SupportLevel(rawValue: supportLevel) else { return supportLevel == nil }
		return level == .flagship || level == .niche
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

	/// The model for a node's hardware: the first of its catalog images that has a model. Matched
	/// on the hardware number when known, since a node's stored name can differ from the catalog's
	/// ("RAK2560" for "WISMESH_HUB"), else on the name without underscores ("THINKNODEM1" for
	/// "THINKNODE_M1").
	static func modelName(forHardwareSlug slug: String?, number: Int? = nil, models: Set<String>, hardware: [ShowcaseHardwareRecord]) -> String? {
		guard let slug, !slug.isEmpty, slug != "UNSET" else { return nil }
		let key = normalized(slug)
		let records = number.map { number in hardware.filter { $0.hwModel == number } }.flatMap { $0.isEmpty ? nil : $0 }
			?? hardware.filter { $0.hwModelSlug.map(normalized) == key }
		for record in records {
			for image in record.images ?? [] {
				let name = (image as NSString).deletingPathExtension
				if models.contains(name) { return name }
			}
		}
		return nil
	}

	private static func normalized(_ slug: String) -> String {
		slug.replacingOccurrences(of: "_", with: "").uppercased()
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

	/// Where the connected radio stands: the front table's right end, toward the viewer.
	static let connectedRadio = SIMD3<Float>(0.7, 0, 0.16)
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
