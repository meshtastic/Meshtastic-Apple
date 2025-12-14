//
//  FirmwareFile.swift
//  Meshtastic
//
//  Created by jake on 12/13/25.
//

import Foundation
import SwiftUI
import CoreData

extension FirmwareFile {
	enum FirmwareFileError: Error, LocalizedError {
		case invalidFilenamePrefix
		case parseError
		case unknownFileType
		case unknownTarget
		case unknownArchitecture
		case unknownVersion
		case unknownReleaseType
		case unknownRemoteURL
		
		var errorDescription: String? {
			switch self {
			case .invalidFilenamePrefix:
				return "Filename must start with `firmware-`."
			case .parseError:
				return "Unable to parse the components of the filename (target and version)."
			case .unknownFileType:
				return "Unknown file type.  May not be a firmware file."
			case .unknownTarget:
				return "Unknown platformio target."
			case .unknownArchitecture:
				return "Unknown architecture."
			case .unknownVersion:
				return "Unknown version."
			case .unknownReleaseType:
				return "Unknown release type (stable/alpha)."
			case .unknownRemoteURL:
				return "Unknown remote URL."
			}
		}
	}
}

// Various Enums and constants
extension FirmwareFile {
	enum DownloadStatus: Equatable {
		case notDownloaded
		case downloading
		case downloaded
		case error(String)
	}
	
	enum FirmwareType: String, Identifiable, CustomStringConvertible {
        var id: String { rawValue }
		var description: String { return rawValue }
		
		case uf2 = ".uf2"
		case bin = ".bin"
		case otaZip = "-ota.zip"
	}
	
	static let localFirmwareStorageURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
	static let remoteFirmwareURLPrefix = URL(string: "https://raw.githubusercontent.com/meshtastic/meshtastic.github.io/master/")!
}

class FirmwareFile: ObservableObject, Hashable, Equatable {
	let localUrl: URL
	let remoteUrl: URL?
	let versionId: String
	let platformioTarget: String
	let releaseType: FirmwareRelease.ReleaseType
	@Published var status: DownloadStatus
	let firmwareType: FirmwareType
	let architecure: Architecture
	let releaseNotes: String?
	
	let versionMajor, versionMinor, versionPatch: Int
	
	init(firmware: FirmwareReleaseEntity, hardware: DeviceHardwareEntity, type: FirmwareType? = nil) throws {
		var target: String?
		var architecture: Architecture?
		
		// Thread safe operationt to get the target and architecture
		// from the given DeviceHardwareEntity
		if let context = hardware.managedObjectContext {
			context.performAndWait {
				target = hardware.platformioTarget
				architecture = hardware.architecture.flatMap { Architecture(rawValue: $0) }
			}
		} else {
			// Detached, not yet inserted NSManagedObject
			target = hardware.platformioTarget
			architecture = hardware.architecture.flatMap { Architecture(rawValue: $0) }
		}
		
		guard let target else { throw FirmwareFileError.unknownTarget }
		self.platformioTarget = target
	
		guard let architecture else { throw FirmwareFileError.unknownArchitecture }
		self.architecure = architecture
		
		// Thread safe operation to get the versionf`rom the given FirmwareReleaseEntity
		var version: String?
		var releaseType: FirmwareRelease.ReleaseType?
		var releaseNotes: String?
		if let context = firmware.managedObjectContext {
			context.performAndWait {
				version = firmware.versionId
				releaseType = firmware.releaseType.flatMap { FirmwareRelease.ReleaseType(rawValue: $0) }
				releaseNotes = firmware.releaseNotes
			}
		} else {
			version = firmware.versionId
			releaseType = firmware.releaseType.flatMap { FirmwareRelease.ReleaseType(rawValue: $0) }
			releaseNotes = firmware.releaseNotes
		}
		
		self.releaseNotes = releaseNotes
		
		guard let version else { throw FirmwareFileError.unknownVersion }
		self.versionId = version
		
		let cleanString = version.hasPrefix("v") ? version.dropFirst() : Substring(version)
		let parts = cleanString.split(separator: ".")
		if parts.count >= 3 {
			self.versionMajor = Int(parts[0]) ?? 0
			self.versionMinor = Int(parts[1]) ?? 0
			self.versionPatch = Int(parts[2]) ?? 0
		} else {
			throw FirmwareFileError.parseError
		}
		
		guard let releaseType else { throw FirmwareFileError.unknownReleaseType }
		self.releaseType = releaseType
		
		// Calculate the filename
		// Regarding the force unwrap: validFilenameSuffixes should always return at least one type
		let defaultFileType = FirmwareFile.validFilenameSuffixes(forArchitecture: architecture).first!
		self.firmwareType = type ?? defaultFileType
		let fileNameVersion = versionId.hasPrefix("v") ? String(versionId.dropFirst()) : versionId
		let fileName = "firmware-\(target)-\(fileNameVersion)\(firmwareType)"
		self.localUrl = FirmwareFile.localFirmwareStorageURL.appendingPathComponent(fileName)
		self.remoteUrl = FirmwareFile.remoteFirmwareURLPrefix
			.appendingPathComponent("firmware-\(fileNameVersion)")
			.appendingPathComponent(fileName)
		
		if FileManager.default.fileExists(atPath: localUrl.path) {
			self.status = .downloaded
		} else {
			self.status = .notDownloaded
		}
	}
	
