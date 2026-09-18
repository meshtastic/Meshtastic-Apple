//
//  ExternalNotificationConfig.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/18/26.
//
import SwiftUI
import MeshtasticProtobufs

extension ModuleConfig.ExternalNotificationConfig: ConfigFormMessage {
	static let entityKeyPath: KeyPath<NodeInfoEntity, ExternalNotificationConfigEntity?> = \NodeInfoEntity.externalNotificationConfig

	init(entity: ExternalNotificationConfigEntity) {
		self.init()
		enabled = entity.enabled
		usePwm = entity.usePWM
		alertBell = entity.alertBell
		alertBellBuzzer = entity.alertBellBuzzer
		alertBellVibra = entity.alertBellVibra
		alertMessage = entity.alertMessage
		alertMessageBuzzer = entity.alertMessageBuzzer
		alertMessageVibra = entity.alertMessageVibra
		active = entity.active
		output = UInt32(truncatingIfNeeded: entity.output)
		outputBuzzer = UInt32(truncatingIfNeeded: entity.outputBuzzer)
		outputVibra = UInt32(truncatingIfNeeded: entity.outputVibra)
		outputMs = UInt32(truncatingIfNeeded: entity.outputMilliseconds)
		nagTimeout = UInt32(truncatingIfNeeded: entity.nagTimeout)
		useI2SAsBuzzer = entity.useI2SAsBuzzer
	}
}

struct ExternalNotificationConfig: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	let node: NodeInfoEntity?

	private typealias F = ModuleConfig.ExternalNotificationConfig.Fields

	static func overlay() -> ConfigFormOverlay<ModuleConfig.ExternalNotificationConfig> {
		.init(sections: [
			.init(title: String(localized: "Options", comment: "Settings section"), fields: [
				.init(F.enabled, symbol: "megaphone"),
				.init(F.alertBell, symbol: "bell"),
				.init(F.alertMessage, symbol: "message"),
				.init(F.usePwm, symbol: "light.beacon.max.fill"),
				.init(F.useI2SAsBuzzer, symbol: "light.beacon.max.fill")
			]),
			.init(title: String(localized: "Primary GPIO", comment: "Settings section"), fields: [
				.init(F.active, symbol: "togglepower"),
				.init(F.output, control: .gpioPin),
				.init(F.outputMs, control: .options(OutputIntervals.allCases.map {
					ConfigFormOption(value: $0.rawValue, title: $0.description)
				})),
				.init(F.nagTimeout, control: .interval(.nagTimeout))
			]),
			.init(title: String(localized: "Optional GPIO", comment: "Settings section"), fields: [
				.init(F.alertBellBuzzer, symbol: "bell"),
				.init(F.alertBellVibra, symbol: "bell"),
				.init(F.alertMessageBuzzer, symbol: "message"),
				.init(F.alertMessageVibra, symbol: "message"),
				.init(F.outputBuzzer, control: .gpioPin),
				.init(F.outputVibra, control: .gpioPin)
			])
		])
	}

	var body: some View {
		MetadataConfigForm(
			node: node, title: "External Notification", overlay: Self.overlay(),
			request: accessoryManager.requestExternalNotificationModuleConfig,
			save: { config, from, to in
				_ = try await accessoryManager.saveExternalNotificationModuleConfig(config: config, fromUser: from, toUser: to)
			})
		.navigationTitle("External Notification Config")
	}
}
