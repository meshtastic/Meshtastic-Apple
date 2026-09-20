//
//  TAKModuleConfig.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/19/26.
//
import SwiftUI
import MeshtasticProtobufs

extension ModuleConfig.TAKConfig: ConfigFormMessage {
	static let entityKeyPath: KeyPath<NodeInfoEntity, TAKConfigEntity?> = \NodeInfoEntity.takConfig

	init(entity: TAKConfigEntity) {
		self.init()
		team = Team(rawValue: Int(entity.team)) ?? .unspecifedColor
		role = MemberRole(rawValue: Int(entity.role)) ?? .unspecifed
	}
}

struct TAKModuleConfig: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	let node: NodeInfoEntity?

	private typealias F = ModuleConfig.TAKConfig.Fields

	/// Whether this node is set to a role that actually sends TAK position reports.
	/// Not a reason to hide the screen, but a reason to say so: the settings save and
	/// persist either way, they just have nothing to travel on until the role changes.
	private var actsAsTAKNode: Bool {
		guard let role = node?.deviceConfig?.role ?? node?.user?.role,
			  let deviceRole = DeviceRoles(rawValue: Int(role)) else { return true }
		return deviceRole == .tak || deviceRole == .takTracker
	}

	static func overlay() -> ConfigFormOverlay<ModuleConfig.TAKConfig> {
		.init(sections: [
			.init(title: String(localized: "Identity", comment: "Settings section"),
				  footer: String(localized: "These values are included in TAK position reports. Leaving either at its default lets the firmware choose Cyan and Team Member.",
								 comment: "TAK identity section footer"),
				  fields: [
				.init(F.team, symbol: "paintpalette"),
				.init(F.role, symbol: "person.badge.shield.checkmark")
			])
		])
	}

	var body: some View {
		MetadataConfigForm(
			node: node, title: "TAK", overlay: Self.overlay(),
			request: accessoryManager.requestTAKModuleConfig,
			save: { config, from, to in
				_ = try await accessoryManager.saveTAKModuleConfig(config: config, fromUser: from, toUser: to)
			},
			leading: { _ in
				if !actsAsTAKNode {
					Section {
						Label {
							Text("These settings only apply when the device role is TAK or TAK Tracker.")
						} icon: {
							Image(systemName: "exclamationmark.triangle")
						}
						.font(.callout)
						.foregroundColor(.orange)
					}
				}
			})
		.navigationTitle("TAK Config")
	}
}
