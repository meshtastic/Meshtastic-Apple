//
//  SerialConfig.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/18/26.
//
import SwiftUI
import MeshtasticProtobufs

extension ModuleConfig.SerialConfig: ConfigFormMessage {
	static let entityKeyPath: KeyPath<NodeInfoEntity, SerialConfigEntity?> = \NodeInfoEntity.serialConfig

	init(entity: SerialConfigEntity) {
		self.init()
		enabled = entity.enabled
		echo = entity.echo
		rxd = UInt32(truncatingIfNeeded: entity.rxd)
		txd = UInt32(truncatingIfNeeded: entity.txd)
		baud = Serial_Baud(rawValue: Int(entity.baudRate)) ?? .baudDefault
		timeout = UInt32(truncatingIfNeeded: entity.timeout)
		mode = Serial_Mode(rawValue: Int(entity.mode)) ?? .default
		// The old screen always wrote this false. It now round-trips from the entity.
		overrideConsoleSerialPort = entity.overrideConsoleSerialPort
	}
}

struct SerialConfig: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	let node: NodeInfoEntity?

	private typealias F = ModuleConfig.SerialConfig.Fields

	static func overlay() -> ConfigFormOverlay<ModuleConfig.SerialConfig> {
		.init(sections: [
			.init(title: String(localized: "Options", comment: "Settings section"), fields: [
				.init(F.enabled, symbol: "terminal"),
				.init(F.echo, symbol: "repeat"),
				.init(F.baud),
				.init(F.timeout, control: .options(SerialTimeoutIntervals.allCases.map {
					ConfigFormOption(value: $0.rawValue, title: $0.description)
				})),
				// The screen has always offered the six modes the app describes, not every
				// value the enum declares, so the set is unchanged.
				.init(F.mode, enumValues: { _ in SerialModeTypes.allCases.map(\.rawValue) })
			]),
			.init(title: String(localized: "GPIO", comment: "Settings section"), fields: [
				.init(F.rxd, control: .gpioPin),
				.init(F.txd, control: .gpioPin)
			])
		], omitted: [
			.init(F.overrideConsoleSerialPort, "no control; written back as stored")
		])
	}

	var body: some View {
		MetadataConfigForm(
			node: node, title: "Serial", overlay: Self.overlay(),
			request: accessoryManager.requestSerialModuleConfig,
			save: { config, from, to in
				_ = try await accessoryManager.saveSerialModuleConfig(config: config, fromUser: from, toUser: to)
			})
		.navigationTitle("Serial Config")
	}
}
