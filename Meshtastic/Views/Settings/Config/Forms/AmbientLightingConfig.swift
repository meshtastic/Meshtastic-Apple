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

/// Converting between the picker's colour and the radio's three 0-255 channels.
///
/// Its own type so the conversion can be tested directly. A test that repeats the
/// arithmetic instead passes whether or not the clamp and the rounding are still here.
enum AmbientChannels {

	/// The colour the radio is currently showing.
	static func color(red: UInt32, green: UInt32, blue: UInt32) -> Color {
		Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
	}

	/// One resolved colour component as the radio wants it.
	///
	/// The picker works in the display's colour space and the radio takes 0-255 sRGB, so a
	/// wide-gamut colour resolves outside that range — P3 pure green comes back with red at
	/// about -0.51. Rounding that without clamping traps on the conversion to UInt32.
	static func level(_ value: Float) -> UInt32 {
		UInt32(min(255, max(0, (value * 255).rounded())))
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
			get: { AmbientChannels.color(red: config.red, green: config.green, blue: config.blue) },
			set: { picked in
				let resolved = picked.resolve(in: environment)
				config.red = AmbientChannels.level(resolved.red)
				config.green = AmbientChannels.level(resolved.green)
				config.blue = AmbientChannels.level(resolved.blue)
			}
		)
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
