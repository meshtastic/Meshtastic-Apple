//
//  Tools.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 12/31/25.
//

import SwiftUI
#if !targetEnvironment(macCatalyst)
import CoreNFC
#endif
import MeshtasticProtobufs
import OSLog
import UniformTypeIdentifiers

@available(iOS 18, *)
struct Tools: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.modelContext) private var context

	#if !targetEnvironment(macCatalyst)
	@StateObject private var nfcReader = NFCReader()
	#endif

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

	var connectedNode: NodeInfoEntity? {
		if let num = accessoryManager.activeDeviceNum {
			return getNodeInfo(id: num, context: context)
		}
		return nil
	}

	var qrString: String {
		guard let connectedNode = connectedNode else {
			return ""
		}

		var contact = SharedContact()
		contact.nodeNum = UInt32(connectedNode.num)
		contact.user = connectedNode.toProto().user
		contact.manuallyVerified = true

		do {
			let contactString = try contact.serializedData().base64EncodedString()
			return "https://meshtastic.org/v/#" + contactString.base64ToBase64url()
		} catch {
			Logger.services.error("Error serializing contact: \(error)")
			return ""
		}
	}

	var body: some View {
		VStack {
			List {
				Section(header: Text("Create Node Contact NFC Tag")) {
					if let node = connectedNode {
						Text("Node Name: \(node.user?.longName ?? "Unknown".localized)")
						#if !targetEnvironment(macCatalyst)
						Button {
							nfcReader.scan(theActualData: qrString)
						} label: {
							Label("Write Contact to NFC Tag", systemImage: "tag")
						}
						.disabled(qrString.isEmpty)
						#endif
					}
				}

				Section(header: Text("Export Device Configuration")) {
					if let node = connectedNode {
						Text("Save the connected node's full configuration (radio, module, and channel settings) to a file you can back up or import on another device.")
							.font(.caption)
							.foregroundColor(.secondary)
						Button {
							isPresentingExportWarning = true
						} label: {
							Label("Export Configuration", systemImage: "square.and.arrow.up")
						}
					} else {
						Text("Connect to a node to export its configuration.")
							.font(.caption)
							.foregroundColor(.secondary)
					}
				}

				Section(header: Text("Import Device Configuration")) {
					if connectedNode != nil {
						Text("Apply a saved configuration file (radio, module, and channel settings) to the connected node.")
							.font(.caption)
							.foregroundColor(.secondary)
						Button {
							isImportingConfig = true
						} label: {
							Label("Import Configuration", systemImage: "square.and.arrow.down")
						}
					} else {
						Text("Connect to a node to import a configuration.")
							.font(.caption)
							.foregroundColor(.secondary)
					}
				}
			}
		}
		.navigationTitle("Tools")
		.navigationBarTitleDisplayMode(.inline)
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
				DispatchQueue.main.async {
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
				let plan = try DeviceProfileImportPlan(profile: profile, currentUser: currentUser,
													   currentSecurity: node.securityConfig?.protoConfig)
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

@available(iOS 18, *)
#Preview {
	Tools()
		.environmentObject(AccessoryManager.shared)
		.modelContainer(PersistenceController.preview.container)
}

#if !targetEnvironment(macCatalyst)
@available(iOS 18, *)
final class NFCReader: NSObject, ObservableObject, NFCNDEFReaderSessionDelegate {

	private let logger = Logger(subsystem: "org.meshtastic.app", category: "NFC")
	private var payloadString = ""
	private var session: NFCNDEFReaderSession?

	func scan(theActualData: String) {
		payloadString = theActualData

		session = NFCNDEFReaderSession(
			delegate: self,
			queue: nil,
			invalidateAfterFirstRead: false
		)

		session?.alertMessage = "Hold your iPhone near the NFC tag."
		session?.begin()
	}

	func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
		logger.debug("NFC session became active")
	}

	func readerSession(_ session: NFCNDEFReaderSession,
	                   didInvalidateWithError error: Error) {
		logger.error("NFC session invalidated: \(error.localizedDescription)")
	}

	func readerSession(_ session: NFCNDEFReaderSession,
	                   didDetectNDEFs messages: [NFCNDEFMessage]) {
	}

	func readerSession(_ session: NFCNDEFReaderSession,
	                   didDetect tags: [NFCNDEFTag]) {

		guard tags.count == 1, let tag = tags.first else {
			session.alertMessage = "More than one tag detected. Please present only one."
			DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) {
				session.restartPolling()
			}
			return
		}

		session.connect(to: tag) { error in
			if let error {
				self.logger.error("Failed to connect to tag: \(error.localizedDescription)")
				session.alertMessage = "Failed to connect to tag."
				session.invalidate()
				return
			}

			tag.queryNDEFStatus { status, capacity, error in
				if let error {
					self.logger.error("Failed to query NDEF status: \(error.localizedDescription)")
					session.alertMessage = "Failed to read tag."
					session.invalidate()
					return
				}
				self.logger.debug("Tag NDEF status: \(String(describing: status)), capacity: \(capacity) bytes")

				switch status {
				case .notSupported:
					self.logger.error("Tag does not support NDEF")
					session.alertMessage = "Tag does not support NDEF."
					session.invalidate()

				case .readOnly:
					self.logger.error("Tag is read-only")
					session.alertMessage = "Tag is read-only."
					session.invalidate()

				case .readWrite:
					guard let payload =
						NFCNDEFPayload.wellKnownTypeURIPayload(
							string: self.payloadString
						) else {
						self.logger.error("Invalid NDEF payload")
						session.alertMessage = "Invalid payload."
						session.invalidate()
						return
					}

					let message = NFCNDEFMessage(records: [payload])

					guard message.length <= capacity else {
						self.logger.error("Payload (\(message.length) bytes) exceeds tag capacity (\(capacity) bytes)")
						session.alertMessage = "Tag too small to hold contact data."
						session.invalidate()
						return
					}

					tag.writeNDEF(message) { error in
						if let error {
							self.logger.error("Failed to write NDEF: \(error.localizedDescription)")
							session.alertMessage = "Failed to write tag."
						} else {
							self.logger.info("Successfully wrote NFC tag")
							session.alertMessage = "NFC tag written successfully."
						}
						session.invalidate()
					}

				@unknown default:
					self.logger.error("Unsupported NDEF status")
					session.alertMessage = "Unsupported tag status."
					session.invalidate()
				}
			}
		}
	}
}
#endif
