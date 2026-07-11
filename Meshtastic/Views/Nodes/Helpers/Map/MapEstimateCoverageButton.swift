//
//  MapEstimateCoverageButton.swift
//  Meshtastic
//
//  Map-toolbar "Estimate Coverage" control (spec 015, US2, FR-002). Unlike
//  EstimateCoverageButton (node-detail, US1), this isn't tied to any specific node —
//  it prefills from the current map view center, falling back to the connected radio's
//  own position, then to Seattle, so the form never opens with an unset/null position.
//  Radio-characteristic prefill (FR-003) still comes from the connected node, same as US1.
//

import SwiftUI
import MapKit

struct MapEstimateCoverageButton: View {
	var visibleCenter: CLLocationCoordinate2D?
	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@State private var isPresentingForm = false

	private var connectedNode: NodeInfoEntity? {
		guard let num = accessoryManager.activeDeviceNum else { return nil }
		return getNodeInfo(id: num, context: context)
	}

	var body: some View {
		Button {
			isPresentingForm = true
		} label: {
			Image(systemName: "antenna.radiowaves.left.and.right")
		}
		.help("Estimate Coverage") // Design Standards §5: tooltip for icon-only controls (Catalyst/Mac).
		.sheet(isPresented: $isPresentingForm) {
			CoverageEstimateForm(initialParameters: prefilledParameters())
		}
	}

	// MARK: - Prefill (FR-002 position, FR-003 radio characteristics)

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
		// FR-002: prefer the current map view center; fall back to the connected radio's
		// own reported position; then to a fixed default rather than (0, 0).
		let coordinate = visibleCenter
			?? connectedNode?.latestPosition?.nodeCoordinate
			?? CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321) // Seattle

		let loRaConfig = connectedNode?.loRaConfig
		let region = RegionCodes(rawValue: Int(loRaConfig?.regionCode ?? 0)) ?? .unset
		let preset = ModemPresets(rawValue: Int(loRaConfig?.modemPreset ?? 0)) ?? .longFast

		let calculator = LoRaChannelCalculator(config: loRaConfig)
		let slot = calculator.effectiveChannelSlot(primaryName: primaryChannelName)
		let frequency = calculator.radioFrequencyMHz(slot: slot)

		var params = CoverageEstimateParameters(
			name: "Site".localized,
			latitude: coordinate.latitude,
			longitude: coordinate.longitude,
			transmitPowerWatts: LoRaRFHelpers.transmitPowerWatts(txPowerDBm: loRaConfig?.txPower ?? 0, region: region),
			transmitFrequencyMHz: frequency > 0 ? frequency : 915
		)
		params.receiverSensitivityDBm = LoRaRFHelpers.receiverSensitivityDBm(for: preset)
		return params
	}
}
