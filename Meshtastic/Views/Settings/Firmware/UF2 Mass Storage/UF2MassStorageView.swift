//
//  UF2MassStorageView.swift
//  Meshtastic
//
//  Created by jake on 12/12/25.
//

import SwiftUI
import OSLog

struct UF2MassStorageView: View {
	@Environment(\.dismiss) var dismiss

	@State private var isExporting = false
	@State private var document: FirmwareDocument?

	let fileURL: URL
	var body: some View {
		FirmwareUpdateScreen(
			title: Text("Firmware Update", comment: "Title of the firmware update screen"),
			onClose: { dismiss() }
		) {
			FirmwareUpdateCard(
				title: String(localized: "Update Over USB", comment: "Title of the USB firmware update screen"),
				message: String(localized: "The firmware goes on as a file you save onto the radio's USB drive.", comment: "Message on the USB firmware update screen")
			)

			FirmwareUSBUpdateModeStep()

			FirmwareUpdateStep(
				number: 2,
				title: String(localized: "Save the firmware onto the radio", comment: "USB firmware update step title")
			) {
				Text("Tap Save Firmware, go back to Locations in the file picker, choose the radio's drive and tap Save.",
					 comment: "USB firmware update step: how to save the file onto the radio's drive")
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
				Button {
					prepareFirmwareForExport()
				} label: {
					Text("Save Firmware", comment: "Button that saves the firmware file onto the radio's USB drive")
						.frame(maxWidth: .infinity)
				}
				.hostedWindowOnly()
				.buttonStyle(.borderedProminent)
				.tint(.accentFill)
				.controlSize(.large)
			}

			FirmwareUpdateNotes(notes: [
				String(localized: "The radio restarts as soon as the file is written, so the file picker may say it couldn't save. That's expected.", comment: "Note on the USB firmware update screen"),
				String(localized: "The file gets a random name so iOS doesn't reuse an old copy.", comment: "Note on the USB firmware update screen")
			])
		}
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
