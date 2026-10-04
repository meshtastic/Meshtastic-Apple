//
//  AudioConfig.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/19/26.
//
import SwiftUI
import MeshtasticProtobufs

extension ModuleConfig.AudioConfig: ConfigFormMessage {
	static let entityKeyPath: KeyPath<NodeInfoEntity, AudioConfigEntity?> = \NodeInfoEntity.audioConfig

	init(entity: AudioConfigEntity) {
		self.init()
		codec2Enabled = entity.codec2Enabled
		pttPin = UInt32(truncatingIfNeeded: entity.pttPin)
		bitrate = Audio_Baud(rawValue: Int(entity.bitrate)) ?? .codec2Default
		i2SWs = UInt32(truncatingIfNeeded: entity.i2sWs)
		i2SSd = UInt32(truncatingIfNeeded: entity.i2sSd)
		i2SDin = UInt32(truncatingIfNeeded: entity.i2sDin)
		i2SSck = UInt32(truncatingIfNeeded: entity.i2sSck)
	}
}

struct AudioConfig: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	let node: NodeInfoEntity?

	private typealias F = ModuleConfig.AudioConfig.Fields

	static func overlay() -> ConfigFormOverlay<ModuleConfig.AudioConfig> {
		let usingCodec2 = ConfigFormCondition<ModuleConfig.AudioConfig>.isTrue(F.codec2Enabled)
		return .init(sections: [
			.init(title: String(localized: "Options", comment: "Settings section"), fields: [
				.init(F.codec2Enabled, symbol: "waveform")
			]),
			.init(title: String(localized: "Codec2 Settings", comment: "Settings section"),
				  shownWhen: usingCodec2, fields: [
				.init(F.bitrate)
			]),
			.init(title: String(localized: "GPIO Configuration", comment: "Settings section"),
				  shownWhen: usingCodec2, fields: [
				.init(F.pttPin, symbol: "button.horizontal", control: .gpioPin),
				.init(F.i2SWs, symbol: "point.3.connected.trianglepath.dotted", control: .gpioPin),
				.init(F.i2SSd, symbol: "point.3.connected.trianglepath.dotted", control: .gpioPin),
				.init(F.i2SDin, symbol: "point.3.connected.trianglepath.dotted", control: .gpioPin),
				.init(F.i2SSck, symbol: "point.3.connected.trianglepath.dotted", control: .gpioPin)
			])
		])
	}

	var body: some View {
		MetadataConfigForm(
			node: node, title: "Audio", overlay: Self.overlay(),
			request: accessoryManager.requestAudioModuleConfig,
			save: { config, from, to in
				_ = try await accessoryManager.saveAudioModuleConfig(config: config, fromUser: from, toUser: to)
			})
		.navigationTitle("Audio Config")
	}
}
