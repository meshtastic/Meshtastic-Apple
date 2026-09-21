//
//  AmbientLightingConfig.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/18/26.
//
import SwiftUI
import MeshtasticProtobufs

extension ModuleConfig.AmbientLightingConfig: ConfigFormMessage {
	static let entityKeyPath: KeyPath<NodeInfoEntity, AmbientLightingConfigEntity?> = \NodeInfoEntity.ambientLightingConfig

	init(entity: AmbientLightingConfigEntity) {
		self.init()
		ledState = entity.ledState
		current = UInt32(truncatingIfNeeded: entity.current)
		red = UInt32(truncatingIfNeeded: entity.red)
		green = UInt32(truncatingIfNeeded: entity.green)
		blue = UInt32(truncatingIfNeeded: entity.blue)
	}
}

struct AmbientLightingConfig: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	let node: NodeInfoEntity?

	private typealias F = ModuleConfig.AmbientLightingConfig.Fields

	static func overlay() -> ConfigFormOverlay<ModuleConfig.AmbientLightingConfig> {
		.init(sections: [
			.init(title: String(localized: "Options", comment: "Settings section"), fields: [
				.init(F.ledState, symbol: "lightbulb.led"),
				// One colour picker writes all three channels; it is laid out on `red` and
				// the other two are omitted below.
				.init(F.red, control: .custom { config in AnyView(AmbientColorPicker(config: config)) }),
				// The registry bounds this 0-31, so the automatic control is a stepper.
				.init(F.current, symbol: "directcurrent")
			])
		], omitted: [
			.init(F.green, "edited through the colour picker on red"),
			.init(F.blue, "edited through the colour picker on red")
		])
	}

	var body: some View {
		MetadataConfigForm(
			node: node, title: "Ambient Lighting", overlay: Self.overlay(),
			request: accessoryManager.requestAmbientLightingConfig,
			save: { config, from, to in
				_ = try await accessoryManager.saveAmbientLightingModuleConfig(config: config, fromUser: from, toUser: to)
			})
		.navigationTitle("Ambient Lighting Config")
	}
}

/// The LED colour as one control over the message's red, green and blue channels.
///
/// The color is read from and written to the message directly. Nothing is kept here:
/// this row appears before the form has loaded the config, so a copy taken on appear
/// would start at a default and then be written back over the values that arrived.
private struct AmbientColorPicker: View {
	@Binding var config: ModuleConfig.AmbientLightingConfig
	@Environment(\.self) private var environment

	private var color: Binding<Color> {
		Binding(
			get: {
				Color(red: Double(config.red) / 255,
					  green: Double(config.green) / 255,
					  blue: Double(config.blue) / 255)
			},
			set: { picked in
				let resolved = picked.resolve(in: environment)
				config.red = level(resolved.red)
				config.green = level(resolved.green)
				config.blue = level(resolved.blue)
			}
		)
	}

	/// The picker works in the display's color space and the radio takes 0-255 sRGB,
	/// so a wide-gamut color resolves outside that range and is clamped into it.
	private func level(_ value: Float) -> UInt32 {
		UInt32(min(255, max(0, (value * 255).rounded())))
	}

	var body: some View {
		HStack {
			Image(systemName: "eyedropper")
				.foregroundColor(.accentColor)
				.accessibilityHidden(true)
			ColorPicker(String(localized: "Color", comment: "Ambient LED colour"), selection: color, supportsOpacity: false)
		}
	}
}
