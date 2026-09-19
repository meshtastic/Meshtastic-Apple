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
private struct AmbientColorPicker: View {
	@Binding var config: ModuleConfig.AmbientLightingConfig
	@Environment(\.self) private var environment
	@State private var color: Color = .white

	var body: some View {
		HStack {
			Image(systemName: "eyedropper")
				.foregroundColor(.accentColor)
				.accessibilityHidden(true)
			ColorPicker(String(localized: "Color", comment: "Ambient LED colour"), selection: $color, supportsOpacity: false)
		}
		.onAppear {
			color = Color(red: Double(config.red) / 255, green: Double(config.green) / 255, blue: Double(config.blue) / 255)
		}
		.onChange(of: color) { _, new in
			let c = new.resolve(in: environment)
			let (r, g, b) = (UInt32((c.red * 255).rounded()), UInt32((c.green * 255).rounded()), UInt32((c.blue * 255).rounded()))
			if (r, g, b) != (config.red, config.green, config.blue) {
				config.red = r; config.green = g; config.blue = b
			}
		}
	}
}
