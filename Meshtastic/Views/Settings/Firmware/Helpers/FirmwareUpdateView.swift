//
//  FirmwareUpdateView.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/27/26.
//
//  The one firmware update screen, whatever the radio and however the firmware gets there
//  (Nordic DFU, ESP32 over Bluetooth or Wi-Fi). A card with the radio's picture, a plain
//  status for each stage and a progress bar; the update library's own wording goes in Details.
//

import SwiftUI

/// What the update screen shows. Each updater maps its own states onto these.
enum FirmwareUpdateStage: Equatable {
	/// Not started: the confirmation, with the Update button.
	case ready
	/// The radio is restarting into update mode and the app is reaching it.
	case preparing
	/// Firmware is going across; progress is meaningful.
	case sending
	/// The transfer finished and the radio is restarting into the new firmware.
	case restarting
	case done
	case failed
	/// The phone can't update this radio; `reason` says why and what to do instead.
	case unavailable(reason: String)

	var isUnderWay: Bool {
		switch self {
		case .preparing, .sending, .restarting: return true
		default: return false
		}
	}

	init(_ status: LocalOTAStatusCode) {
		switch status {
		case .idle: self = .ready
		case .waitingForConnection, .connected, .preparing: self = .preparing
		case .transferring: self = .sending
		case .completed: self = .done
		case .error: self = .failed
		}
	}
}

/// The radio being updated, for the card's picture and name. Set by the firmware screen on
/// the sheet it presents.
struct FirmwareUpdateRadio {
	let hardware: DeviceHardwareEntity
	let pioEnv: String?
	/// The radio's own name, falling back to the hardware's.
	let name: String
	/// The firmware version going on, when known, without the commit hash.
	let firmwareVersion: String?
}

extension EnvironmentValues {
	@Entry var firmwareUpdateRadio: FirmwareUpdateRadio?
}

/// Reads the firmware version out of a firmware file name, as people know it: `2.8.3` from
/// `firmware-…-2.8.3.eb99f95.zip`, without the build's commit hash.
enum FirmwareFileVersion {
	static func version(in fileName: String) -> String? {
		guard let match = fileName.firstMatch(of: /(\d+\.\d+\.\d+)/) else { return nil }
		return String(match.1)
	}
}

struct FirmwareUpdateView: View {
	@Environment(\.firmwareUpdateRadio) private var radio

	let stage: FirmwareUpdateStage
	let progress: Double
	/// The update library's own status or error text, shown under Details.
	var detail: String = ""
	var isStartDisabled = false
	let onStart: () -> Void
	let onRetry: () -> Void
	let onDismiss: () -> Void

	@State private var showChirpyGame = false
	@State private var showStopConfirmation = false
	/// Height of everything under the navigation bar, so the sheet can be just that tall.
	@State private var contentHeight: CGFloat = 0
	/// The inline navigation bar above the content.
	private static let navigationBarHeight: CGFloat = 64

