//
//  DeviceProfileDocument.swift
//  Meshtastic
//
//  A `FileDocument` wrapper around a serialized `DeviceProfile` protobuf, used with `.fileExporter`
//  to save a node's whole configuration. The `.cfg` binary format matches the Android app so the
//  exported file can be re-imported across the Meshtastic ecosystem.
//

import SwiftUI
import UniformTypeIdentifiers

struct DeviceProfileDocument: FileDocument {

	static let readableContentTypes = [UTType(filenameExtension: "cfg") ?? .data]

	var profileData: Data

	init(profileData: Data = Data()) {
		self.profileData = profileData
	}

	init(configuration: ReadConfiguration) throws {
		guard let data = configuration.file.regularFileContents else {
			throw CocoaError(.fileReadCorruptFile)
		}
		profileData = data
	}

	func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
		FileWrapper(regularFileWithContents: profileData)
	}
}
