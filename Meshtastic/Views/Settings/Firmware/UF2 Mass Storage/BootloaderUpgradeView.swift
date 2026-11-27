//
//  BootloaderUpgradeView.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/19/26.
//
//  Guides an nRF52 user through installing the OTAFIX bootloader (Meshtastic's
//  fork of the Adafruit nRF52 bootloader with faster, more reliable BLE OTA).
//
//  Safety model (mirrors Meshtastic-Android): the image to write is selected
//  ONLY by the Board-ID the device itself reports in INFO_UF2.TXT on its
//  mounted drive — never by correlating product names. The user grants the app
//  access to the drive with the folder picker; the app reads the Board-ID,
//  downloads the matching release image, verifies its pinned SHA-256, and
//  writes it onto the drive. An unrecognized Board-ID refuses the upgrade.
//

import CryptoKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

struct BootloaderUpgradeView: View {
	@Environment(\.dismiss) var dismiss

	/// The connected node's build target, for boards whose stock bootloader shares another board's Board-ID.
	var platformioTarget: String?

	enum Phase: Equatable {
		case idle
		case resolved(boardID: String, image: MaintenanceUF2)
		case installing
		case done(fileName: String)
		case failed(String)
	}

	@State private var phase: Phase = .idle
	@State private var isPickingDrive = false
	/// The in-flight download/verify/write. Cancelled before drive access is released so
	/// the write can never run against a revoked security scope.
	@State private var installTask: Task<Void, Never>?
	/// The security-scoped drive URL from the folder picker. Access is started
	/// when granted and stopped when this view goes away or a new pick begins.
	@State private var driveURL: URL?
	@State private var lastFault: BootloaderFault?

	var body: some View {
		FirmwareUpdateScreen(
			title: Text("Bootloader Update", comment: "Title of the bootloader update screen"),
			onClose: { dismiss() },
			allowsSwipeToClose: phase != .installing
		) {
			FirmwareUpdateCard(title: cardTitle, message: cardMessage) {
				if phase == .installing {
					FirmwareUpdateProgressBar(progress: 0, isIndeterminate: true)
						.accessibilityLabel(cardTitle)
				}
			}

			FirmwareUSBUpdateModeStep()

			FirmwareUpdateStep(
				number: 2,
				title: String(localized: "Choose the radio's drive", comment: "Bootloader and factory erase step title")
			) {
				Text("Pick the radio's drive in the file picker, for example FTHR840BOOT or RAK4631. The app reads which board it is from the drive.",
					 comment: "Bootloader update step: choosing the radio's USB drive")
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
				chooseDriveButton()
				if let lastFault {
					BootloaderFaultNotice(fault: lastFault)
				}
			}

			FirmwareUpdateStep(
				number: 3,
				title: String(localized: "Install", comment: "Bootloader update step title")
			) {
				if case .resolved(_, let image) = phase {
					Text(image.fileName)
						.font(.caption.monospaced())
						.foregroundStyle(.secondary)
				}
				Button {
					install()
				} label: {
					Text("Install Bootloader", comment: "Button that writes the bootloader file onto the radio's drive")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.borderedProminent)
				.tint(.accentFill)
				.controlSize(.large)
				.disabled(!isResolved)
			}

			FirmwareUpdateNotes(notes: [
				String(localized: "The download is checked against a known checksum before anything is written.", comment: "Note on the bootloader update screen"),
				String(localized: "After the file is written the radio installs the bootloader and restarts. Its drive disappears and comes back.", comment: "Note on the bootloader update screen"),
				String(localized: "If the board isn't recognized, nothing is written. A bootloader for the wrong board can't be fixed over USB.", comment: "Note on the bootloader update screen")
			])
		}
		.fileImporter(
			isPresented: $isPickingDrive,
			allowedContentTypes: [.folder],
			allowsMultipleSelection: false
		) { result in
			handleDrivePick(result)
		}
		.onDisappear {
			releaseDriveAccess()
		}
	}

	// MARK: - Wording

	private var isResolved: Bool {
		if case .resolved = phase { return true }
		return false
	}

	private var cardTitle: String {
		switch phase {
		case .idle:
			return String(localized: "Update the Bootloader", comment: "Bootloader update screen title before a drive is chosen")
		case .resolved:
			return String(localized: "Ready to Install", comment: "Bootloader update screen title once the board is recognized")
		case .installing:
			return String(localized: "Installing the Bootloader", comment: "Bootloader update screen title while the file is downloaded and written")
		case .done:
			return String(localized: "Bootloader Installed", comment: "Bootloader update screen title after the file is written")
		case .failed:
			return String(localized: "The Bootloader Wasn't Installed", comment: "Bootloader update screen title after a failure")
		}
	}

