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
	/// The exact build going on, with its commit hash, for the Details log.
	var firmwareBuild: String?

	/// The same radio with no firmware going on, for the bootloader and erase screens.
	var withoutFirmware: FirmwareUpdateRadio {
		FirmwareUpdateRadio(hardware: hardware, pioEnv: pioEnv, name: name, firmwareVersion: nil)
	}
}

extension EnvironmentValues {
	@Entry var firmwareUpdateRadio: FirmwareUpdateRadio?
}

/// A title and message that replace the stage's own, for a situation the stage alone doesn't
/// cover, such as a radio whose bootloader wouldn't take the update.
struct FirmwareUpdateCallout: Equatable {
	let title: String
	let message: String

	/// After an nRF52 update failed before any firmware went across.
	static let didNotEnterUpdateMode = FirmwareUpdateCallout(
		title: String(localized: "Your Radio Didn't Go Into Update Mode", comment: "Firmware update screen title when the radio restarted but never entered update mode"),
		message: String(localized: "It restarted but didn't wait for the update. This usually means its bootloader needs updating. Update the bootloader over USB, then try again.", comment: "Firmware update screen message when the radio restarted but never entered update mode")
	)
}

/// Reads the firmware version out of a firmware file name, as people know it: `2.8.3` from
/// `firmware-…-2.8.3.eb99f95.zip`, without the build's commit hash. Takes the last
/// version-shaped run whose major number is plausible, so a date earlier in the name, as in
/// `backup-2026.11.27-heltec-v3-2.7.18.fb3bf78.bin`, isn't mistaken for it.
enum FirmwareFileVersion {
	static func version(in fileName: String) -> String? {
		fileName.matches(of: /(\d+)\.(\d+)\.(\d+)/)
			.last { (Int($0.1) ?? .max) < 100 }
			.map { "\($0.1).\($0.2).\($0.3)" }
	}

	/// The exact build, with the commit hash when the name has one: `2.8.3.eb99f95`.
	static func build(in fileName: String) -> String? {
		fileName.matches(of: /(\d+)\.(\d+)\.(\d+)(\.[0-9a-f]{6,})?/)
			.last { (Int($0.1) ?? .max) < 100 }
			.map { "\($0.1).\($0.2).\($0.3)\($0.4 ?? "")" }
	}
}

struct FirmwareUpdateView: View {
	@Environment(\.firmwareUpdateRadio) private var radio

	let stage: FirmwareUpdateStage
	let progress: Double
	/// The update library's current status or error text. Each change is kept, with its
	/// time, in the Details log.
	var detail: String = ""
	var isStartDisabled = false
	let onStart: () -> Void
	let onRetry: () -> Void
	let onDismiss: () -> Void
	/// Shown instead of the failed wording.
	var failureNotice: FirmwareUpdateCallout?
	/// Opens the bootloader upgrade. When set, the failure callout offers it as the main action.
	var onUpgradeBootloader: (() -> Void)?

	@State private var showChirpyGame = false
	@State private var showStopConfirmation = false
	/// Every status the update library reported since Update was tapped, oldest first.
	@State private var detailLog: [DetailLine] = []

	var body: some View {
		FirmwareUpdateScreen(
			title: Text("Firmware Update", comment: "Title of the firmware update screen"),
			onClose: {
				// Always a way out. An update can stall somewhere the app can't recover
				// from, and a disabled close button leaves force-quitting as the only exit.
				if stage.isUnderWay {
					showStopConfirmation = true
				} else {
					onDismiss()
				}
			},
			allowsSwipeToClose: false
		) {
			card
			actions
			if !detailLog.isEmpty, stage != .ready, !isUnavailable {
				DisclosureGroup {
					VStack(alignment: .leading, spacing: 4) {
						ForEach(detailLog) { line in
							HStack(alignment: .firstTextBaseline, spacing: 8) {
								Text(line.time, format: .dateTime.hour().minute().second())
									.foregroundStyle(.tertiary)
								Text(line.text)
									.foregroundStyle(.secondary)
							}
						}
					}
					.font(.footnote.monospaced())
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
		.onChange(of: detail, initial: true) { _, text in record(text) }
	}

	// MARK: - Details log

	private struct DetailLine: Identifiable {
		let id = UUID()
		let time: Date
		let text: String
	}

	/// Adds a status to the log once the update has started, skipping repeats in a row. The
	/// first entry names the exact build going on.
	private func record(_ text: String) {
		let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !text.isEmpty, stage != .ready, !isUnavailable, detailLog.last?.text != text else { return }
		if detailLog.isEmpty, let build = radio?.firmwareBuild ?? radio?.firmwareVersion {
			detailLog.append(DetailLine(
				time: Date(),
				text: String(localized: "Installing firmware \(build)", comment: "First line of the firmware update Details log; the version with its commit hash")
			))
		}
		detailLog.append(DetailLine(time: Date(), text: text))
	}

	// MARK: - Card

	private var card: some View {
		FirmwareUpdateCard(title: title, message: message) {
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
		case .failed where failureNotice != nil && onUpgradeBootloader != nil:
			VStack(spacing: 10) {
				upgradeBootloaderButton
				Button(action: onRetry) {
					Label {
						Text("Try Again", comment: "Button that restarts a firmware update that failed")
					} icon: {
						Image(systemName: "arrow.clockwise")
					}
					.frame(maxWidth: .infinity)
				}
				.buttonStyle(.bordered)
				.controlSize(.large)
			}
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

	private var upgradeBootloaderButton: some View {
		Button {
			onUpgradeBootloader?()
		} label: {
			Label {
				Text("Update Bootloader", comment: "Button that opens the bootloader upgrade from the firmware update screen")
			} icon: {
				Image(systemName: "memorychip")
			}
			.frame(maxWidth: .infinity)
		}
		.buttonStyle(.borderedProminent)
		.tint(.accentFill)
		.controlSize(.large)
	}

	// MARK: - Wording

	private var isUnavailable: Bool {
		if case .unavailable = stage { return true }
		return false
	}

	private var title: String {
		if stage == .failed, let failureNotice { return failureNotice.title }
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
		if stage == .failed, let failureNotice { return failureNotice.message }
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
			return String(localized: "The firmware is on your radio. It's restarting now, and the app reconnects on its own.", comment: "Firmware update screen message after a successful update")
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
