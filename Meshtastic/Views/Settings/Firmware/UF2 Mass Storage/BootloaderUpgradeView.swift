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
import Foundation
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// Coordinates writes to a security-scoped URL returned by the Files picker.
/// External USB volumes are hosted by a file provider, so writing directly to
/// the URL can fail even after the app has successfully read INFO_UF2.TXT.
protocol OTAFIXDriveWriteCoordinating {
	func coordinateWritingItem(at destination: URL, accessor: (URL) -> Void) throws
}

struct OTAFIXDriveWriteCoordinator: OTAFIXDriveWriteCoordinating {
	func coordinateWritingItem(at destination: URL, accessor: (URL) -> Void) throws {
		let coordinator = NSFileCoordinator()
		var coordinationError: NSError?

		coordinator.coordinate(writingItemAt: destination, options: [], error: &coordinationError) { coordinatedDestination in
			accessor(coordinatedDestination)
		}

		if let coordinationError { throw coordinationError }
	}
}

enum OTAFIXDriveWriter {
	static func write(
		_ data: Data,
		to destination: URL,
		coordinator: any OTAFIXDriveWriteCoordinating = OTAFIXDriveWriteCoordinator()
	) throws {
		var writeError: Error?

		try coordinator.coordinateWritingItem(at: destination) { coordinatedDestination in
			do {
				try data.write(to: coordinatedDestination)
			} catch {
				writeError = error
			}
		}

		if let writeError { throw writeError }
	}
}

