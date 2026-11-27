//
//  FactoryEraseView.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/27/26.
//
//  Guides an nRF52 user through a factory erase from the radio's bootloader
//  drive — the recovery path when firmware cannot boot, and the right way to
//  wipe a radio before handing it off. The owner, channels, identity keys,
//  settings, Bluetooth bonds, and node database are removed.
//
//  Two paths, chosen by INFO_UF2.TXT (see NRF52FactoryErase). A bootloader that
//  reports `Factory-Erase:` wipes its settings region itself and keeps the
//  installed firmware; the file is verified by digest and UF2 family ID. Older
//  bootloaders run a SoftDevice-specific erase image that leaves only the
//  SoftDevice and bootloader; that file is verified by digest and flash start
//  address, because the wrong one erases part of the SoftDevice.
//

import CryptoKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

struct FactoryEraseView: View {
	@Environment(\.dismiss) var dismiss

	/// Which erase the drive supports, and so which header check gates the write.
	enum Method: Equatable {
		/// The bootloader erases its own settings region; firmware is kept.
		case bootloader
		/// A SoftDevice-specific image erases application flash and settings.
		case softDevice(NRF52FactoryErase.SoftDeviceVariant)
	}

	enum Phase: Equatable {
		case idle
		case resolved(method: Method, entry: EraseEntry)
		case installing
		case done(Method)
		case failed(String)
	}

	@State private var phase: Phase = .idle
	@State private var isPickingDrive = false
	@State private var showConfirmation = false
	/// The in-flight download/verify/write. Cancelled before drive access is released so
	/// the write can never run against a revoked security scope.
	@State private var installTask: Task<Void, Never>?
	@State private var driveURL: URL?
	@State private var lastFault: BootloaderFault?

