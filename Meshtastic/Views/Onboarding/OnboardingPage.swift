//
//  OnboardingPage.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/1/26.
//
//  A setup page in the style of Apple's "What's New" sheets: a centered title, an
//  optional one-paragraph intro, feature rows, an optional footnote, and one prominent
//  button pinned at the bottom. Holds no flow state; the caller supplies the rows and
//  the button's work.
//

import SwiftUI

struct OnboardingPage<Rows: View>: View {
	let title: String
	let intro: AttributedString?
	let footer: String?
	let buttonTitle: String
	/// False keeps the main button disabled: a choice the page needs has not been made.
	let isContinueEnabled: Bool
	/// Shown above the footer, in orange. A failed save says why here and the page stays.
	let errorMessage: String?
	/// A plain button under the main one: Skip, Not Now.
	let secondaryButtonTitle: String?
	let secondaryAction: (() -> Void)?
	let action: () async -> Void
	let rows: () -> Rows

	/// Set while `action` runs so a second tap cannot run it again. A page that pushes
	/// the next step would otherwise push it twice.
	@State private var isWorking = false

	init(
		title: String,
		intro: AttributedString? = nil,
		footer: String? = nil,
		buttonTitle: String = String(localized: "Continue"),
		isContinueEnabled: Bool = true,
		errorMessage: String? = nil,
		secondaryButtonTitle: String? = nil,
		secondaryAction: (() -> Void)? = nil,
		action: @escaping () async -> Void,
		@ViewBuilder rows: @escaping () -> Rows
	) {
		self.title = title
		self.intro = intro
		self.footer = footer
		self.buttonTitle = buttonTitle
		self.isContinueEnabled = isContinueEnabled
		self.errorMessage = errorMessage
		self.secondaryButtonTitle = secondaryButtonTitle
		self.secondaryAction = secondaryAction
		self.action = action
		self.rows = rows
	}

	var body: some View {
		VStack(spacing: 0) {
			ScrollView(.vertical) {
				VStack(spacing: 28) {
					Text(title)
						.font(.largeTitle.bold())
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: false, vertical: true)
						.frame(maxWidth: .infinity)
						.padding(.top, 32)
					if let intro {
						Text(intro)
							.font(.body)
							.multilineTextAlignment(.center)
							.fixedSize(horizontal: false, vertical: true)
							.frame(maxWidth: 560)
					}
					VStack(alignment: .leading, spacing: 24) {
						rows()
					}
					// Long lines read badly on an iPad or Mac window, so the rows keep a
					// phone-like measure and sit centered.
					.frame(maxWidth: 560)
				}
				.padding(.horizontal, 24)
				.padding(.bottom, 16)
			}
			VStack(spacing: 12) {
				if let errorMessage {
					Label {
						Text(errorMessage)
					} icon: {
						Image(systemName: "exclamationmark.triangle.fill")
					}
					.foregroundStyle(.orange)
					.font(.callout)
					.multilineTextAlignment(.leading)
					.fixedSize(horizontal: false, vertical: true)
					.frame(maxWidth: 480)
					.padding(.horizontal, 24)
				}
				if let footer {
					Text(footer)
						.font(.footnote)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: false, vertical: true)
						.frame(maxWidth: 480)
						.padding(.horizontal, 24)
				}
				Button {
					guard !isWorking else { return }
					isWorking = true
					Task {
						await action()
						isWorking = false
					}
				} label: {
					Text(buttonTitle)
						.frame(maxWidth: 400)
				}
				.capsuleButtonStyle()
				.disabled(isWorking || !isContinueEnabled)
				if let secondaryButtonTitle, let secondaryAction {
					Button(action: secondaryAction) {
						// The label is the tap target, so it carries the minimum height.
						Text(secondaryButtonTitle)
							.font(.body)
							.frame(minHeight: 44)
							.padding(.horizontal, 24)
					}
					.disabled(isWorking)
				}
			}
			.padding(.bottom)
		}
	}
}

#Preview("Welcome") {
	OnboardingPage(
		title: "Welcome to Meshtastic",
		footer: "Meshtastic does not collect any personal information. We do anonymously collect usage and crash data to improve the app.",
		buttonTitle: "Get started",
		action: {}
	) {
		OnboardingFeatureRow(
			symbol: "antenna.radiowaves.left.and.right",
			color: .green,
			title: "Off-Grid Messaging",
			text: "Send text, positions and more over LoRa radios. No cell service or internet needed."
		)
		OnboardingFeatureRow(
			symbol: "lock.shield",
			title: "Privacy First",
			text: "Channels are encrypted. Your radio shares no location until you turn it on."
		)
	}
}
