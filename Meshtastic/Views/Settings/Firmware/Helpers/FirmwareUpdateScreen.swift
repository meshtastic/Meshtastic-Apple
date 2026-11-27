//
//  FirmwareUpdateScreen.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/27/26.
//

import OSLog
import SwiftUI

/// The frame every firmware screen shares: a sheet as tall as its content, a close button,
/// the grouped background, and the screen kept on while it's open.
struct FirmwareUpdateScreen<Content: View>: View {
	let title: Text
	/// Called by the close button. The screen decides whether to ask first.
	let onClose: () -> Void
	/// Whether a swipe down can close the sheet. Off while something is being written.
	var allowsSwipeToClose = true
	@ViewBuilder let content: Content

	/// Height of everything under the navigation bar, so the sheet can be just that tall.
	@State private var contentHeight: CGFloat = 0
	/// The inline navigation bar above the content.
	private static var navigationBarHeight: CGFloat { 64 }

	var body: some View {
		SheetNavigationStack {
			ScrollView {
				VStack(spacing: 20) {
					content
				}
				// Rounded rectangles, not the default capsule, to match the rest of the app.
				.buttonBorderShape(.roundedRectangle(radius: 12))
				.padding(20)
				.frame(maxWidth: 560)
				.frame(maxWidth: .infinity)
				.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
			}
			#if targetEnvironment(macCatalyst)
			// Catalyst can clamp the sheet shorter than the content; keep the scroll bar showing
			// so the cut-off edge reads as scrollable.
			.scrollIndicators(.visible)
			#endif
			.background(Color(.systemGroupedBackground))
			.navigationTitle(title)
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(action: onClose) {
						Image(systemName: "xmark")
					}
					.accessibilityLabel(String(localized: "Close", comment: "VoiceOver: dismiss this sheet"))
				}
			}
		}
		.interactiveDismissDisabled(!allowsSwipeToClose)
		// Only as tall as the content. A sheet taller than the screen stops at full height
		// and the content scrolls.
		.presentationDetents(contentHeight > 0 ? [.height(contentHeight + Self.navigationBarHeight)] : [.large])
		// Keep the screen on while this is open, the way the map does: a phone that sleeps
		// mid-transfer can drop the link and stall the update.
		.onAppear { UIApplication.shared.isIdleTimerDisabled = true }
		.onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
	}
}

/// The card at the top of a firmware screen: the radio's picture and name, the version
/// going on when there is one, and the screen's current title and message.
struct FirmwareUpdateCard<Accessory: View>: View {
	@Environment(\.firmwareUpdateRadio) private var radio

	let title: String
	let message: String
	@ViewBuilder var accessory: Accessory

	var body: some View {
		VStack(spacing: 16) {
			if let radio {
				FirmwareHeroImage(hardware: radio.hardware, pioEnv: radio.pioEnv)
					.frame(maxHeight: 140)
					.accessibilityHidden(true)
				VStack(spacing: 4) {
					Text(radio.name)
						.font(.headline)
						.multilineTextAlignment(.center)
					if let version = radio.firmwareVersion {
						Text("Firmware \(version)", comment: "The firmware version being installed, under the radio's name on the update screen")
							.font(.subheadline)
							.foregroundStyle(.secondary)
					}
				}
			}

			VStack(spacing: 6) {
				Text(title)
					.font(.title3.bold())
					.multilineTextAlignment(.center)
				Text(message)
					.font(.callout)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.center)
					.fixedSize(horizontal: false, vertical: true)
			}

			accessory
		}
		.padding(20)
		.frame(maxWidth: .infinity)
		.background(Color(.secondarySystemGroupedBackground))
		.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
}

extension FirmwareUpdateCard where Accessory == EmptyView {
	init(title: String, message: String) {
		self.init(title: title, message: message) { EmptyView() }
	}
}

/// One numbered step of a firmware screen that needs the user to do something, such as
/// saving a file onto the radio's USB drive.
struct FirmwareUpdateStep<Content: View>: View {
	let number: Int
	let title: String
	@ViewBuilder let content: Content

	var body: some View {
		HStack(alignment: .top, spacing: 12) {
			Text(number, format: .number)
				.font(.subheadline.bold())
				.foregroundStyle(.white)
				.frame(width: 28, height: 28)
				.background(Circle().fill(Color.accentFill))
				.accessibilityHidden(true)
			VStack(alignment: .leading, spacing: 10) {
				Text(title)
					.font(.headline)
					.accessibilityLabel(Text("Step \(number): \(title)", comment: "VoiceOver label for a numbered firmware screen step: the step number, then its title"))
				content
					.font(.callout)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.padding(16)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color(.secondarySystemGroupedBackground))
		.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
}

/// Small print under the steps.
struct FirmwareUpdateNotes: View {
	let notes: [String]

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			ForEach(notes, id: \.self) { note in
				Text(note)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		.font(.footnote)
		.foregroundStyle(.secondary)
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.horizontal, 4)
	}
}

/// The USB screens' first step: get the radio into update mode, where it shows up as a drive.
struct FirmwareUSBUpdateModeStep: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Environment(\.modelContext) private var context
	/// The restart request in flight. One at a time, and cancelled when the screen closes.
	@State private var restartTask: Task<Void, Never>?

	var body: some View {
		FirmwareUpdateStep(
			number: 1,
			title: String(localized: "Put the radio in update mode", comment: "Firmware USB screen step title")
		) {
			Text("Connect the radio with a USB cable. If it's connected to the app, tap the button. Otherwise press its reset button twice quickly. It shows up as a USB drive.",
				 comment: "Firmware USB screen step: how to put the radio in update mode")
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
			Button {
				restartIntoUpdateMode()
			} label: {
				Text("Restart Into Update Mode", comment: "Button that restarts the connected radio into its USB update mode")
					.frame(maxWidth: .infinity)
			}
			.buttonStyle(.bordered)
			.controlSize(.large)
			.disabled(accessoryManager.activeDeviceNum == nil || restartTask != nil)
		}
		.onDisappear {
			restartTask?.cancel()
			restartTask = nil
		}
	}

	private func restartIntoUpdateMode() {
		guard let node = getNodeInfo(id: accessoryManager.activeDeviceNum ?? 0, context: context),
			  let user = node.user, restartTask == nil else { return }
		restartTask = Task {
			defer { restartTask = nil }
			do {
				try await accessoryManager.sendEnterDfuMode(fromUser: user, toUser: user)
			} catch is CancellationError {
			} catch {
				Logger.mesh.error("Restart into update mode failed: \(error.localizedDescription, privacy: .public)")
			}
		}
	}
}
