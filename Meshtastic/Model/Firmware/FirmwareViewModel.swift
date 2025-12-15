//
//  FirmwareViewModel.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/11/25.
//

import Foundation
import SwiftUI
import CoreData
import OSLog

extension FirmwareViewModel {
	enum FirmwareViewModelError: Error, LocalizedError {
		case timedOut(TimeInterval)
		case unknownFirmwareVersion
		case unableToFindOrCreateEntity
		case unknownArchitecture
		case unknownPlatformIOTarget
		var errorDescription: String? {
			switch self {
			case .timedOut(let seconds):
				return "The operation timed out after \(seconds) seconds."
			case .unknownFirmwareVersion:
				return "Unknown firmware version."
			case .unableToFindOrCreateEntity:
				return "Unable to find or create Core Data entity."
			case .unknownArchitecture:
				return "Unknown architecture."
			case .unknownPlatformIOTarget:
				return "Unknown platformio target."
			}
		}
	}
}

class FirmwareViewModel: ObservableObject {
	@Published var firmwareFiles: [FirmwareFile] = []
	let hardware: DeviceHardwareEntity
	
	init(forHardware: DeviceHardwareEntity) {
		self.hardware = forHardware
		Task {
			try? await MeshtasticAPI.shared.refreshFirmwareAPIData()
			refresh()
		}
	}
	
	func refresh() {
		var newFirmwareList = [String: FirmwareFile]()
		
		// First, loop through all firmware entities and create an entry for those
		let context = PersistenceController.shared.container.newBackgroundContext()
		context.performAndWait {
			let fetchRequest = FirmwareReleaseEntity.fetchRequest()
			do {
				let firmwareReleases = try context.fetch(fetchRequest)
				for release in firmwareReleases {
					if let architecture = hardware.architecture.flatMap({ Architecture(rawValue: $0) }) {
						for firmwareType in FirmwareFile.validFilenameSuffixes(forArchitecture: architecture) {
							let firmwareFile = try FirmwareFile(firmware: release, hardware: hardware, type: firmwareType)
							newFirmwareList[firmwareFile.localUrl.lastPathComponent] = firmwareFile
						}
					} else {
						// Just the default
						let firmwareFile = try FirmwareFile(firmware: release, hardware: hardware)
						newFirmwareList[firmwareFile.localUrl.lastPathComponent] = firmwareFile
					}
				}
			} catch {
				Logger.services.error("Error fetching firmware releases: \(error)")
			}
		}
		
		// Now look for unlisted files on the filesystem
		let fileManager = FileManager.default
		var isDirectory: ObjCBool = false
		
		// 1. Check if directory exists
		if !fileManager.fileExists(atPath: FirmwareFile.localFirmwareStorageURL.path, isDirectory: &isDirectory) {
			return
		}
		
		// 2. Iterate the files in the folder
		do {
			let fileURLs = try fileManager.contentsOfDirectory(at: FirmwareFile.localFirmwareStorageURL, includingPropertiesForKeys: nil)
			
			for url in fileURLs {
				do {
					let firmwareFile = try FirmwareFile(localFile: url)
					if firmwareFile.platformioTarget != hardware.platformioTarget {
						// Skip if this is not for the current hardware we are dealing with
						continue
					}
					
					if newFirmwareList[firmwareFile.localUrl.lastPathComponent] != nil {
						// Already have this one from the Core Data entries
						continue
					}
					newFirmwareList[firmwareFile.localUrl.lastPathComponent] = firmwareFile
				} catch {
					Logger.services.error("Error parsing local firmware file at \(url.path): \(error)")
				}
			}
		} catch {
			Logger.services.error("Error loading firmware files: \(error)")
		}
		
		Task { @MainActor in
			// Keep the list sorted by version, with deterministic ordering of the firmware type
			self.firmwareFiles = newFirmwareList.values.sorted {
				if ($0.versionMajor, $0.versionMinor, $0.versionPatch) == ($1.versionMajor, $1.versionMinor, $1.versionPatch) {
					// If versions are equal, sort by firmwareType (assuming it's String or Comparable)
					return String(describing: $0.firmwareType) < String(describing: $1.firmwareType)
				}
				return ($0.versionMajor, $0.versionMinor, $0.versionPatch) > ($1.versionMajor, $1.versionMinor, $1.versionPatch)
			}
		}
	}

	func mostRecentFirmwareVersion(forReleaseType releaseType: FirmwareRelease.ReleaseType) -> String? {
		let context = PersistenceController.shared.container.newBackgroundContext()
		var versionId: String?
		
		try? context.performAndWait {
			let fetchRequest = FirmwareReleaseEntity.fetchRequest()
			fetchRequest.predicate = NSPredicate(format: "releaseType == %@", releaseType.rawValue)
			fetchRequest.sortDescriptors = [NSSortDescriptor(key: "versionMajor", ascending: false),
											NSSortDescriptor(key: "versionMinor", ascending: false),
											NSSortDescriptor(key: "versionPatch", ascending: false)]
			fetchRequest.fetchLimit = 1
			do {
				if let firmwareRelease = try context.fetch(fetchRequest).first {
					versionId = firmwareRelease.versionId
				}
			}
		}
		return versionId
	}
	
	func firmwareFiles(forVersionId versionId: String) -> [FirmwareFile] {
		return firmwareFiles.filter({ $0.versionId == versionId })
	}
	
	func mostRecentFirmware(forReleaseType releaseType: FirmwareRelease.ReleaseType) -> [FirmwareFile] {
		if let versionId = mostRecentFirmwareVersion(forReleaseType: releaseType) {
			return firmwareFiles.filter { $0.releaseType == releaseType && $0.versionId == versionId }
		} else {
			// Worst case, rely on sorting and only return the first one
			let firmwareOfType = firmwareFiles.filter { $0.releaseType == releaseType }
			if let singleVersionToReturn = firmwareOfType.first {
				return [singleVersionToReturn]
			}
		}
		return []
	}
	
	func downloadedFirmware(includeInProgressDownloads: Bool = true) -> [FirmwareFile] {
		if includeInProgressDownloads {
			return firmwareFiles.filter( { $0.status == .downloading || $0.status == .downloaded })
		} else {
			return firmwareFiles.filter( { $0.status == .downloaded })
		}
	}

	var hasDownloadedFirmware: Bool {
		return !downloadedFirmware(includeInProgressDownloads: false).isEmpty
	}
	
	func delete(_ filesToDelete:[FirmwareFile]) {
		// 1. Create a bucket for files that were actually deleted
		var deletedFiles = Set<FirmwareFile>()

		// 2. Perform Disk I/O
		for file in filesToDelete {
			do {
				try FileManager.default.removeItem(at: file.localUrl)
				deletedFiles.insert(file)
			} catch {
				// Optional: Handle "File not found" as a success so it clears from UI
				if (error as NSError).code == NSFileNoSuchFileError {
					deletedFiles.insert(file)
				} else {
					Logger.services.error("Failed to delete \(file.localUrl.path): \(error)")
				}
			}
		}

		// 3. Update State ONCE (Efficient O(n))
		// This triggers the UI update/Publisher only one time
		firmwareFiles.removeAll { deletedFiles.contains($0) }
	}
}
