//
//  StoreForwardConfig.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/18/26.
//
import SwiftUI
import MeshtasticProtobufs

extension ModuleConfig.StoreForwardConfig: ConfigFormMessage {
	static let entityKeyPath: KeyPath<NodeInfoEntity, StoreForwardConfigEntity?> = \NodeInfoEntity.storeForwardConfig

	init(entity: StoreForwardConfigEntity) {
		self.init()
		enabled = entity.enabled
		heartbeat = entity.heartbeat
		records = UInt32(truncatingIfNeeded: entity.records)
		historyReturnMax = UInt32(truncatingIfNeeded: entity.historyReturnMax)
		historyReturnWindow = UInt32(truncatingIfNeeded: entity.historyReturnWindow)
		// The entity names this isRouter; the proto field is is_server.
		isServer = entity.isRouter
	}
}

struct StoreForwardConfig: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	let node: NodeInfoEntity?

	private typealias F = ModuleConfig.StoreForwardConfig.Fields

	private static let counts: [ConfigFormOption] = [
		ConfigFormOption(value: 0, title: String(localized: "Unset", comment: "Picker option")),
		ConfigFormOption(value: 25, title: "25"),
		ConfigFormOption(value: 50, title: "50"),
		ConfigFormOption(value: 75, title: "75"),
		ConfigFormOption(value: 100, title: "100")
	]

	private static let windows: [ConfigFormOption] = [
		ConfigFormOption(value: 0, title: String(localized: "Unset", comment: "Picker option")),
		ConfigFormOption(value: 60, title: String(localized: "One Minute", comment: "Interval option")),
		ConfigFormOption(value: 300, title: String(localized: "Five Minutes", comment: "Interval option")),
		ConfigFormOption(value: 600, title: String(localized: "Ten Minutes", comment: "Interval option")),
		ConfigFormOption(value: 900, title: String(localized: "Fifteen Minutes", comment: "Interval option")),
		ConfigFormOption(value: 1800, title: String(localized: "Thirty Minutes", comment: "Interval option")),
		ConfigFormOption(value: 3600, title: String(localized: "One Hour", comment: "Interval option")),
		ConfigFormOption(value: 7200, title: String(localized: "Two Hours", comment: "Interval option"))
	]

	static func overlay() -> ConfigFormOverlay<ModuleConfig.StoreForwardConfig> {
		.init(sections: [
			.init(title: String(localized: "Options", comment: "Settings section"), fields: [
				.init(F.enabled, symbol: "envelope.arrow.triangle.branch")
			]),
			.init(title: String(localized: "Settings", comment: "Settings section"), shownWhen: .isTrue(F.enabled), fields: [
				.init(F.heartbeat, symbol: "waveform.path.ecg"),
				.init(F.records, control: .options(counts)),
				.init(F.historyReturnMax, control: .options(counts)),
				.init(F.historyReturnWindow, control: .options(windows))
			]),
			.init(title: String(localized: "Server Option", comment: "Settings section"), shownWhen: .isTrue(F.enabled), fields: [
				.init(F.isServer, symbol: "server.rack")
			])
		])
	}

	var body: some View {
		MetadataConfigForm(
			node: node, title: "Store & Forward", overlay: Self.overlay(),
			request: accessoryManager.requestStoreAndForwardModuleConfig,
			save: { config, from, to in
				_ = try await accessoryManager.saveStoreForwardModuleConfig(config: config, fromUser: from, toUser: to)
			},
			trailing: { config in
				if config.wrappedValue.enabled && config.wrappedValue.isServer {
					Section {
						Text("Store and forward servers require an ESP32 device with PSRAM or Linux Native.")
							.font(.callout)
							.foregroundColor(.gray)
					}
				}
			})
		.navigationTitle("Store & Forward Config")
	}
}
