//
//  DeviceProfileDocument.swift
//  Meshtastic
//
//  A `FileDocument` wrapper around a serialized `DeviceProfile` protobuf, used with `.fileExporter`
//  to save a node's whole configuration. The `.cfg` binary format matches the Android app so the
//  exported file can be re-imported across the Meshtastic ecosystem.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
	/// The Meshtastic device-profile (`.cfg`) export type, shared with the Android app and CLI.
	/// Defined once and reused by both the document and the exporter so the file extension stays
	/// consistent instead of being recreated inline at each call site.
	static let meshtasticDeviceProfile = UTType(filenameExtension: "cfg", conformingTo: .data) ?? .data
}

struct DeviceProfileDocument: FileDocument {

	static let readableContentTypes = [UTType.meshtasticDeviceProfile]

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

	/// Builds an Android-compatible default filename (without extension) for an exported profile:
	/// `Meshtastic_<shortName>_<yyyyMMdd>_nodeConfig`. The `.cfg` suffix is appended by the exporter
	/// from `UTType.meshtasticDeviceProfile`. Mirrors Android's `Meshtastic_${shortName}_${yyyyMMdd}_nodeConfig.cfg`.
	/// Falls back to the long name, then `Node`, when no short name is set, and strips path-illegal
	/// characters so the exporter doesn't fail or mangle the saved file.
	static func exportFilename(shortName: String?, longName: String?, date: Date) -> String {
		let rawName = [shortName, longName]
			.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
			.first { !$0.isEmpty } ?? "Node"
		let safeName = rawName
			.components(separatedBy: CharacterSet(charactersIn: "/\\:"))
			.joined(separator: "-")
			// Trim leading/trailing dashes and whitespace so a name made entirely of illegal
			// characters (e.g. "/" or "::") collapses to empty and uses the "Node" fallback
			// instead of a string of dashes.
			.trimmingCharacters(in: CharacterSet(charactersIn: "-").union(.whitespacesAndNewlines))
		return "Meshtastic_\(safeName.isEmpty ? "Node" : safeName)_\(date.exportDateStamp)_nodeConfig"
	}
}