	var body: some View {
		SheetNavigationStack {
			ScrollView {
				VStack(spacing: 20) {
					card
					actions
						// Rounded rectangles, not the default capsule, to match the rest of the app.
						.buttonBorderShape(.roundedRectangle(radius: 12))
					if !detail.isEmpty, stage != .ready, !isUnavailable {
						DisclosureGroup {
							Text(detail)
								.font(.footnote.monospaced())
								.foregroundStyle(.secondary)
								.textSelection(.enabled)
								.frame(maxWidth: .infinity, alignment: .leading)
								.padding(.top, 4)
						} label: {
							Text("Details", comment: "Disclosure on the firmware update screen that shows the update library's own status text")
								.font(.subheadline)
						}
						.padding(.horizontal, 4)
					}
				}
				.padding(20)
				.frame(maxWidth: 560)
				.frame(maxWidth: .infinity)
				.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
			}
			.background(Color(.systemGroupedBackground))
			.navigationTitle(Text("Firmware Update", comment: "Title of the firmware update screen"))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button {
						// Always a way out. An update can stall somewhere the app can't recover
						// from, and a disabled close button leaves force-quitting as the only exit.
						if stage.isUnderWay {
							showStopConfirmation = true
						} else {
							onDismiss()
						}
					} label: {
						Image(systemName: "xmark")
					}
					.accessibilityLabel(String(localized: "Close", comment: "VoiceOver: dismiss this sheet"))
				}
			}
		}
		.interactiveDismissDisabled(true)
		// Only as tall as the content, growing when Details opens. A sheet taller than the
		// screen stops at full height and the content scrolls.
		.presentationDetents(contentHeight > 0 ? [.height(contentHeight + Self.navigationBarHeight)] : [.large])
		.hostedConfirmation(
			Text("Stop the update?", comment: "Title of the confirmation shown when closing an update in progress"),
			isPresented: $showStopConfirmation,
			titleVisibility: .visible
		) {
			Button(role: .destructive) {
				onDismiss()
			} label: {
				Text("Stop Update", comment: "Button that abandons an update in progress")
			}
			Button(role: .cancel) { } label: {
				Text("Keep Waiting", comment: "Button that returns to an update in progress")
			}
		} message: {
			Text("The device stays in update mode until the update finishes or you power it off and on again.",
				 comment: "Explains what happens to the device when an update is abandoned")
		}
		.firmwareUpdateGame(isPresented: $showChirpyGame, status: gameStatus)
		// Keep the screen on while this is open, the way the map does: a phone that sleeps
		// mid-transfer can drop the Bluetooth link and stall the update.
		.onAppear { UIApplication.shared.isIdleTimerDisabled = true }
		.onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
	}

	// MARK: - Card

	private var card: some View {
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

			if stage == .ready {
				readyChecklist
			} else if stage != .failed, !isUnavailable {
				FirmwareUpdateProgressBar(
					progress: stage == .done ? 1 : progress,
					isIndeterminate: stage == .preparing || stage == .restarting
				)
				.accessibilityLabel(title)
				.accessibilityValue(stage == .sending ? Text(progress, format: .percent.precision(.fractionLength(0))) : Text(""))
			}
		}
		.padding(20)
		.frame(maxWidth: .infinity)
		.background(Color(.secondarySystemGroupedBackground))
		.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
	}

	private var readyChecklist: some View {
		VStack(alignment: .leading, spacing: 10) {
			Label {
				Text("The radio is charged or plugged in", comment: "Firmware update checklist item")
			} icon: {
				Image(systemName: "battery.75percent")
					.frame(width: 28)
			}
			Label {
				Text("Your phone stays close to the radio", comment: "Firmware update checklist item")
			} icon: {
				Image(systemName: "dot.radiowaves.left.and.right")
					.frame(width: 28)
			}
			Label {
				Text("The app stays open until it finishes", comment: "Firmware update checklist item")
			} icon: {
				Image(systemName: "iphone")
					.frame(width: 28)
			}
		}
		.font(.subheadline)
		.foregroundStyle(.secondary)
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	// MARK: - Actions

	@ViewBuilder
	private var actions: some View {
		switch stage {
		case .ready:
			Button(action: onStart) {
				Text("Update", comment: "Button that starts a firmware update")
					.frame(maxWidth: .infinity)
			}
			.buttonStyle(.borderedProminent)
			.tint(.accentFill)
			.controlSize(.large)
			.disabled(isStartDisabled)
		case .failed:
			Button(action: onRetry) {
				Label {
					Text("Try Again", comment: "Button that restarts a firmware update that failed")
				} icon: {
					Image(systemName: "arrow.clockwise")
				}
				.frame(maxWidth: .infinity)
			}
			.buttonStyle(.borderedProminent)
			.tint(.accentFill)
			.controlSize(.large)
		case .done:
			Button(action: onDismiss) {
				Text("Done", comment: "Button that closes the firmware update screen after a successful update")
					.frame(maxWidth: .infinity)
			}
			.buttonStyle(.borderedProminent)
			.tint(.accentFill)
			.controlSize(.large)
		case .unavailable:
			Link(destination: URL(string: "https://flash.meshtastic.org")!) {
				Label {
					Text("Open the Web Flasher", comment: "Button that opens flash.meshtastic.org when the phone can't update a radio")
				} icon: {
					Image(systemName: "arrow.up.right")
				}
				.frame(maxWidth: .infinity)
			}
			.buttonStyle(.bordered)
			.controlSize(.large)
		case .preparing, .sending, .restarting:
			if gameStatus.phase.isActive {
				FirmwareUpdateGameButton(isPresented: $showChirpyGame, status: gameStatus)
			}
		}
	}

	// MARK: - Wording

	private var isUnavailable: Bool {
		if case .unavailable = stage { return true }
		return false
	}

	private var title: String {
		switch stage {
		case .ready:
			return String(localized: "Ready to Update", comment: "Firmware update screen title before the update starts")
		case .preparing:
			return String(localized: "Getting Your Radio Ready", comment: "Firmware update screen title while the radio restarts into update mode")
		case .sending:
			return String(localized: "Sending Firmware", comment: "Firmware update screen title while firmware is transferred")
		case .restarting:
			return String(localized: "Restarting Your Radio", comment: "Firmware update screen title after the transfer while the radio restarts")
		case .done:
			return String(localized: "Update Complete", comment: "Firmware update screen title after a successful update")
		case .failed:
			return String(localized: "The Update Didn't Finish", comment: "Firmware update screen title after an update fails")
		case .unavailable:
			return String(localized: "Update This Radio From a Computer", comment: "Firmware update screen title when the phone can't update the radio")
		}
	}

	private var message: String {
		switch stage {
		case .ready:
			return String(localized: "Your radio will restart a few times and reconnect when it's done.", comment: "Firmware update screen message before the update starts")
		case .preparing:
			return String(localized: "Your radio is restarting into update mode. Keep the app open and your phone near the radio.", comment: "Firmware update screen message while the radio restarts into update mode")
		case .sending:
			return String(localized: "Keep the app open and your phone near the radio.", comment: "Firmware update screen message while firmware is transferred")
		case .restarting:
			return String(localized: "Your radio is starting the new firmware. The app reconnects on its own.", comment: "Firmware update screen message after the transfer while the radio restarts")
		case .done:
			return String(localized: "Your radio is running the new firmware. The app reconnects on its own.", comment: "Firmware update screen message after a successful update")
		case .failed:
			return String(localized: "Something interrupted the update. Move your phone close to the radio and try again.", comment: "Firmware update screen message after an update fails")
		case .unavailable(let reason):
			return reason
		}
	}

	private var gameStatus: FirmwareUpdateGameStatus {
		let phase: FirmwareUpdateGamePhase
		switch stage {
		case .preparing: phase = .preparing
		case .sending: phase = .uploading
		case .restarting, .done: phase = .complete
		case .ready, .failed, .unavailable: phase = .failed
		}
		return FirmwareUpdateGameStatus(
			title: String(localized: "Firmware Update", comment: "Title of the firmware update screen"),
			message: title,
			progress: progress,
			phase: phase
		)
	}
}

/// A plain linear progress bar with rounded ends, sized for the update card.
struct FirmwareUpdateProgressBar: View {
	let progress: Double
	var isIndeterminate = false

	@State private var sweep = false

	var body: some View {
		GeometryReader { geometry in
			ZStack(alignment: .leading) {
				RoundedRectangle(cornerRadius: 4, style: .continuous)
					.fill(Color(.tertiarySystemFill))
				if isIndeterminate {
					RoundedRectangle(cornerRadius: 4, style: .continuous)
						.fill(Color.accentFill)
						.frame(width: geometry.size.width * 0.3)
						.offset(x: sweep ? geometry.size.width * 0.7 : 0)
						.animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: sweep)
						.onAppear { sweep = true }
						.onDisappear { sweep = false }
				} else {
					RoundedRectangle(cornerRadius: 4, style: .continuous)
						.fill(Color.accentFill)
						.frame(width: geometry.size.width * min(max(progress, 0), 1))
						.animation(.easeOut(duration: 0.25), value: progress)
				}
			}
		}
		.frame(height: 8)
	}
}
