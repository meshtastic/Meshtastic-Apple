//
//  EstimateCoverageButton.swift
//  Meshtastic
//
//  "Estimate Coverage" node-detail action (spec 015, US1, FR-001). Shown by the caller
//  only when the node has a known position — see NodeDetail.actionsSection's
//  `if let latestPosition { ... }` gate, matching NavigateToButton's existing pattern.
//
//  Prefill (FR-003) uses `connectedNode`'s LoRa config, not `node`'s own — the estimate
//  answers "if my connected radio broadcast from this site's position," not "if a radio
//  matching this remote node's self-reported config did." `node` supplies only the
//  position and display name.
//

import SwiftUI

struct EstimateCoverageButton: View {
	var node: NodeInfoEntity
	var connectedNode: NodeInfoEntity?
	@State private var isPresentingForm = false

	var body: some View {
		Button {
			isPresentingForm = true
		} label: {
			Label {
				Text("Estimate Coverage")
			} icon: {
				Image(systemName: "antenna.radiowaves.left.and.right")
					.symbolRenderingMode(.hierarchical)
			}
		}
		.sheet(isPresented: $isPresentingForm) {
			CoverageEstimateForm(initialParameters: prefilledParameters())
		}
	}

	// MARK: - Prefill (FR-003)

	private var primaryChannelName: String {
		if let primary = connectedNode?.myInfo?.channels.first(where: { $0.index == 0 || $0.role == 1 }),
		   let name = primary.name, !name.isEmpty {
			return name
		}
		if connectedNode?.loRaConfig?.usePreset == false { return "Custom" }
		guard let preset = ModemPresets(rawValue: Int(connectedNode?.loRaConfig?.modemPreset ?? 0)) else { return "LongFast" }
		return preset.androidChannelName
	}

	private func prefilledParameters() -> CoverageEstimateParameters {
		let position = node.latestPosition
		let loRaConfig = connectedNode?.loRaConfig
		let region = RegionCodes(rawValue: Int(loRaConfig?.regionCode ?? 0)) ?? .unset
		let preset = ModemPresets(rawValue: Int(loRaConfig?.modemPreset ?? 0)) ?? .longFast

		let calculator = LoRaChannelCalculator(config: loRaConfig)
		let slot = calculator.effectiveChannelSlot(primaryName: primaryChannelName)
		let frequency = calculator.radioFrequencyMHz(slot: slot)

		var params = CoverageEstimateParameters(
			name: node.user?.displayLongName ?? "Site".localized,
			latitude: position?.latitude ?? 0,
			longitude: position?.longitude ?? 0,
			transmitPowerWatts: LoRaRFHelpers.transmitPowerWatts(txPowerDBm: loRaConfig?.txPower ?? 0, region: region),
			transmitFrequencyMHz: frequency > 0 ? frequency : 915
		)
		params.receiverSensitivityDBm = LoRaRFHelpers.receiverSensitivityDBm(for: preset)
		return params
	}
}
