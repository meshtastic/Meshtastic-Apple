//
//  PaxCounterConfig.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/18/26.
//
import SwiftUI
import MeshtasticProtobufs

extension ModuleConfig.PaxcounterConfig: ConfigFormMessage {
	static let entityKeyPath: KeyPath<NodeInfoEntity, PaxCounterConfigEntity?> = \NodeInfoEntity.paxCounterConfig

	init(entity: PaxCounterConfigEntity) {
		self.init()
		enabled = entity.enabled
		paxcounterUpdateInterval = UInt32(truncatingIfNeeded: entity.updateInterval)
		wifiThreshold = entity.wifiThreshold
		bleThreshold = entity.bleThreshold
	}
}

struct PaxCounterConfig: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	let node: NodeInfoEntity?

	private typealias F = ModuleConfig.PaxcounterConfig.Fields

	static func overlay() -> ConfigFormOverlay<ModuleConfig.PaxcounterConfig> {
		.init(sections: [
			.init(fields: [
				.init(F.enabled, symbol: "figure.walk.motion"),
				// A stored zero means the firmware default; the controls show what that
				// default is, and leaving them alone still saves zero.
				.init(F.paxcounterUpdateInterval, shownWhen: .isTrue(F.enabled), control: .interval(.paxCounter), displayDefault: 3600),
				.init(F.wifiThreshold, symbol: "wifi", shownWhen: .isTrue(F.enabled), displayDefault: -80),
				.init(F.bleThreshold, symbol: "antenna.radiowaves.left.and.right", shownWhen: .isTrue(F.enabled), displayDefault: -80)
			])
		])
	}

	var body: some View {
		// The old screen watched the wrong config for its remote-admin banner
		// (`\.powerConfig`); the form reads its own entity key path, so that is fixed here.
		MetadataConfigForm(
			node: node, title: "PAX Counter Config", overlay: Self.overlay(),
			request: accessoryManager.requestPaxCounterModuleConfig,
			save: { config, from, to in
				_ = try await accessoryManager.savePaxcounterModuleConfig(config: config, fromUser: from, toUser: to)
			})
		.navigationTitle("PAX Counter Config")
	}
}
