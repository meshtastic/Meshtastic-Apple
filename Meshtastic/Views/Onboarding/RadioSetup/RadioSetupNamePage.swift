//
//  RadioSetupNamePage.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/2/26.
//

import SwiftUI

/// Sets the long and short names other people see. Skippable.
struct RadioSetupNamePage: View {
	let model: RadioSetupModel
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Environment(\.modelContext) private var context

	// Limited through the bindings rather than onChange, so the stored names are never
	// shortened before the user touches them.
	private var longName: Binding<String> {
		Binding(get: { model.longName }, set: { model.setLongName($0) })
	}

	private var shortName: Binding<String> {
		Binding(get: { model.shortName }, set: { model.setShortName($0) })
	}

	var body: some View {
		OnboardingPage(
			title: String(localized: "Name Your Radio", comment: "Radio setup name title"),
			intro: AttributedString(localized: "Other people see these in their node lists and on the map.", comment: "Radio setup name intro"),
			footer: String(localized: "The short name shows in your node's circle: up to 4 characters or one emoji.", comment: "Radio setup name footer"),
			buttonTitle: model.hasNameChanges
				? String(localized: "Save and Continue", comment: "Radio setup button")
				: String(localized: "Continue"),
			isContinueEnabled: model.canSaveName,
			errorMessage: model.saveError,
			secondaryButtonTitle: String(localized: "Skip"),
			secondaryAction: { model.advance(from: .name) },
			action: {
				if await model.saveName(using: accessoryManager, context: context) {
					model.advance(from: .name)
				}
			}
		) {
			OnboardingControlRow(
				symbol: "person.crop.rectangle.fill",
				color: .indigo,
				title: String(localized: "Long Name"),
				text: String.localizedStringWithFormat(String(localized: "Long Name can be up to %lld bytes long."), Int64(model.longNameLimit)),
				placement: .below
			) {
				TextField(String(localized: "Long Name"), text: longName)
					.textFieldStyle(.roundedBorder)
					.disableAutocorrection(true)
			}
			OnboardingControlRow(symbol: "circlebadge.fill", color: .indigo, title: String(localized: "Short Name"), placement: .below) {
				HStack(spacing: 12) {
					CircleText(text: model.shortName, color: .accentColor, circleSize: 44)
						.accessibilityHidden(true)
					TextField(String(localized: "Short Name"), text: shortName)
						.textFieldStyle(.roundedBorder)
						.disableAutocorrection(true)
				}
			}
			if model.isAwaitingReconnect {
				OnboardingFeatureRow(
					symbol: "antenna.radiowaves.left.and.right",
					color: .orange,
					title: String(localized: "Waiting for your radio to reconnect", comment: "Radio setup name page"),
					text: String(localized: "Your radio is restarting with its new LoRa settings. Saving the name works once it is back.", comment: "Radio setup name page")
				)
			}
		}
	}
}
