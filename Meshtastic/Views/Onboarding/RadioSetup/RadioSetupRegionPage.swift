//
//  RadioSetupRegionPage.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/2/26.
//

import SwiftUI

/// Confirms or picks the LoRa region. The draft starts on the region the phone's region
/// setting points at when the radio has none. Continue waits for a region this app can
/// write back.
struct RadioSetupRegionPage: View {
	let model: RadioSetupModel
	@EnvironmentObject private var accessoryManager: AccessoryManager

	/// The radio's legal-preset map for a region; only 2.8 radios send one.
	private func regionInfo(for region: RegionCodes) -> RegionPresetInfo? {
		guard model.supports2_8 else { return nil }
		return accessoryManager.loRaRegionPresets[region.protoEnumValue()]
	}

	private var selection: Binding<Int> {
		Binding(
			get: { model.draft.region.rawValue },
			set: { raw in
				guard let region = RegionCodes(rawValue: raw), region != .unset else { return }
				model.selectRegion(region, regionInfo: regionInfo(for: region))
			})
	}

	private var footer: String? {
		guard let region = model.region, region.dutyCycle > 0, region.dutyCycle < 100 else { return nil }
		return String.localizedStringWithFormat(
			String(localized: "This region has an hourly duty cycle of %lld%%.", comment: "Radio setup region footer"),
			Int64(region.dutyCycle))
	}

	private var title: String {
		model.suggestedRegion != nil
			? String(localized: "Confirm Your Region", comment: "Radio setup region title when one was pre-selected")
			: String(localized: "Choose Your Region", comment: "Radio setup region title")
	}

	private var intro: AttributedString {
		model.suggestedRegion != nil
			? AttributedString(localized: "Picked from your phone's region setting. Your radio must use the frequencies allowed where you are, so change it if you are somewhere else.", comment: "Radio setup region intro when one was pre-selected")
			: AttributedString(localized: "Your radio must use the frequencies allowed where you are. With the wrong region nothing nearby will hear you.", comment: "Radio setup region intro")
	}

	var body: some View {
		OnboardingPage(
			title: title,
			intro: intro,
			footer: footer,
			isContinueEnabled: model.hasChosenRegion,
			action: { model.advance(from: .region) }
		) {
			OnboardingControlRow(symbol: "globe.americas.fill", color: .red, title: String(localized: "Region", comment: "Radio setup row title")) {
				Picker(String(localized: "Region", comment: "Radio setup row title"), selection: selection) {
					if model.draft.region == .unset {
						Text("Choose a region").tag(RegionCodes.unset.rawValue)
					}
					ForEach(RegionCodes.selectable(supports2_8: model.supports2_8).filter { $0 != .unset }) { region in
						Text(region.description).tag(region.rawValue)
					}
				}
				.labelsHidden()
			}
			if !model.isRegionSupported {
				UnsupportedRegionNotice()
			}
			if let region = model.region, regionInfo(for: region)?.licensedOnly == true {
				LicensedBandNotice(isLicensed: model.isLicensed)
			}
		}
	}
}
