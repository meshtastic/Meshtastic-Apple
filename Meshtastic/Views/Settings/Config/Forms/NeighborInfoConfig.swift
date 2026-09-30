//
//  NeighborInfoConfig.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/18/26.
//
import SwiftUI
import MeshtasticProtobufs

extension ModuleConfig.NeighborInfoConfig: ConfigFormMessage {
	static let entityKeyPath: KeyPath<NodeInfoEntity, NeighborInfoConfigEntity?> = \NodeInfoEntity.neighborInfoConfig

	init(entity: NeighborInfoConfigEntity) {
		self.init()
		enabled = entity.enabled
		updateInterval = UInt32(truncatingIfNeeded: entity.updateInterval)
		transmitOverLora = entity.transmitOverLora
	}
}

struct NeighborInfoConfig: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	let node: NodeInfoEntity?

	private typealias F = ModuleConfig.NeighborInfoConfig.Fields

	static func overlay() -> ConfigFormOverlay<ModuleConfig.NeighborInfoConfig> {
		.init(sections: [
			.init(title: String(localized: "Options", comment: "Settings section"), fields: [
				.init(F.enabled, symbol: "network")
			]),
			.init(title: String(localized: "Settings", comment: "Settings section"), shownWhen: .isTrue(F.enabled), fields: [
				// A stored 0 means the firmware default of four hours; the picker shows
				// that, and leaving it alone still saves 0.
				.init(F.updateInterval, control: .interval(.neighborInfo), displayDefault: 14400),
				.init(F.transmitOverLora, symbol: "antenna.radiowaves.left.and.right")
			])
		])
	}

	var body: some View {
		MetadataConfigForm(
			node: node, title: "Neighbor Info", overlay: Self.overlay(),
			request: accessoryManager.requestNeighborInfoModuleConfig,
			save: { config, from, to in
				_ = try await accessoryManager.saveNeighborInfoModuleConfig(config: config, fromUser: from, toUser: to)
			})
		.navigationTitle("Neighbor Info Config")
	}
}