	init(localFile url: URL) throws {
		self.localUrl = url
		
		let fileName = url.lastPathComponent
		
		// Check Prefix
		guard fileName.hasPrefix("firmware-") else {
			throw FirmwareFileError.invalidFilenamePrefix
		}
		
		// Check and Strip Suffix (Extension)
		// We strip the prefix and suffix first to isolate "<target>-<version>"
		var coreName = String(fileName.dropFirst("firmware-".count))
		
		if fileName.hasSuffix("-ota.zip") {
			coreName = String(coreName.dropLast("-ota.zip".count))
			self.firmwareType = .otaZip
		} else if fileName.hasSuffix(".uf2") {
			coreName = String(coreName.dropLast(".uf2".count))
			self.firmwareType = .uf2
		} else if fileName.hasSuffix(".bin") {
			coreName = String(coreName.dropLast(".bin".count))
			self.firmwareType = .bin
		} else {
			// File does not match supported extensions
			throw FirmwareFileError.unknownFileType
		}
		
		// Extract Target and Version
		// Strategy: We assume the format is Target-Version.
		// Since Targets can have hyphens (e.g. "esp32-s3"), but Versions usually don't contain
		// the separating hyphen in this specific naming convention, we split by the *last* hyphen.
		guard let lastHyphenIndex = coreName.lastIndex(of: "-") else {
			throw FirmwareFileError.parseError
		}
		
		let target = String(coreName[..<lastHyphenIndex])
		var version = String(coreName[coreName.index(after: lastHyphenIndex)...])
		
		let cleanString = version.hasPrefix("v") ? version.dropFirst() : Substring(version)
		let parts = cleanString.split(separator: ".")
		if parts.count >= 3 {
			self.versionMajor = Int(parts[0]) ?? 0
			self.versionMinor = Int(parts[1]) ?? 0
			self.versionPatch = Int(parts[2]) ?? 0
		} else {
			throw FirmwareFileError.parseError
		}
		
		if !version.hasPrefix("v") {
			version = "v" + version
		}
		
		// Validation to ensure we didn't end up with empty strings
		guard !target.isEmpty, !version.isEmpty else {
			throw FirmwareFileError.parseError
		}
		
		self.versionId = version
		self.platformioTarget = target
		
		if FileManager.default.fileExists(atPath: url.path) {
			self.status = .downloaded
		} else {
			self.status = .notDownloaded
		}
		
		// Look up the architecture for this file
		let context = PersistenceController.shared.container.newBackgroundContext()
		var architecture: Architecture?
		context.performAndWait {
			let hardwareFetchRequest = DeviceHardwareEntity.fetchRequest()
			hardwareFetchRequest.predicate = NSPredicate(format: "platformioTarget == %@", target)
			hardwareFetchRequest.fetchLimit = 1
			let hardware = try? context.fetch(hardwareFetchRequest).first
			architecture = hardware?.architecture.flatMap { Architecture(rawValue: $0) }
		}
		
		guard let architecture else { throw FirmwareFileError.unknownArchitecture }
		self.architecure = architecture
		
		// Determine release type
		var releaseType: FirmwareRelease.ReleaseType = .unlisted
		var releaseNotes: String?
		context.performAndWait {
			let firmwareFetchRequest = FirmwareReleaseEntity.fetchRequest()
			firmwareFetchRequest.predicate = NSPredicate(format: "versionId == %@", version)
			firmwareFetchRequest.fetchLimit = 1
			if let firmware = try? context.fetch(firmwareFetchRequest).first {
				releaseType = firmware.releaseType.flatMap { FirmwareRelease.ReleaseType(rawValue: $0) } ?? .unlisted
				releaseNotes = firmware.releaseNotes
			}
		}
		self.releaseType = releaseType
		self.releaseNotes = releaseNotes
		
		let fileNameVersion = versionId.hasPrefix("v") ? String(versionId.dropFirst()) : versionId
		self.remoteUrl = FirmwareFile.remoteFirmwareURLPrefix
			.appendingPathComponent("firmware-\(fileNameVersion)")
			.appendingPathComponent(fileName)
	}
	
	@MainActor
	func download() async throws {
		guard let remoteUrl else {
			throw FirmwareFileError.unknownRemoteURL
		}
		Task {
			do {
				let (tempLocalUrl, response) = try await URLSession.shared.download(from: remoteUrl)
				
				if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
					throw URLError(.badServerResponse)
				}
				
				if FileManager.default.fileExists(atPath: localUrl.path) {
					try FileManager.default.removeItem(at: localUrl)
				}
				
				try FileManager.default.moveItem(at: tempLocalUrl, to: localUrl)
				
				self.status = .downloaded
				
			} catch {
				try? FileManager.default.removeItem(at: localUrl)
				self.status = .error(error.localizedDescription)
			}
		}
	}
	
	static func validFilenameSuffixes(forArchitecture: Architecture) -> [FirmwareType] {
		switch forArchitecture {
		case .esp32, .esp32C3, .esp32S3, .esp32C6:
			return [.bin]
		case .nrf52840:
			return [.uf2, .otaZip]
		case .rp2040:
			return [.uf2]
		}
	}
	
	static func == (lhs: FirmwareFile, rhs: FirmwareFile) -> Bool {
		return lhs.localUrl == rhs.localUrl &&
			   lhs.remoteUrl == rhs.remoteUrl &&
			   lhs.versionId == rhs.versionId &&
			   lhs.platformioTarget == rhs.platformioTarget &&
			   lhs.releaseType == rhs.releaseType &&
			   lhs.firmwareType == rhs.firmwareType &&
			   lhs.architecure == rhs.architecure
	}

	func hash(into hasher: inout Hasher) {
		hasher.combine(localUrl)
		hasher.combine(remoteUrl)
		hasher.combine(versionId)
		hasher.combine(platformioTarget)
		hasher.combine(releaseType)
		hasher.combine(firmwareType)
		hasher.combine(architecure)
	}
}

