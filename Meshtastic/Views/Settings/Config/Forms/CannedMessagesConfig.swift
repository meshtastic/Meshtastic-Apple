//
//  CannedMessagesConfig.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/18/26.
//
import SwiftUI
import MeshtasticProtobufs

extension ModuleConfig.CannedMessageConfig: ConfigFormMessage {
	static let entityKeyPath: KeyPath<NodeInfoEntity, CannedMessageConfigEntity?> = \NodeInfoEntity.cannedMessageConfig

	init(entity: CannedMessageConfigEntity) {
		self.init()
		rotary1Enabled = entity.rotary1Enabled
		updown1Enabled = entity.updown1Enabled
		inputbrokerPinA = UInt32(truncatingIfNeeded: entity.inputbrokerPinA)
		inputbrokerPinB = UInt32(truncatingIfNeeded: entity.inputbrokerPinB)
		inputbrokerPinPress = UInt32(truncatingIfNeeded: entity.inputbrokerPinPress)
		inputbrokerEventCw = InputEventChar(rawValue: Int(entity.inputbrokerEventCw)) ?? .none
		inputbrokerEventCcw = InputEventChar(rawValue: Int(entity.inputbrokerEventCcw)) ?? .none
		inputbrokerEventPress = InputEventChar(rawValue: Int(entity.inputbrokerEventPress)) ?? .none
		sendBell = entity.sendBell
		// `enabled` and `allow_input_source` are deprecated with no successor and are not
		// written (#2021, #2022); the input source is governed by the two flags above.
	}
}

/// The module config is one admin message and the messages themselves are another, so
/// the messages live beside the form and are sent only when they changed.
struct CannedMessagesConfig: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	let node: NodeInfoEntity?

	@State private var preset: ConfigPresets = .unset
	@State private var messages = ""
	@State private var loadedMessages = ""

	private typealias F = ModuleConfig.CannedMessageConfig.Fields
	static let messagesByteCap = 200

	/// A preset fills in the control type, pins and key mapping for known hardware.
	static func apply(_ preset: ConfigPresets, to config: inout ModuleConfig.CannedMessageConfig) {
		switch preset {
		case .unset:
			return
		case .rakRotaryEncoder:
			config.updown1Enabled = true
			config.rotary1Enabled = false
			config.inputbrokerPinA = 4
			config.inputbrokerPinB = 10
			config.inputbrokerPinPress = 9
			config.inputbrokerEventCw = .down
			config.inputbrokerEventCcw = .up
			config.inputbrokerEventPress = .select
		case .cardKB:
			config.updown1Enabled = false
			config.rotary1Enabled = false
			config.inputbrokerPinA = 0
			config.inputbrokerPinB = 0
			config.inputbrokerPinPress = 0
			config.inputbrokerEventCw = .none
			config.inputbrokerEventCcw = .none
			config.inputbrokerEventPress = .none
		}
	}

	/// What a save has to send. The module config and the messages travel as separate
	/// admin messages, so sending one whose contents did not change is a wasted round
	/// trip to the radio — and sending the messages through the config operation would
	/// not store them at all.
	static func pending(
		config: ModuleConfig.CannedMessageConfig,
		stored: CannedMessageConfigEntity?,
		messages: String,
		loadedMessages: String
	) -> (config: Bool, messages: Bool) {
		let configChanged = stored.map { config != ModuleConfig.CannedMessageConfig(entity: $0) } ?? true
		return (configChanged, messages != loadedMessages)
	}

	static func overlay(preset: ConfigPresets = .unset) -> ConfigFormOverlay<ModuleConfig.CannedMessageConfig> {
		// With a preset chosen its fields are shown but not editable, as before.
		let manual = ConfigFormCondition<ModuleConfig.CannedMessageConfig>.environment { _ in preset == .unset }
		return .init(sections: [
			.init(title: String(localized: "Options", comment: "Settings section"), fields: [
				.init(F.sendBell, symbol: "bell")
			]),
			.init(title: String(localized: "Control Type", comment: "Settings section"), enabledWhen: manual, fields: [
				.init(F.rotary1Enabled, symbol: "dial.min", enabledWhen: .isFalse(F.updown1Enabled)),
				.init(F.updown1Enabled, symbol: "arrow.up.arrow.down", enabledWhen: .isFalse(F.rotary1Enabled))
			]),
			.init(title: String(localized: "Inputs", comment: "Settings section"), enabledWhen: manual, fields: [
				.init(F.inputbrokerPinA, control: .gpioPin),
				.init(F.inputbrokerPinB, control: .gpioPin),
				.init(F.inputbrokerPinPress, control: .gpioPin)
			]),
			.init(title: String(localized: "Key Mapping", comment: "Settings section"), enabledWhen: manual, fields: [
				.init(F.inputbrokerEventCw),
				.init(F.inputbrokerEventCcw),
				.init(F.inputbrokerEventPress)
			])
		])
	}

	var body: some View {
		MetadataConfigForm(
			node: node, title: "Canned Messages", overlay: Self.overlay(preset: preset),
			externalChanges: messages != loadedMessages,
			request: accessoryManager.requestCannedMessagesModuleConfig,
			save: { config, from, to in
				let pending = Self.pending(config: config, stored: node?.cannedMessageConfig,
										   messages: messages, loadedMessages: loadedMessages)
				if pending.config {
					_ = try await accessoryManager.saveCannedMessageModuleConfig(config: config, fromUser: from, toUser: to)
				}
				if pending.messages {
					_ = try await accessoryManager.saveCannedMessageModuleMessages(messages: messages, fromUser: from, toUser: to)
					loadedMessages = messages
				}
			},
			leading: { config in
				Section(header: Text("Messages")) {
					HStack {
						Label("Messages", systemImage: "message.fill")
						TextField("Messages separate with |", text: $messages, axis: .vertical)
							.foregroundColor(.gray)
							.autocorrectionDisabled()
							.textInputAutocapitalization(.never)
							.onChange(of: messages) { _, new in
								var trimmed = new
								while trimmed.utf8.count > Self.messagesByteCap { trimmed = String(trimmed.dropLast()) }
								if trimmed != new { messages = trimmed }
							}
					}
				}
				Section(header: Text("Presets")) {
					Picker("Configuration Presets", selection: $preset) {
						ForEach(ConfigPresets.allCases) { Text($0.description).tag($0) }
					}
					.onChange(of: preset) { _, new in Self.apply(new, to: &config.wrappedValue) }
				}
			})
		.navigationTitle("Canned Messages Config")
		.onAppear {
			messages = node?.cannedMessageConfig?.messages ?? ""
			loadedMessages = messages
		}
	}
}
