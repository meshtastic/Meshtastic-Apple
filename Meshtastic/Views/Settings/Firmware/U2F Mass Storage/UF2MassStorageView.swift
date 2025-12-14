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
	@Environment(\.managedObjectContext) var context
	
	@State private var isExporting = false
	@State private var document: FirmwareDocument?
	
	let fileURL: URL
	var body: some View {
		NavigationView { // Use a NavigationView for a title bar
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
					.cornerRadius(12)
					
					Divider()
					
					VStack(alignment: .leading, spacing: 12) {
						Label("Step 1: Connect Device", systemImage: "1.circle.fill")
							.font(.headline)
						
						Text("Place your device in DFU mode and connect it via USB.")
							.fixedSize(horizontal: false, vertical: true)
						
						Text("If connected, use the button below to reboot into DFU. Otherwise, press your device's reset button twice rapidly.")
							.font(.caption)
							.foregroundStyle(.secondary)
						
						resetIntoOTAButton() // Ensure this button has suitable padding/styling
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
						
						exportFirmwareButton() // Ensure this button is prominent
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
				}.padding()
			}.navigationTitle("UF2 Firmware Update")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .navigationBarLeading) {
					// 2. Create a button that calls dismiss()
					Button("Done") {
						dismiss()
					}
				}
			}
		}.fileExporter(
			isPresented: $isExporting,
			document: document,
			contentType: .UF2Firmware, // Use your custom type here
			defaultFilename: UUID().uuidString // No extension needed here, UTType handles it
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
			Label(" Send Reboot into DFU", systemImage: "square.and.arrow.down")
		}.buttonStyle(.borderedProminent)
			.controlSize(.large)
			.frame(maxWidth: .infinity)
			.cornerRadius(10).disabled(accessoryManager.activeDeviceNum == nil)
	}
	
	@ViewBuilder
	func exportFirmwareButton() -> some View {
		Button(action: {
			prepareFirmwareForExport()
		}) {
			Label("Save Firmware to USB", systemImage: "externaldrive.fill")
		}.buttonStyle(.borderedProminent)
			.controlSize(.large)
			.frame(maxWidth: .infinity)
	}
	
	func prepareFirmwareForExport() {
		if let data = try? Data(contentsOf: fileURL) {
			// 2. Initialize the document
			self.document = FirmwareDocument(data: data)
			
			// 3. Trigger the sheet
			self.isExporting = true
		}
	}
}
