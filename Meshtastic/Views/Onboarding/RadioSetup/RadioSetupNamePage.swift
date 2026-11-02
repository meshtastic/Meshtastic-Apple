//
//  RadioSetupNamePage.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/2/26.
//

import SwiftUI

/// Sets the long and short names other people see: the node's circle as a live preview
/// over a grouped form of the two names. Skippable.
struct RadioSetupNamePage: View {
	let model: RadioSetupModel
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Environment(\.modelContext) private var context
	@ScaledMetric(relativeTo: .largeTitle) private var previewSize: CGFloat = 96

	// Limited through the bindings rather than onChange, so the stored names are never
	// shortened before the user touches them.
	private var longName: Binding<String> {
		Binding(get: { model.longName }, set: { model.setLongName($0) })
	}

	private var shortName: Binding<String> {
		Binding(get: { model.shortName }, set: { model.setShortName($0) })
	}

	/// The same color the node lists give this node's circle.
	private var nodeColor: Color {
		Color(UIColor(hex: UInt32(truncatingIfNeeded: model.nodeNum)))
	}

	var body: some View {
		OnboardingPage(
			title: String(localized: "Name Your Radio", comment: "Radio setup name title"),
			intro: AttributedString(localized: "Other people see these in their node lists and on the map.", comment: "Radio setup name intro"),
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
			// The circle other people see, following the short name as it is typed.
			CircleText(text: model.shortName.isEmpty ? "?" : model.shortName, color: nodeColor, circleSize: previewSize)
				.frame(maxWidth: .infinity)
				.accessibilityHidden(true)
			VStack(spacing: 0) {
				NameRow(title: String(localized: "Long Name"), text: longName)
				Divider()
					.padding(.leading, 16)
				NameRow(title: String(localized: "Short Name"), text: shortName)
			}
			.background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
			VStack(alignment: .leading, spacing: 4) {
				Text(String.localizedStringWithFormat(String(localized: "Long Name can be up to %lld bytes long."), Int64(model.longNameLimit)))
				Text("The short name shows in your node's circle: up to 4 characters or one emoji.", comment: "Radio setup name footer")
			}
			.font(.footnote)
			.foregroundStyle(.secondary)
			.fixedSize(horizontal: false, vertical: true)
			.padding(.horizontal, 16)
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

/// One row of the names form: the label, and the field at the trailing edge. At
/// accessibility sizes the field goes under the label so neither is squeezed.
private struct NameRow: View {
	let title: String
	@Binding var text: String
	@Environment(\.dynamicTypeSize) private var dynamicTypeSize

	var body: some View {
		let stacked = dynamicTypeSize.isAccessibilitySize
		let layout = stacked
			? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
			: AnyLayout(HStackLayout(spacing: 12))
		layout {
			Text(title)
				.font(.body)
			TextField(title, text: $text)
				.multilineTextAlignment(stacked ? .leading : .trailing)
				.disableAutocorrection(true)
				.frame(minHeight: 44)
		}
		.padding(.horizontal, 16)
		.padding(.vertical, stacked ? 8 : 0)
	}
}
