//
//  UF2MassStorageView.swift
//  Meshtastic
//
//  Created by jake on 12/12/25.
//

import SwiftUI
import OSLog

struct UF2MassStorageView: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) var dismiss
	@Environment(\.modelContext) var context
	
	@State private var isExporting = false
	@State private var document: FirmwareDocument?
	
	let fileURL: URL
	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(spacing: 20) {
					
					HStack(alignment: .top, spacing: 12) {
						Image(systemName: "lock.shield")
							.font(.title2)
							.foregroundStyle(.blue)
						
						Text("For security reasons, iOS cannot write directly to external USB devices. You must save the file manually.")
							.font(.callout)
					}
					.padding()
					.background(Color.secondary.opacity(0.1))
					.clipShape(RoundedRectangle(cornerRadius: 12))
					
					Divider()
					
					VStack(alignment: .leading, spacing: 12) {
						Label("Step 1: Connect Device", systemImage: "1.circle.fill")
							.font(.headline)
						
						Text("Place your device in DFU mode and connect it via USB.")
							.fixedSize(horizontal: false, vertical: true)
						
						Text("If connected, use the button below to reboot into DFU. Otherwise, press your device's reset button twice rapidly.")
							.font(.caption)
							.foregroundStyle(.secondary)
						
						resetIntoOTAButton()
					}
					
					Divider()
					
					VStack(alignment: .leading, spacing: 12) {
						Label("Step 2: Save the File", systemImage: "2.circle.fill")
							.font(.headline)
						
						VStack(alignment: .leading, spacing: 8) {
							Text("• Tap the **Save Firmware to USB** button below.")
							Text("• Navigate all the way back to **Locations** in the file picker.")
							Text("• Select your USB device and tap **Save**.")
						}
						.font(.callout)
						
						exportFirmwareButton()
					}
					
					Divider()
					
					VStack(alignment: .leading, spacing: 10) {
						Label("Important Notes", systemImage: "info.circle")
							.font(.caption.bold())
							.foregroundStyle(.secondary)
						
						Text("• The filename will be a random string ending in `.uf2` to prevent iOS caching.")
						Text("• You may see an error saying the file could not be saved. This is normal, as the device disconnects immediately after updating.")
					}
					.font(.caption)
					.foregroundStyle(.secondary)
				}
				.padding()
			}
			.navigationTitle("UF2 Firmware Update")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button {
						dismiss()
					} label: {
						Image(systemName: "xmark")
					}
					.accessibilityLabel(String(localized: "Done", comment: "VoiceOver: dismiss the UF2 firmware update sheet"))
				}
			}
		}
		#if targetEnvironment(macCatalyst)
		// Mac Catalyst gives a sheet a fixed 620x680 window, about 20pt shorter than this
		// content needs, so the Important Notes section sits below the bottom edge. Ask for a
		// taller sheet; Catalyst clamps the request to the app window, and the ScrollView
		// still handles whatever is left over.
		.frame(minHeight: 740)
		#endif
		.fileExporter(
			isPresented: $isExporting,
			document: document,
			contentType: .UF2Firmware,
			defaultFilename: UUID().uuidString
		) { result in
			switch result {
			case .success(let url):
				Logger.services.info("Firmware Saved to \(url.path)")
			case .failure(let error):
				Logger.services.error("Failed to save firmware: \(error.localizedDescription)")
			}
		}
	}
	
	@ViewBuilder
	func resetIntoOTAButton() -> some View {
		Button {
			let connectedNode = getNodeInfo(id: accessoryManager.activeDeviceNum ?? 0, context: context)
			if let connectedNode, let user = connectedNode.user {
				Task {
					do {
						try await accessoryManager.sendEnterDfuMode(fromUser: user, toUser: user)
					} catch {
						Logger.mesh.error("Reboot Failed")
					}
				}
			}
		} label: {
			Label("Send Reboot into DFU", systemImage: "square.and.arrow.down")
		}
		.buttonStyle(.borderedProminent)
		.controlSize(.large)
		.frame(maxWidth: .infinity)
		.clipShape(RoundedRectangle(cornerRadius: 10))
		.disabled(accessoryManager.activeDeviceNum == nil)
	}
	
	@ViewBuilder
	func exportFirmwareButton() -> some View {
		Button {
			prepareFirmwareForExport()
		} label: {
			Label("Save Firmware to USB", systemImage: "externaldrive.fill")
		}
		.buttonStyle(.borderedProminent)
		.controlSize(.large)
		.frame(maxWidth: .infinity)
	}
	
	func prepareFirmwareForExport() {
		if let data = try? Data(contentsOf: fileURL) {
			self.document = FirmwareDocument(data: data)
			self.isExporting = true
		}
	}
}

#Preview {
	UF2MassStorageView(fileURL: URL(fileURLWithPath: "/tmp/firmware-rak4631.uf2"))
		.environmentObject(AccessoryManager.shared)
}