	var body: some View {
		FirmwareUpdateScreen(
			title: Text("Factory Erase", comment: "Title of the factory erase screen"),
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
				Text("Pick the radio's drive in the file picker. The app reads its bootloader from the drive to choose the right erase file, and never writes the wrong one.",
					 comment: "Factory erase step: choosing the radio's USB drive")
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
				chooseDriveButton()
				if let lastFault {
					BootloaderFaultNotice(fault: lastFault)
				}
			}

			FirmwareUpdateStep(
				number: 3,
				title: String(localized: "Erase", comment: "Factory erase step title")
			) {
				if case .resolved(_, let entry) = phase {
					Text(entry.image.fileName)
						.font(.caption.monospaced())
						.foregroundStyle(.secondary)
				}
				Button(role: .destructive) {
					showConfirmation = true
				} label: {
					Text("Erase This Radio", comment: "Button that writes the factory erase file onto the radio's drive")
						.frame(maxWidth: .infinity)
				}
				// The destructive role colors it red; a tint would override that.
				.buttonStyle(.borderedProminent)
				.controlSize(.large)
				.disabled(!isResolved)
			}

			FirmwareUpdateNotes(notes: [
				String(localized: "The download is checked against a known checksum, and against what the drive reported, before anything is written.", comment: "Note on the factory erase screen"),
				String(localized: "After the file is written the radio erases itself. Its drive disappears and comes back a couple of seconds later.", comment: "Note on the factory erase screen")
			])
		}
		.fileImporter(
			isPresented: $isPickingDrive,
			allowedContentTypes: [.folder],
			allowsMultipleSelection: false
		) { result in
			handleDrivePick(result)
		}
		.hostedAlert("Erase this radio?", isPresented: $showConfirmation) {
			Button("Erase Everything", role: .destructive) { install() }
			Button("Cancel", role: .cancel) {}
		} message: {
			Text("The owner, channels, identity keys, settings, Bluetooth bonds, and node database are permanently removed.")
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
			return String(localized: "Erase This Radio", comment: "Factory erase screen title before a drive is chosen")
		case .resolved:
			return String(localized: "Ready to Erase", comment: "Factory erase screen title once the erase file is chosen")
		case .installing:
			return String(localized: "Erasing", comment: "Factory erase screen title while the erase file is downloaded and written")
		case .done:
			return String(localized: "Erase Started", comment: "Factory erase screen title after the erase file is written")
		case .failed:
			return String(localized: "The Radio Wasn't Erased", comment: "Factory erase screen title after a failure")
		}
	}

	private var cardMessage: String {
		switch phase {
		case .idle:
			return String(localized: "Factory erase permanently removes the radio's owner, channels, identity keys, settings, Bluetooth bonds, and node database. Nothing is restored automatically.")
		case .resolved(.bootloader, _):
			return String(localized: "The bootloader erases its own settings. The installed firmware stays and starts as a brand-new device.", comment: "Factory erase screen message when the bootloader can erase itself")
		case .resolved(.softDevice(let variant), _):
			return String(localized: "This radio takes the erase image for SoftDevice S140 \(variant.rawValue). The firmware is removed too, so install firmware afterwards.", comment: "Factory erase screen message for older bootloaders; the SoftDevice version")
		case .installing:
			return String(localized: "Downloading, checking and writing the file.", comment: "Bootloader update screen message while the file is downloaded and written")
		case .done(.bootloader):
			return String(localized: "Erase file written. The radio is wiping its settings and comes back as a bootloader drive in a few seconds. Unplug it to start the installed firmware as a brand-new device, or install firmware from the Firmware Updates screen.")
		case .done(.softDevice):
			return String(localized: "Erase image written. The radio is wiping its flash and will reboot into the bootloader — install firmware next from the Firmware Updates screen.")
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
			// A bootloader that erases itself takes one file for every board and needs
			// no SoftDevice match. Anything else — line absent, or a family we do not
			// ship — falls through to the SoftDevice-specific path unchanged.
			let volumeFamily = NRF52FactoryErase.parseFactoryEraseFamily(fromInfoText: infoText)
			if let entry = NRF52FactoryErase.bootloaderEraseEntry(forVolumeFamily: volumeFamily) {
				phase = .resolved(method: .bootloader, entry: entry)
				return
			}
			guard let variant = NRF52FactoryErase.parseSoftDevice(fromInfoText: infoText) else {
				phase = .failed(String(localized: "The drive does not report a SoftDevice this erase supports (S140 6.1.1 or 7.3.0), so the right image cannot be chosen safely. Nothing was written."))
				return
			}
			guard let entry = NRF52FactoryErase.eraseEntry(for: variant) else {
				phase = .failed(String(localized: "No erase image is available for SoftDevice S140 \(variant.rawValue) right now. Nothing was written — try again later."))
				return
			}
			phase = .resolved(method: .softDevice(variant), entry: entry)
		} catch {
			phase = .failed(error.localizedDescription)
		}
	}

	/// INFO_UF2.TXT read, tolerant of FAT case differences and size-capped — the
	/// bootloader emits a few hundred bytes.
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
		guard case .resolved(let method, let entry) = phase, let driveURL else { return }
		let image = entry.image
		phase = .installing
		installTask = Task {
			do {
				let (data, response) = try await URLSession.shared.data(from: image.url)
				if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
					throw URLError(.badServerResponse)
				}
				try Task.checkCancellation()
				guard image.matches(data) else {
					Logger.services.error("Factory erase image failed checksum verification: \(image.fileName, privacy: .public)")
					phase = .failed(String(localized: "The downloaded image did not match its pinned checksum. Nothing was written — try again later."))
					return
				}
				// The digest proves the bytes; this proves the row: a swapped URL/digest
				// pairing would still write a file the drive cannot safely take.
				switch method {
				case .bootloader:
					guard let expected = entry.expectedFamilyID, NRF52FactoryErase.uf2FamilyID(data) == expected else {
						Logger.services.error("Factory erase file does not carry the bootloader erase family ID")
						phase = .failed(String(localized: "The erase file is not the one the bootloader expects. Nothing was written."))
						return
					}
				case .softDevice(let variant):
					guard NRF52FactoryErase.uf2FirstTargetAddress(data) == variant.applicationStartAddress else {
						Logger.services.error("Factory erase image start address does not match SoftDevice S140 \(variant.rawValue, privacy: .public)")
						phase = .failed(String(localized: "The erase image does not match the radio's SoftDevice. Nothing was written."))
						return
					}
				}
				let destination = driveURL.appendingPathComponent(image.fileName)
				try data.write(to: destination)
				Logger.services.info("Wrote factory erase image \(image.fileName, privacy: .public) to the device drive")
				phase = .done(method)
			} catch is CancellationError {
				// Dismissed mid-install; nothing was written.
			} catch {
				// The error can carry the drive path — keep it out of public logs.
				Logger.services.error("Factory erase failed: \(error.localizedDescription, privacy: .private)")
				phase = .failed(String(localized: "Could not write the erase image: \(error.localizedDescription)"))
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
	FactoryEraseView()
		.environmentObject(AccessoryManager.shared)
}
