//
//  FirmwareViewModel.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/11/25.
//

import Foundation
import SwiftUI
@preconcurrency import SwiftData
import OSLog

extension ReleaseType: Sendable {}
extension Architecture: Sendable {}

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

extension FirmwareViewModel {
	struct FirmwareHardwareSnapshot: Sendable {
		let platformioTarget: String?
		let architecture: Architecture?

		init(platformioTarget: String?, architecture: Architecture?) {
			self.platformioTarget = platformioTarget
			self.architecture = architecture
		}
	}

	struct FirmwareReleaseSnapshot: Sendable {
		let versionId: String
		let releaseType: ReleaseType
		let releaseNotes: String?

		init(versionId: String, releaseType: ReleaseType, releaseNotes: String?) {
			self.versionId = versionId
			self.releaseType = releaseType
			self.releaseNotes = releaseNotes
		}

		init(_ release: FirmwareReleaseEntity) throws {
			guard let releaseType = release.releaseType.flatMap({ ReleaseType(rawValue: $0) }) else {
				throw FirmwareFile.FirmwareFileError.unknownReleaseType
			}
			guard FirmwareViewModel.parsedVersion(release.versionId) != nil else {
				throw FirmwareFile.FirmwareFileError.parseError
			}
			self.init(
				versionId: release.versionId,
				releaseType: releaseType,
				releaseNotes: release.releaseNotes
			)
		}
	}

	struct FirmwareFileSnapshot: Sendable {
		let localUrl: URL
		let remoteUrlCandidates: [URL]
		let versionId: String
		let platformioTarget: String
		let releaseType: ReleaseType
		let status: FirmwareFile.DownloadStatus
		let firmwareType: FirmwareFile.FirmwareType
		let architecture: Architecture
		let releaseNotes: String?
		let versionMajor: Int
		let versionMinor: Int
		let versionPatch: Int
	}

	struct FirmwareCatalogSnapshotError: Sendable {
		let localFileURL: URL
		let message: String
	}

	struct FirmwareCatalogSnapshot: Sendable {
		let files: [FirmwareFileSnapshot]
		let localFileErrors: [FirmwareCatalogSnapshotError]
	}

	struct RefreshGeneration {
		private var current = 0
		private var activeCatalogMutations = 0

		mutating func begin() -> Int {
			current += 1
			return current
		}

		mutating func beginCatalogMutation() {
			activeCatalogMutations += 1
			invalidateForCatalogMutation()
		}

		mutating func endCatalogMutation() {
			activeCatalogMutations = max(activeCatalogMutations - 1, 0)
			invalidateForCatalogMutation()
		}

		mutating func invalidateForCatalogMutation() {
			current += 1
		}

		func isCurrent(_ generation: Int) -> Bool {
			activeCatalogMutations == 0 && generation == current
		}
	}

	nonisolated static func makeFirmwareCatalogSnapshot(
		releases: [FirmwareReleaseSnapshot],
		localFileURLs: [URL],
		hardware: FirmwareHardwareSnapshot,
		localeTags: [String]
	) -> FirmwareCatalogSnapshot {
		let localFileNames = Set(localFileURLs.map(\.lastPathComponent))
		var releasesByVersion = [String: FirmwareReleaseSnapshot]()
		for release in releases where releasesByVersion[release.versionId] == nil {
			releasesByVersion[release.versionId] = release
			if let normalizedVersionId = Self.parsedVersion(release.versionId)?.versionId {
				releasesByVersion[normalizedVersionId] = release
			}
		}
		var filesByName = [String: FirmwareFileSnapshot]()
		var localFileErrors = [FirmwareCatalogSnapshotError]()

		if let target = hardware.platformioTarget, let architecture = hardware.architecture {
			for release in releases {
				guard let version = Self.parsedVersion(release.versionId) else { continue }
				for firmwareType in FirmwareFile.validFilenameSuffixes(forArchitecture: architecture) {
					let fileName = Self.firmwareFileName(target: target, version: version.fileNameVersion, firmwareType: firmwareType)
					filesByName[fileName] = FirmwareFileSnapshot(
						localUrl: FirmwareFile.localFirmwareStorageURL.appendingPathComponent(fileName),
						remoteUrlCandidates: FirmwareFile.makeRemoteURLCandidates(
							target: target,
							version: version.fileNameVersion,
							firmwareType: firmwareType,
							localeTags: localeTags
						),
						versionId: release.versionId,
						platformioTarget: target,
						releaseType: release.releaseType,
						status: localFileNames.contains(fileName) ? .downloaded : .notDownloaded,
						firmwareType: firmwareType,
						architecture: architecture,
						releaseNotes: release.releaseNotes,
						versionMajor: version.major,
						versionMinor: version.minor,
						versionPatch: version.patch
					)
				}
			}
		}

		for localFileURL in localFileURLs {
			do {
				let localFile = try Self.parseLocalFirmwareFile(localFileURL)
				guard localFile.platformioTarget == hardware.platformioTarget else { continue }
				guard filesByName[localFileURL.lastPathComponent] == nil else { continue }
				guard let architecture = hardware.architecture else {
					throw FirmwareFile.FirmwareFileError.unknownArchitecture
				}
				let release = releasesByVersion[localFile.version.versionId]
				filesByName[localFileURL.lastPathComponent] = FirmwareFileSnapshot(
					localUrl: localFileURL,
					remoteUrlCandidates: FirmwareFile.makeRemoteURLCandidates(
						target: localFile.platformioTarget,
						version: localFile.version.fileNameVersion,
						firmwareType: localFile.firmwareType,
						localeTags: []
					),
					versionId: localFile.version.versionId,
					platformioTarget: localFile.platformioTarget,
					releaseType: release?.releaseType ?? .unlisted,
					status: .downloaded,
					firmwareType: localFile.firmwareType,
					architecture: architecture,
					releaseNotes: release?.releaseNotes,
					versionMajor: localFile.version.major,
					versionMinor: localFile.version.minor,
					versionPatch: localFile.version.patch
				)
			} catch {
				localFileErrors.append(FirmwareCatalogSnapshotError(
					localFileURL: localFileURL,
					message: String(describing: error)
				))
			}
		}

		return FirmwareCatalogSnapshot(
			files: filesByName.values.sorted(by: Self.isFirmwareFileOrderedBefore(_:_:)),
			localFileErrors: localFileErrors
		)
	}

