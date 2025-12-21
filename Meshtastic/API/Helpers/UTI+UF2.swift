//
//  UTI+UF2.swift
//  Meshtastic
//
//  Created by jake on 12/12/25.
//

import UniformTypeIdentifiers
import SwiftUI

extension UTType {
	// Define a custom type for your firmware
	// Identifier: Use your bundle ID prefix (e.g., com.yourcompany.firmware)
	static let UF2Firmware = UTType(exportedAs: "com.meshtastic.uf2-firmware")
}


struct FirmwareDocument: FileDocument {
	// 1. Tell the system this document supports your custom UTType
	static var readableContentTypes: [UTType] { [.UF2Firmware] }

	var firmwareData: Data

	init(data: Data) {
		self.firmwareData = data
	}

	// Initialize from an existing file (Read)
	init(configuration: ReadConfiguration) throws {
		guard let data = configuration.file.regularFileContents else {
			throw CocoaError(.fileReadCorruptFile)
		}
		self.firmwareData = data
	}

	// Prepare data for saving (Write)
	func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
		return FileWrapper(regularFileWithContents: firmwareData)
	}
}
