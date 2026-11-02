//
//  RadioSetupDonePage.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/2/26.
//

import SwiftUI

/// What the radio is set to now.
struct RadioSetupDonePage: View {
	let model: RadioSetupModel
	let onDone: () -> Void

	var body: some View {
		OnboardingPage(
			title: String(localized: "You're All Set", comment: "Radio setup done title"),
			footer: String(localized: "Change any of these in Settings.", comment: "Radio setup done footer"),
			buttonTitle: String(localized: "Done"),
			action: { onDone() }
		) {
			OnboardingFeatureRow(
				symbol: "globe.americas.fill",
				color: .red,
				title: String(localized: "Region", comment: "Radio setup row title"),
				text: model.region?.description ?? String(localized: "Not set", comment: "Radio setup summary")
			)
			OnboardingFeatureRow(
				symbol: "dot.radiowaves.left.and.right",
				title: String(localized: "Preset", comment: "Radio setup row title"),
				text: model.presetSummary
			)
			if !model.isLicensed {
				OnboardingFeatureRow(
					symbol: "person.crop.circle",
					color: .indigo,
					title: String(localized: "Name", comment: "Radio setup row title"),
					text: model.nameSummary
				)
			}
		}
	}
}
