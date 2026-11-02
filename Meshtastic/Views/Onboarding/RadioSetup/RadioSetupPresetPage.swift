//
//  RadioSetupPresetPage.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/2/26.
//

import SwiftUI

/// Picks the modem preset and writes the LoRa config. The one save of region and preset.
struct RadioSetupPresetPage: View {
	let model: RadioSetupModel
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Environment(\.modelContext) private var context

	private var regionInfo: RegionPresetInfo? {
		guard model.supports2_8 else { return nil }
		return accessoryManager.loRaRegionPresets[model.draft.region]
	}

	private var selection: Binding<Int> {
		Binding(
			get: { model.draft.modemPreset.rawValue },
			set: { if let preset = ModemPresets(rawValue: $0) { model.selectPreset(preset) } })
	}

	/// The radio's own default for the region, when it sent a map.
	private var recommendation: String? {
		guard let info = regionInfo, let region = model.region,
			  let preset = ModemPresets(rawValue: info.defaultPreset.rawValue) else { return nil }
		return String.localizedStringWithFormat(
			String(localized: "Recommended for %@: %@", comment: "Radio setup preset row; region, then preset"),
			region.description, preset.description)
	}

	private var footer: String? {
		guard model.restartsOnLoRaSave else { return nil }
		return String(localized: "Your radio restarts to apply this and reconnects in a few seconds.", comment: "Radio setup preset footer")
	}

	var body: some View {
		OnboardingPage(
			title: String(localized: "Choose a Preset", comment: "Radio setup preset title"),
			intro: AttributedString(localized: "Presets trade range for speed. Long Range reaches farther and Short Range sends faster. Everyone on a mesh must use the same one.", comment: "Radio setup preset intro"),
			footer: footer,
			buttonTitle: model.hasLoRaChanges
				? String(localized: "Save and Continue", comment: "Radio setup button")
				: String(localized: "Continue"),
			errorMessage: model.saveError,
			action: {
				if await model.saveLoRa(using: accessoryManager, context: context) {
					model.advance(from: .preset)
				}
			}
		) {
			OnboardingControlRow(symbol: "dot.radiowaves.left.and.right", title: String(localized: "Preset", comment: "Radio setup row title"), text: recommendation) {
				Picker(String(localized: "Preset", comment: "Radio setup row title"), selection: selection) {
					ForEach(model.availablePresets(regionInfo: regionInfo)) { preset in
						Text(preset.description).tag(preset.rawValue)
					}
				}
				.labelsHidden()
			}
			if let warning = model.usBandwidthWarning {
				OnboardingFeatureRow(symbol: "exclamationmark.triangle.fill", color: .orange, text: warning)
			}
			if !model.draft.usePreset {
				OnboardingFeatureRow(
					symbol: "slider.horizontal.3",
					color: .orange,
					title: String(localized: "Custom Modem Settings", comment: "Radio setup preset page row title"),
					text: String(localized: "Your radio uses its own bandwidth, spread factor and coding rate. They stay until you choose a preset here.", comment: "Radio setup preset page row")
				)
			}
		}
	}
}
