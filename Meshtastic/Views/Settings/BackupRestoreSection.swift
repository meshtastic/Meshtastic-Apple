//
//  BackupRestoreSection.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/26/26.
//
//  Backup and restore of the connected radio's full configuration, on the Settings
//  list where Android puts it. It used to live under Developers → Tools, which hid
//  it behind an NFC-capable iPhone on iOS 18 — on Mac Catalyst and iOS 17 there was
//  no way to reach it at all.
//
//  The section owns the whole file-transfer flow: the warning about what the backup
//  contains, the exporter and importer, the parsed-plan sheet and both failure alerts.
//

import SwiftUI
import MeshtasticProtobufs
import OSLog
import UniformTypeIdentifiers

struct BackupRestoreSection: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	/// The radio this window works with (feature 021, D-19).
	@Environment(\.windowRadio) private var windowRadio
	@Environment(\.modelContext) private var context

	/// True when the radio says a mesh administrator owns its configuration. The rows
	/// stay visible and disabled, with the reason, rather than disappearing.
	let isManaged: Bool

	@State private var isExportingConfig = false
	@State private var exportConfigDocument = DeviceProfileDocument()
	@State private var exportConfigFilename = "device-config"
	@State private var isPresentingExportFailedAlert = false
	@State private var exportFailedMessage = "The device configuration could not be prepared for export."
	@State private var isPresentingExportWarning = false

	@State private var isImportingConfig = false
	@State private var pendingImport: PendingImport?
	@State private var isPresentingImportFailedAlert = false
	@State private var importFailedMessage = "This file isn't a valid Meshtastic configuration."

	/// Identifiable wrapper so a parsed plan can drive `.sheet(item:)`.
	private struct PendingImport: Identifiable {
		let id = UUID()
		let plan: DeviceProfileImportPlan
	}

	private var connectedNode: NodeInfoEntity? {
		guard let num = accessoryManager.nodeNum(for: windowRadio) else { return nil }
		return getNodeInfo(id: num, context: context)
	}

	private var isEnabled: Bool {
		accessoryManager.isConnected(windowRadio) && connectedNode != nil && !isManaged
	}

	var body: some View {
		Section(header: Text("Backup & Restore")) {
			if isManaged {
				Label("This radio is managed and can only be changed by a remote admin.", systemImage: "lock.shield")
					.font(.callout)
					.foregroundStyle(.orange)
			}

			Button {
				isImportingConfig = true
			} label: {
				Label("Import Configuration", systemImage: "square.and.arrow.down")
			}
			.disabled(!isEnabled)

			Button {
				isPresentingExportWarning = true
			} label: {
				Label("Export Configuration", systemImage: "square.and.arrow.up")
			}
			.disabled(!isEnabled)

			if !accessoryManager.isConnected(windowRadio) || connectedNode == nil {
				Text("Connect to a node to back up or restore its configuration.")
					.font(.caption)
					.foregroundColor(.secondary)
			}
		}
		.confirmationDialog(
			"Export Device Configuration",
			isPresented: $isPresentingExportWarning,
			titleVisibility: .visible
		) {
			Button("Export Configuration") {
				// Re-resolve the connected node at confirm time — the entity is fetched fresh rather than
				// captured at button-tap, so it can't be a stale/faulted object if the device disconnects
				// while the dialog is open. Defer to the next runloop so presenting the file exporter isn't
				// swallowed by the confirmation dialog's dismissal animation.
				Task { @MainActor in
					guard let node = connectedNode else { return }
					exportConfiguration(for: node)
				}
			}
			Button("Cancel", role: .cancel) { }
		} message: {
			Text("This backup contains sensitive security material — your node's private key, admin keys, channel keys (PSKs), and Wi-Fi/MQTT passwords. Anyone with this file can join and administer your mesh, so only share it with people you trust.")
		}
		.fileExporter(
			isPresented: $isExportingConfig,
			document: exportConfigDocument,
			contentType: .meshtasticDeviceProfile,
			defaultFilename: exportConfigFilename
		) { result in
			switch result {
			case .success:
				Logger.services.info("Device configuration export succeeded.")
			case .failure(let error):
				// A user dismissing the export sheet can surface as a cancellation failure on some OS
				// versions — don't show an error for that, only for genuine write failures.
				if (error as? CocoaError)?.code == .userCancelled { break }
				Logger.services.error("Device configuration export failed: \(error.localizedDescription, privacy: .public)")
				// Surface the write failure in-app too — the file could not be saved (permissions,
				// disk full, file-provider error), not just a prepare/serialization failure.
				exportFailedMessage = "The device configuration could not be saved. Please try again."
				isPresentingExportFailedAlert = true
			}
		}
		.alert("Export Failed", isPresented: $isPresentingExportFailedAlert) {
			Button("OK") { }.keyboardShortcut(.defaultAction)
		} message: {
			Text(exportFailedMessage)
		}
		.fileImporter(
			isPresented: $isImportingConfig,
			allowedContentTypes: [.meshtasticDeviceProfile],
			allowsMultipleSelection: false
		) { result in
			handleImport(result)
		}
		.sheet(item: $pendingImport) { pending in
			ImportDeviceProfileView(plan: pending.plan)
				.environmentObject(accessoryManager)
				.trackScreen(.importDeviceProfile)
		}
		.alert("Import Failed", isPresented: $isPresentingImportFailedAlert) {
			Button("OK") { }.keyboardShortcut(.defaultAction)
		} message: {
			Text(importFailedMessage)
		}
	}

	/// Reads at most `cap + 1` bytes from a file so an oversized file is caught by the caller's size guard
	/// without loading the whole file into memory — independent of whether the file provider reports a size.
	private static func readCapped(_ url: URL, cap: Int) throws -> Data {
		let handle = try FileHandle(forReadingFrom: url)
		defer { try? handle.close() }
		return try handle.read(upToCount: cap + 1) ?? Data()
	}

	private func handleImport(_ result: Result<[URL], Error>) {
		switch result {
		case .success(let urls):
			guard let url = urls.first else { return }
			guard let node = connectedNode, let currentUser = node.user?.toProto() else {
				importFailedMessage = "Connect to a node before importing a configuration."
				isPresentingImportFailedAlert = true
				return
			}
			// Access the security-scoped file the picker handed us, and always release it afterwards.
			let didAccess = url.startAccessingSecurityScopedResource()
			defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
			do {
				// Read at most one byte past the cap so an oversized (or size-unreported) file is rejected
				// by parseDeviceProfile without ever loading the whole thing into memory.
				let data = try Self.readCapped(url, cap: DeviceProfileImportPlan.maxProfileBytes)
				let profile = try DeviceProfileImportPlan.parseDeviceProfile(data)
				// Pass the connected firmware version so items this radio cannot apply are reported rather
				// than sent into a silent no-op (the firmware acks unknown module configs as success).
				let plan = try DeviceProfileImportPlan(profile: profile, currentUser: currentUser,
													   currentSecurity: node.securityConfig?.protoConfig,
													   firmwareVersion: accessoryManager.firmwareVersion(for: windowRadio))
				pendingImport = PendingImport(plan: plan)
			} catch DeviceProfileImportError.nothingToImport {
				importFailedMessage = "This configuration file doesn't contain anything to import."
				isPresentingImportFailedAlert = true
			} catch {
				Logger.services.error("Device configuration import failed to parse: \(error.localizedDescription, privacy: .public)")
				importFailedMessage = "This file isn't a valid Meshtastic configuration."
				isPresentingImportFailedAlert = true
			}
		case .failure(let error):
			// A user dismissing the picker can surface as a cancellation — don't treat that as an error.
			if (error as? CocoaError)?.code == .userCancelled { return }
			Logger.services.error("Device configuration import picker failed: \(error.localizedDescription, privacy: .public)")
			importFailedMessage = "The configuration file could not be opened."
			isPresentingImportFailedAlert = true
		}
	}

	private func exportConfiguration(for node: NodeInfoEntity) {
		do {
			let data = try node.exportDeviceProfile().serializedData()
			exportConfigDocument = DeviceProfileDocument(profileData: data)
			exportConfigFilename = DeviceProfileDocument.exportFilename(
				shortName: node.user?.shortName,
				longName: node.user?.longName,
				date: .now
			)
			isExportingConfig = true
		} catch {
			Logger.services.error("Failed to serialize device profile: \(error.localizedDescription, privacy: .public)")
			exportFailedMessage = "The device configuration could not be prepared for export."
			isPresentingExportFailedAlert = true
		}
	}
}
