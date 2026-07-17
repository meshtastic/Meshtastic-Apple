//
//  DeviceHardwareEntity.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/10/25.
//

import Foundation
import SwiftData

@Model
final class DeviceHardwareEntity {
	var activelySupported: Bool = false
	var architecture: String?
	var displayName: String?
	var hasInkHud: Bool = false
	var hasMui: Bool = false
	var hwModel: Int64 = 0
	var hwModelSlug: String?
	var key: String?
	var partitionScheme: String?
	var platformioTarget: String?
	var requiresDfu: Bool = false
	var supportLevel: Int = 0
	var variant: String?

	@Relationship(deleteRule: .nullify, inverse: \DeviceHardwareImageEntity.device)
	var images: [DeviceHardwareImageEntity] = []

	@Relationship(deleteRule: .nullify, inverse: \DeviceHardwareTagEntity.devices)
	var tags: [DeviceHardwareTagEntity] = []

	init() {}
}

/// A target-specific entry from the device-hardware catalog.
///
/// Firmware targets are not a one-to-one representation of the radio hardware model reported
/// over the mesh protocol: multiple targets can intentionally report the same `hwModel`.
struct HardwareCatalogRecord: Equatable {
	let hwModel: Int64
	let hwModelSlug: String?
	let platformioTarget: String?
	let displayName: String?
	let activelySupported: Bool
	let supportLevel: SupportLevel
	let architecture: String?

	init(
		hwModel: Int64,
		hwModelSlug: String?,
		platformioTarget: String?,
		displayName: String?,
		activelySupported: Bool,
		supportLevel: SupportLevel,
		architecture: String? = nil
	) {
		self.hwModel = hwModel
		self.hwModelSlug = hwModelSlug
		self.platformioTarget = platformioTarget
		self.displayName = displayName
		self.activelySupported = activelySupported
		self.supportLevel = supportLevel
		self.architecture = architecture
	}

	init(_ entity: DeviceHardwareEntity) {
		self.init(
			hwModel: entity.hwModel,
			hwModelSlug: entity.hwModelSlug,
			platformioTarget: entity.platformioTarget,
			displayName: entity.displayName,
			activelySupported: entity.activelySupported,
			supportLevel: SupportLevel(rawValue: entity.supportLevel) ?? .discontinued,
			architecture: entity.architecture
		)
	}
}

/// Safe presentation metadata for a radio that only reports a protobuf `HardwareModel`.
///
/// Target-specific values are omitted when the protocol cannot distinguish the catalog variants.
struct HardwareCatalogPresentation: Equatable {
	let displayName: String?
	let platformioTarget: String?
	let activelySupported: Bool?
	let supportLevel: SupportLevel?
	let architecture: String?
}

enum HardwareCatalogResolver {
	static func presentation(for hwModel: Int64, in entities: [DeviceHardwareEntity]) -> HardwareCatalogPresentation? {
		presentation(for: hwModel, in: entities.map(HardwareCatalogRecord.init))
	}

	static func presentation(for hwModel: Int64, in records: [HardwareCatalogRecord]) -> HardwareCatalogPresentation? {
		let matches = records.filter { $0.hwModel == hwModel }
		guard !matches.isEmpty else { return nil }

		if matches.count == 1, let record = matches.first {
			return presentation(for: record)
		}

		let canonicalTargets = matches.filter { record in
			guard let target = record.platformioTarget,
			      let slug = record.hwModelSlug else { return false }
			return target == normalizedTarget(from: slug)
		}
		if canonicalTargets.count == 1, let canonical = canonicalTargets.first {
			return presentation(for: canonical)
		}

		// The radio protocol cannot supply target-level identity. Present the most desirable
		// catalog entry consistently instead of letting database/query order pick one at random.
		let preferred = matches.sorted(by: isPreferred(_:over:)).first!
		return presentation(for: preferred)
	}

	private static func presentation(for record: HardwareCatalogRecord) -> HardwareCatalogPresentation {
		HardwareCatalogPresentation(
			displayName: record.displayName,
			platformioTarget: record.platformioTarget,
			activelySupported: record.activelySupported,
			supportLevel: record.supportLevel,
			architecture: record.architecture
		)
	}

	private static func normalizedTarget(from hardwareModelSlug: String) -> String {
		hardwareModelSlug.lowercased().replacingOccurrences(of: "_", with: "-")
	}

	private static func isPreferred(_ lhs: HardwareCatalogRecord, over rhs: HardwareCatalogRecord) -> Bool {
		if lhs.supportLevel != rhs.supportLevel {
			return lhs.supportLevel.rawValue < rhs.supportLevel.rawValue
		}
		if lhs.activelySupported != rhs.activelySupported {
			return lhs.activelySupported
		}
		if lhs.displayName != rhs.displayName {
			return isPreferred(lhs.displayName, over: rhs.displayName)
		}
		return isPreferred(lhs.platformioTarget, over: rhs.platformioTarget)
	}

	private static func isPreferred(_ lhs: String?, over rhs: String?) -> Bool {
		switch (lhs, rhs) {
		case let (lhs?, rhs?):
			return lhs < rhs
		case (.some, nil):
			return true
		case (nil, .some), (nil, nil):
			return false
		}
	}
}