	nonisolated private static func firmwareFileName(
		target: String,
		version: String,
		firmwareType: FirmwareFile.FirmwareType
	) -> String {
		"firmware-\(target)-\(version)\(firmwareType.rawValue)"
	}

	nonisolated private struct ParsedFirmwareVersion {
		let versionId: String
		let fileNameVersion: String
		let major: Int
		let minor: Int
		let patch: Int
	}

	nonisolated private struct ParsedLocalFirmwareFile {
		let platformioTarget: String
		let version: ParsedFirmwareVersion
		let firmwareType: FirmwareFile.FirmwareType
	}

	nonisolated private static func parsedVersion(_ versionId: String) -> ParsedFirmwareVersion? {
		guard !versionId.isEmpty else { return nil }
		let cleanString = versionId.hasPrefix("v") ? versionId.dropFirst() : Substring(versionId)
		let parts = cleanString.split(separator: ".")
		guard parts.count >= 3 else { return nil }
		return ParsedFirmwareVersion(
			versionId: versionId.hasPrefix("v") ? versionId : "v\(versionId)",
			fileNameVersion: String(cleanString),
			major: Int(parts[0]) ?? 0,
			minor: Int(parts[1]) ?? 0,
			patch: Int(parts[2]) ?? 0
		)
	}

	nonisolated private static func parseLocalFirmwareFile(_ url: URL) throws -> ParsedLocalFirmwareFile {
		let fileName = url.lastPathComponent
		guard fileName.hasPrefix("firmware-") else {
			throw FirmwareFile.FirmwareFileError.invalidFilenamePrefix
		}

		let firmwareType: FirmwareFile.FirmwareType
		var coreName = String(fileName.dropFirst("firmware-".count))
		if fileName.hasSuffix("-ota.zip") {
			coreName = String(coreName.dropLast("-ota.zip".count))
			firmwareType = .otaZip
		} else if fileName.hasSuffix(".uf2") {
			coreName = String(coreName.dropLast(".uf2".count))
			firmwareType = .uf2
		} else if fileName.hasSuffix(".bin") {
			coreName = String(coreName.dropLast(".bin".count))
			firmwareType = .bin
		} else {
			throw FirmwareFile.FirmwareFileError.unknownFileType
		}

		guard let lastHyphenIndex = coreName.lastIndex(of: "-") else {
			throw FirmwareFile.FirmwareFileError.parseError
		}
		let target = String(coreName[..<lastHyphenIndex])
		let versionId = String(coreName[coreName.index(after: lastHyphenIndex)...])
		guard !target.isEmpty, let version = parsedVersion(versionId) else {
			throw FirmwareFile.FirmwareFileError.parseError
		}

		return ParsedLocalFirmwareFile(
			platformioTarget: target,
			version: version,
			firmwareType: firmwareType
		)
	}

	nonisolated private static func isFirmwareFileOrderedBefore(
		_ lhs: FirmwareFileSnapshot,
		_ rhs: FirmwareFileSnapshot
	) -> Bool {
		if (lhs.versionMajor, lhs.versionMinor, lhs.versionPatch) == (rhs.versionMajor, rhs.versionMinor, rhs.versionPatch) {
			return String(describing: lhs.firmwareType) < String(describing: rhs.firmwareType)
		}
		return (lhs.versionMajor, lhs.versionMinor, lhs.versionPatch) > (rhs.versionMajor, rhs.versionMinor, rhs.versionPatch)
	}

