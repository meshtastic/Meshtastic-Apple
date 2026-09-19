//
//  RangeTestConfig.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/18/26.
//
import SwiftUI
import MeshtasticProtobufs

extension ModuleConfig.RangeTestConfig: ConfigFormMessage {
	static let entityKeyPath: KeyPath<NodeInfoEntity, RangeTestConfigEntity?> = \NodeInfoEntity.rangeTestConfig

	init(entity: RangeTestConfigEntity) {
		self.init()
		enabled = entity.enabled
		sender = UInt32(truncatingIfNeeded: entity.sender)
		save = entity.save
	}
}

struct RangeTestConfig: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	let node: NodeInfoEntity?

	private typealias F = ModuleConfig.RangeTestConfig.Fields

	/// The primary channel is effectively unencrypted: no key, or the one-byte default.
	/// Range test on such a channel floods the public mesh, so the form refuses.
	private var isPrimaryChannelPublic: Bool {
		guard let channels = node?.myInfo?.channels,
			  let primary = channels.first(where: { $0.index == 0 && $0.role > 0 }) else { return false }
		return (primary.psk?.hexDescription.count ?? 0) < 3
	}

	static func overlay() -> ConfigFormOverlay<ModuleConfig.RangeTestConfig> {
		.init(sections: [
			.init(title: String(localized: "Options", comment: "Settings section"), fields: [
				.init(F.enabled, symbol: "figure.walk"),
				.init(F.sender, control: .interval(.rangeTestSender)),
				// The CSV is served by the device's web server, which needs WiFi.
				.init(F.save, symbol: "square.and.arrow.down.fill", enabledWhen: .hasWifi)
			])
		], omitted: [
			.init(F.clearOnReboot_p, "no control in the app; not persisted by the entity, so saved as the proto default as before")
		])
	}

	var body: some View {
		MetadataConfigForm(
			node: node, title: "Range", overlay: Self.overlay(),
			request: accessoryManager.requestRangeTestModuleConfig,
			save: { config, from, to in
				_ = try await accessoryManager.saveRangeTestModuleConfig(config: config, fromUser: from, toUser: to)
			},
			leading: { _ in
				if isPrimaryChannelPublic {
					Section {
						Label("Range test requires an encrypted private channel. The primary channel on this node is using a default or empty key.", systemImage: "lock.open.fill")
							.font(.callout)
							.foregroundColor(.orange)
					}
				} else if accessoryManager.isConnected, node != nil, node?.rangeTestConfig == nil {
					Section {
						Label("Range test configuration has not been received from the radio. Try reconnecting to the device.", systemImage: "exclamationmark.triangle.fill")
							.font(.callout)
							.foregroundColor(.orange)
					}
				}
			})
		.disabled(isPrimaryChannelPublic)
		.navigationTitle("Range Test Config")
	}
}