	private var cardMessage: String {
		switch phase {
		case .idle:
			return String(localized: "The Meshtastic nRF52 Bootloader makes Bluetooth firmware updates faster and more reliable. It's installed from the radio's USB drive.", comment: "Bootloader update screen message before a drive is chosen")
		case .resolved(let boardID, _):
			return String(localized: "Recognized board \(boardID).", comment: "Bootloader update screen message once the board is recognized; the board ID")
		case .installing:
			return String(localized: "Downloading, checking and writing the file.", comment: "Bootloader update screen message while the file is downloaded and written")
		case .done(let fileName):
			return String(localized: "Wrote \(fileName). The radio is installing the bootloader and restarts on its own.", comment: "Bootloader update screen message after the file is written; the file name")
		case .failed(let message):
			return message
		}
	}

	// MARK: - Steps

	@ViewBuilder
	func chooseDriveButton() -> some View {
		Button {
			isPickingDrive = true
		} label: {
			Text("Choose Drive", comment: "Button that opens the file picker to choose the radio's USB drive")
				.frame(maxWidth: .infinity)
		}
		.hostedWindowOnly()
		.buttonStyle(.bordered)
		.controlSize(.large)
		.disabled(phase == .installing)
	}

	// MARK: - Drive handling

	private func handleDrivePick(_ result: Result<[URL], Error>) {
		releaseDriveAccess()
		lastFault = nil
		do {
			guard let url = try result.get().first else { return }
			guard url.startAccessingSecurityScopedResource() else {
				phase = .failed(String(localized: "Could not open the selected drive."))
				return
			}
			driveURL = url

			guard let infoText = readInfoFile(in: url) else {
				phase = .failed(String(localized: "That folder is not a UF2 bootloader drive — no INFO_UF2.TXT found. Select the drive the device mounts in DFU mode."))
				return
			}
			lastFault = BootloaderFaultNotice.record(fromInfoText: infoText)
			guard let boardID = OTAFIXBootloader.parseBoardID(fromInfoText: infoText) else {
				phase = .failed(String(localized: "INFO_UF2.TXT has no Board-ID line, so the board cannot be identified safely."))
				return
			}
			guard let image = OTAFIXBootloader.image(forBoardID: boardID, platformioTarget: platformioTarget) else {
				phase = .failed(String(localized: "No Meshtastic nRF52 Bootloader is available for board \"\(boardID)\". Nothing was written."))
				return
			}
			phase = .resolved(boardID: boardID, image: image)
		} catch {
			phase = .failed(error.localizedDescription)
		}
	}

	/// INFO_UF2.TXT read, tolerant of FAT case differences. The bootloader emits a few
	/// hundred bytes; anything large is not the file we expect, so refuse before reading
	/// it into memory.
	private static let maxInfoFileBytes = 16 * 1024

	private func readInfoFile(in drive: URL) -> String? {
		let fm = FileManager.default
		let direct = drive.appendingPathComponent(OTAFIXBootloader.infoFileName)
		if let text = boundedInfoText(at: direct) { return text }
		guard let names = try? fm.contentsOfDirectory(atPath: drive.path) else { return nil }
		guard let match = names.first(where: { $0.caseInsensitiveCompare(OTAFIXBootloader.infoFileName) == .orderedSame }) else {
			return nil
		}
		return boundedInfoText(at: drive.appendingPathComponent(match))
	}

	private func boundedInfoText(at url: URL) -> String? {
		guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
			  size <= Self.maxInfoFileBytes else { return nil }
		return try? String(contentsOf: url, encoding: .utf8)
	}

	private func install() {
		guard case .resolved(_, let image) = phase, let driveURL else { return }
		phase = .installing
		installTask = Task {
			do {
				let (data, response) = try await URLSession.shared.data(from: image.url)
				if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
					throw URLError(.badServerResponse)
				}
				// The sheet may have been dismissed (and drive access released) during
				// the download — never write against a revoked scope.
				try Task.checkCancellation()
				guard image.matches(data) else {
					Logger.services.error("OTAFIX image failed checksum verification: \(image.fileName, privacy: .public)")
					phase = .failed(String(localized: "The downloaded image did not match its pinned checksum. Nothing was written — try again later."))
					return
				}
				let destination = driveURL.appendingPathComponent(image.fileName)
				try data.write(to: destination)
				Logger.services.info("Wrote OTAFIX bootloader \(image.fileName, privacy: .public) to the device drive")
				phase = .done(fileName: image.fileName)
			} catch is CancellationError {
				// Dismissed mid-install; nothing was written.
			} catch {
				// The error can carry the drive path — keep it out of public logs.
				Logger.services.error("OTAFIX bootloader install failed: \(error.localizedDescription, privacy: .private)")
				phase = .failed(String(localized: "Could not install the update: \(error.localizedDescription)"))
			}
		}
	}

	private func releaseDriveAccess() {
		installTask?.cancel()
		installTask = nil
		driveURL?.stopAccessingSecurityScopedResource()
		driveURL = nil
	}
}

#Preview {
	BootloaderUpgradeView()
		.environmentObject(AccessoryManager.shared)
}
