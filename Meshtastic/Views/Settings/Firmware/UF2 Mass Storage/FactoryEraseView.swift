//
//  FactoryEraseView.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/27/26.
//
//  Guides an nRF52 user through a flash-level factory erase from the radio's
//  bootloader drive — the recovery path when firmware cannot boot, and the right
//  way to wipe a radio before handing it off. The erase image runs once on the
//  radio and removes the owner, channels, identity keys, settings, and node
//  database; only the SoftDevice and bootloader remain, and firmware must be
//  installed afterward through the normal firmware flow.
//
//  Safety model (mirrors Meshtastic-Android): the image is selected only by the
//  SoftDevice line the drive reports in INFO_UF2.TXT — the two erase images are
//  linked for different flash addresses, and the wrong one erases part of the
//  SoftDevice — and the downloaded bytes are digest-verified and cross-checked
//  against the expected start address before writing.
//

import CryptoKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

struct FactoryEraseView: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) var dismiss
	@Environment(\.modelContext) var context

	enum Phase: Equatable {
		case idle
		case resolved(variant: NRF52FactoryErase.SoftDeviceVariant, image: MaintenanceUF2)
		case installing
		case done
		case failed(String)
	}

	@State private var phase: Phase = .idle
	@State private var isPickingDrive = false
	@State private var showConfirmation = false
	/// The in-flight download/verify/write. Cancelled before drive access is released so
	/// the write can never run against a revoked security scope.
	@State private var installTask: Task<Void, Never>?
	@State private var driveURL: URL?

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(spacing: 20) {

					HStack(alignment: .top, spacing: 12) {
						Image(systemName: "exclamationmark.triangle.fill")
							.font(.title2)
							.foregroundStyle(.orange)

						Text("Factory erase permanently removes the radio's owner, channels, identity keys, settings, and node database. Nothing is restored automatically. Firmware must be installed afterward.")
							.font(.callout)
					}
					.padding()
					.background(Color.secondary.opacity(0.1))
					.clipShape(RoundedRectangle(cornerRadius: 12))

					Divider()

					VStack(alignment: .leading, spacing: 12) {
						Label("Step 1: Connect Device", systemImage: "1.circle.fill")
							.font(.headline)

						Text("Place your device in DFU mode and connect it via USB. It appears as a USB drive. A radio that cannot boot can still enter DFU with a double press of its reset button.")
							.fixedSize(horizontal: false, vertical: true)

						rebootIntoDFUButton()
					}

					Divider()

					VStack(alignment: .leading, spacing: 12) {
						Label("Step 2: Choose the Bootloader Drive", systemImage: "2.circle.fill")
							.font(.headline)

						Text("Select the device's drive in the file picker. The erase image is chosen from the SoftDevice version the drive reports, so the wrong image can never be written.")
							.font(.callout)
							.fixedSize(horizontal: false, vertical: true)

						chooseDriveButton()
					}

					Divider()

					VStack(alignment: .leading, spacing: 12) {
						Label("Step 3: Erase", systemImage: "3.circle.fill")
							.font(.headline)

						statusView()
					}

					Divider()

					VStack(alignment: .leading, spacing: 10) {
						Label("Important Notes", systemImage: "info.circle")
							.font(.caption.bold())
							.foregroundStyle(.secondary)

						Text("• The download is verified against a pinned checksum, and its flash address is cross-checked against the reported SoftDevice, before anything is written.")
						Text("• After the file is written the radio erases itself and reboots back into the bootloader; the drive disappears and comes back.")
						Text("• Install firmware next from the Firmware Updates screen. The radio starts as a brand-new device.")
					}
					.font(.caption)
					.foregroundStyle(.secondary)
				}
				.padding()
			}
			#if targetEnvironment(macCatalyst)
			.scrollIndicators(.visible)
			#endif
			.navigationTitle("Factory Erase")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button {
						dismiss()
					} label: {
						Image(systemName: "xmark")
					}
					.accessibilityLabel(String(localized: "Done", comment: "VoiceOver: dismiss the factory erase sheet"))
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
		.alert("Erase this radio?", isPresented: $showConfirmation) {
			Button("Erase Everything", role: .destructive) { install() }
			Button("Cancel", role: .cancel) {}
		} message: {
			Text("The owner, channels, identity keys, settings, and node database are permanently removed.")
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
						Logger.mesh.error("Reboot into DFU for factory erase failed")
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
			Text("Choose the drive above to identify the SoftDevice.")
				.font(.callout)
				.foregroundStyle(.secondary)

		case .resolved(let variant, let image):
			VStack(alignment: .leading, spacing: 8) {
				Label {
					Text("SoftDevice **S140 \(variant.rawValue)**")
				} icon: {
					Image(systemName: "checkmark.seal.fill")
						.foregroundStyle(.green)
				}
				Text(image.fileName)
					.font(.caption.monospaced())
					.foregroundStyle(.secondary)
				Button(role: .destructive) {
					showConfirmation = true
				} label: {
					Label("Erase This Radio", systemImage: "externaldrive.badge.xmark")
				}
				.buttonStyle(.borderedProminent)
				.tint(.red)
				.controlSize(.large)
				.frame(maxWidth: .infinity)
			}

		case .installing:
			HStack(spacing: 10) {
				ProgressView()
				Text("Downloading, verifying and writing…")
					.font(.callout)
			}

		case .done:
			Label {
				Text("Erase image written. The radio is wiping its flash and will reboot into the bootloader — install firmware next from the Firmware Updates screen.")
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
			guard let variant = NRF52FactoryErase.parseSoftDevice(fromInfoText: infoText) else {
				phase = .failed(String(localized: "The drive does not report a SoftDevice this erase supports (S140 6.1.1 or 7.3.0), so the right image cannot be chosen safely. Nothing was written."))
				return
			}
			phase = .resolved(variant: variant, image: NRF52FactoryErase.image(for: variant))
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
		guard case .resolved(let variant, let image) = phase, let driveURL else { return }
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
				// pairing would still write an image linked for the wrong SoftDevice.
				guard NRF52FactoryErase.uf2FirstTargetAddress(data) == NRF52FactoryErase.expectedFirstTargetAddress(for: variant) else {
					Logger.services.error("Factory erase image start address does not match SoftDevice S140 \(variant.rawValue, privacy: .public)")
					phase = .failed(String(localized: "The erase image does not match the radio's SoftDevice. Nothing was written."))
					return
				}
				let destination = driveURL.appendingPathComponent(image.fileName)
				try data.write(to: destination)
				Logger.services.info("Wrote factory erase image \(image.fileName, privacy: .public) to the device drive")
				phase = .done
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
