//
//  RadioSetupIntroPage.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/2/26.
//

import SwiftUI

/// The first page: which radio this is and what the next pages set.
struct RadioSetupIntroPage: View {
	let model: RadioSetupModel
	let onNotNow: () -> Void

	var body: some View {
		OnboardingPage(
			title: String(localized: "Set Up Your Radio", comment: "Radio setup intro title"),
			intro: AttributedString(localized: "A few settings get your radio talking on the mesh. You can change them later in Settings.", comment: "Radio setup intro"),
			buttonTitle: String(localized: "Get started"),
			secondaryButtonTitle: String(localized: "Not Now", comment: "Radio setup; closes the flow"),
			secondaryAction: onNotNow,
			action: { model.advance(from: .intro) }
		) {
			if let hardwareModelId = model.hardwareModelId {
				DeviceHardwareImage(hwId: hardwareModelId)
					.frame(maxWidth: .infinity)
					.frame(height: 160)
					.accessibilityHidden(true)
			}
			OnboardingFeatureRow(
				symbol: "cpu",
				color: .gray,
				title: model.deviceName,
				text: model.radioSummary ?? String(localized: "Connected radio", comment: "Radio setup; name shown when the radio has none")
			)
			OnboardingFeatureRow(
				symbol: "globe.americas.fill",
				color: .red,
				title: String(localized: "Region", comment: "Radio setup row title"),
				text: String(localized: "Where you are, so the radio uses legal frequencies.", comment: "Radio setup intro row")
			)
			OnboardingFeatureRow(
				symbol: "dot.radiowaves.left.and.right",
				title: String(localized: "Preset", comment: "Radio setup row title"),
				text: String(localized: "The range and speed your mesh uses.", comment: "Radio setup intro row")
			)
			if !model.isLicensed {
				OnboardingFeatureRow(
					symbol: "person.crop.circle",
					color: .indigo,
					title: String(localized: "Name", comment: "Radio setup row title"),
					text: String(localized: "How your radio shows up for others.", comment: "Radio setup intro row")
				)
			}
		}
	}
}