struct BootloaderUpgradeView: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) var dismiss
	@Environment(\.modelContext) var context

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

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(spacing: 20) {

					HStack(alignment: .top, spacing: 12) {
						Image(systemName: "memorychip")
							.font(.title2)
							.foregroundStyle(.blue)

						Text("OTAFIX is Meshtastic's improved nRF52 bootloader with faster, more reliable Bluetooth firmware updates. The upgrade is written from the device's own bootloader drive.")
							.font(.callout)
					}
					.padding()
					.background(Color.secondary.opacity(0.1))
					.clipShape(RoundedRectangle(cornerRadius: 12))

					Divider()

					VStack(alignment: .leading, spacing: 12) {
						Label("Step 1: Connect Device", systemImage: "1.circle.fill")
							.font(.headline)

						Text("Place your device in DFU mode and connect it via USB. It appears as a USB drive.")
							.fixedSize(horizontal: false, vertical: true)

						Text("If connected, use the button below to reboot into DFU. Otherwise, press your device's reset button twice rapidly.")
							.font(.caption)
							.foregroundStyle(.secondary)

						rebootIntoDFUButton()
					}

					Divider()

					VStack(alignment: .leading, spacing: 12) {
						Label("Step 2: Choose the Bootloader Drive", systemImage: "2.circle.fill")
							.font(.headline)

						Text("Select the device's drive in the file picker (for example FTHR840BOOT or RAK4631). The board is identified from the INFO_UF2.TXT file the bootloader publishes there.")
							.font(.callout)
							.fixedSize(horizontal: false, vertical: true)

						chooseDriveButton()
					}

					Divider()

					VStack(alignment: .leading, spacing: 12) {
						Label("Step 3: Install", systemImage: "3.circle.fill")
							.font(.headline)

						statusView()
					}

					Divider()

					VStack(alignment: .leading, spacing: 10) {
						Label("Important Notes", systemImage: "info.circle")
							.font(.caption.bold())
							.foregroundStyle(.secondary)

						Text("• The download is verified against a pinned checksum before anything is written.")
						Text("• After the file is written the device installs the bootloader and reboots itself; the drive disappears and comes back.")
						Text("• If the board is not recognized nothing is written — a bootloader for the wrong board cannot be recovered over USB.")
					}
					.font(.caption)
					.foregroundStyle(.secondary)
				}
				.padding()
			}
			// Catalyst sizes the sheet from the window and hides scroll bars at
			// rest — same treatment as UF2MassStorageView so the bottom section
			// never reads as cut off.
			#if targetEnvironment(macCatalyst)
			.scrollIndicators(.visible)
			#endif
			.navigationTitle("Bootloader Upgrade")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button {
						dismiss()
					} label: {
						Image(systemName: "xmark")
					}
					.accessibilityLabel(String(localized: "Done", comment: "VoiceOver: dismiss the bootloader upgrade sheet"))
				}
			}
		}
		#if targetEnvironment(macCatalyst)
		.frame(minHeight: 780)
		#endif
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

	// MARK: - Steps

	@ViewBuilder
	func rebootIntoDFUButton() -> some View {
		Button {
			let connectedNode = getNodeInfo(id: accessoryManager.activeDeviceNum ?? 0, context: context)
			if let connectedNode, let user = connectedNode.user {
				Task {
					do {
						try await accessoryManager.sendEnterDfuMode(fromUser: user, toUser: user)
					} catch {
						Logger.mesh.error("Reboot into DFU for bootloader upgrade failed")
					}
				}
			}
		} label: {
			Label("Send Reboot into DFU", systemImage: "square.and.arrow.down")
		}
		.buttonStyle(.borderedProminent)
		.controlSize(.large)
		.frame(maxWidth: .infinity)
		.disabled(accessoryManager.activeDeviceNum == nil)
	}

	@ViewBuilder
	func chooseDriveButton() -> some View {
		Button {
			isPickingDrive = true
		} label: {
			Label("Choose Bootloader Drive", systemImage: "externaldrive")
		}
		.buttonStyle(.borderedProminent)
		.controlSize(.large)
		.frame(maxWidth: .infinity)
		.disabled(phase == .installing)
	}

	@ViewBuilder
	func statusView() -> some View {
		switch phase {
		case .idle:
			Text("Choose the drive above to identify the board.")
				.font(.callout)
				.foregroundStyle(.secondary)

		case .resolved(let boardID, let image):
			VStack(alignment: .leading, spacing: 8) {
				Label {
					Text("Recognized **\(boardID)**")
				} icon: {
					Image(systemName: "checkmark.seal.fill")
						.foregroundStyle(.green)
				}
				Text(image.fileName)
					.font(.caption.monospaced())
					.foregroundStyle(.secondary)
				Button {
					install()
				} label: {
					Label("Install Bootloader Update", systemImage: "arrow.down.circle.fill")
				}
				.buttonStyle(.borderedProminent)
				.controlSize(.large)
				.frame(maxWidth: .infinity)
			}

		case .installing:
			HStack(spacing: 10) {
				ProgressView()
				Text("Downloading, verifying and writing…")
					.font(.callout)
			}

		case .done(let fileName):
			Label {
				Text("Wrote \(fileName). The device is installing the bootloader and will reboot on its own.")
					.font(.callout)
			} icon: {
				Image(systemName: "checkmark.circle.fill")
					.foregroundStyle(.green)
			}

		case .failed(let message):
			Label {
				Text(message)
					.font(.callout)
			} icon: {
				Image(systemName: "exclamationmark.triangle.fill")
					.foregroundStyle(.orange)
			}
		}
	}

	// MARK: - Drive handling

	private func handleDrivePick(_ result: Result<[URL], Error>) {
		releaseDriveAccess()
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
			guard let boardID = OTAFIXBootloader.parseBoardID(fromInfoText: infoText) else {
				phase = .failed(String(localized: "INFO_UF2.TXT has no Board-ID line, so the board cannot be identified safely."))
				return
			}
			guard let image = OTAFIXBootloader.image(forBoardID: boardID) else {
				phase = .failed(String(localized: "No OTAFIX bootloader is available for board \"\(boardID)\". Nothing was written."))
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
				try OTAFIXDriveWriter.write(data, to: destination)
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