	nonisolated private static func loadLocalFirmwareFileURLs() -> [URL]? {
		let fileManager = FileManager.default
		var isDirectory: ObjCBool = false
		if !fileManager.fileExists(atPath: FirmwareFile.localFirmwareStorageURL.path, isDirectory: &isDirectory) {
			return nil
		}

		do {
			return try fileManager.contentsOfDirectory(at: FirmwareFile.localFirmwareStorageURL, includingPropertiesForKeys: nil)
		} catch {
			Logger.services.error("Error loading firmware files: \(error)")
			return []
		}
	}
}

@MainActor
class FirmwareViewModel: ObservableObject {
	@Published var firmwareFiles: [FirmwareFile] = []
	let hardware: DeviceHardwareEntity
	private var refreshGeneration = RefreshGeneration()
	/// The connected node's LoRa region; non-Latin regions get locale-tagged
	/// remote artifact candidates so the right on-device fonts ship. `.unset`
	/// keeps the previous generic-only behavior.
	let preferredRegion: RegionCodes

	init(forHardware: DeviceHardwareEntity, preferredRegion: RegionCodes = .unset) {
		self.hardware = forHardware
		self.preferredRegion = preferredRegion
		Task {
			refresh()
		}
	}
	
	func refresh() {
		let generation = refreshGeneration.begin()
		let hardwareSnapshot = FirmwareHardwareSnapshot(
			platformioTarget: hardware.platformioTarget,
			architecture: hardware.architecture.flatMap { Architecture(rawValue: $0) }
		)
		let localeTags = preferredRegion.prefersLocalizedFontFirmware ? preferredRegion.firmwareLocaleTagCandidates : []
		var releaseSnapshots = [FirmwareReleaseSnapshot]()
		let context = PersistenceController.shared.container.mainContext
		let descriptor = FetchDescriptor<FirmwareReleaseEntity>()
		do {
			let firmwareReleases = try context.fetch(descriptor)
			for release in firmwareReleases {
				releaseSnapshots.append(try FirmwareReleaseSnapshot(release))
			}
		} catch {
			Logger.services.error("Error fetching firmware releases: \(error)")
		}

		Task {
			let snapshot = await Task.detached(priority: .userInitiated) {
				guard let localFileURLs = Self.loadLocalFirmwareFileURLs() else { return nil as FirmwareCatalogSnapshot? }
				return Self.makeFirmwareCatalogSnapshot(
					releases: releaseSnapshots,
					localFileURLs: localFileURLs,
					hardware: hardwareSnapshot,
					localeTags: localeTags
				)
			}.value

			guard let snapshot else { return }
			guard self.refreshGeneration.isCurrent(generation) else { return }
			for localFileError in snapshot.localFileErrors {
				Logger.services.error("Error parsing local firmware file at \(localFileError.localFileURL.path): \(localFileError.message)")
			}
			self.firmwareFiles = snapshot.files.map { snapshot in
				FirmwareFile(
					localUrl: snapshot.localUrl,
					remoteUrlCandidates: snapshot.remoteUrlCandidates,
					versionId: snapshot.versionId,
					platformioTarget: snapshot.platformioTarget,
					releaseType: snapshot.releaseType,
					status: snapshot.status,
					firmwareType: snapshot.firmwareType,
					architecture: snapshot.architecture,
					releaseNotes: snapshot.releaseNotes,
					versionMajor: snapshot.versionMajor,
					versionMinor: snapshot.versionMinor,
					versionPatch: snapshot.versionPatch
				)
			}
		}
	}

	func mostRecentFirmwareVersion(forReleaseType releaseType: ReleaseType) -> String? {
		let context = PersistenceController.shared.container.mainContext
		let releaseTypeRaw = releaseType.rawValue
		var descriptor = FetchDescriptor<FirmwareReleaseEntity>(
			predicate: #Predicate { $0.releaseType == releaseTypeRaw },
			sortBy: [
				SortDescriptor(\.versionMajor, order: .reverse),
				SortDescriptor(\.versionMinor, order: .reverse),
				SortDescriptor(\.versionPatch, order: .reverse)
			]
		)
		descriptor.fetchLimit = 1
		return try? context.fetch(descriptor).first?.versionId
	}
	
	func firmwareFiles(forVersionId versionId: String) -> [FirmwareFile] {
		return firmwareFiles.filter({ $0.versionId == versionId })
	}
	
	func mostRecentFirmware(forReleaseType releaseType: ReleaseType) -> [FirmwareFile] {
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

	func download(_ file: FirmwareFile) async throws {
		refreshGeneration.beginCatalogMutation()
		do {
			try await file.download()
			refreshGeneration.endCatalogMutation()
			refresh()
		} catch {
			refreshGeneration.endCatalogMutation()
			throw error
		}
	}
	
	func delete(_ filesToDelete: [FirmwareFile]) {
		refreshGeneration.invalidateForCatalogMutation()

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
