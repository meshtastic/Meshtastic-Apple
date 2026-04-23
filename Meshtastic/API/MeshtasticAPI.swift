//
//  MeshtasticAPI.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/4/25.
//

import Foundation
import OSLog
import SwiftUI
import SwiftData

// These structs are public becase tehy are used elsewhere in the app to represent
// fields in the Core Data database.
enum ReleaseType: String {
	case stable = "Stable"
	case alpha = "Alpha"
	case unlisted = "Unlisted"
}

enum Architecture: String, Codable, Identifiable {
	case esp32 = "esp32"
	case esp32C3 = "esp32-c3"
	case esp32S3 = "esp32-s3"
	case nrf52840 = "nrf52840"
	case rp2040 = "rp2040"
	case esp32C6 = "esp32-c6"

	var id: String { rawValue }
}

// These structs are private because they are only used for decoding API responses.
// The rest of the app should be using Core Data entities.
private struct DeviceHardware: Codable {
	let hwModel: Int
	let hwModelSlug: String
	let platformioTarget: String
	let architecture: Architecture
	let activelySupported: Bool
	let displayName: String
	let supportLevel: Int?
	let tags: [String]?
	let images: [String]?
	let requiresDfu: Bool?
	let hasInkHud: Bool?
	let partitionScheme: String?
	let hasMui: Bool?
}

/// Firmware Release Lists
private struct FirmwareReleases: Codable {
	let releases: Releases
	let pullRequests: [FirmwareRelease]
}
private struct Releases: Codable {
	let stable, alpha: [FirmwareRelease]
}
private struct FirmwareRelease: Codable {
	let id, title: String
	let pageURL: String
	let zipURL: String
	let releaseNotes: String?

	enum CodingKeys: String, CodingKey {
		case id, title
		case pageURL = "page_url"
		case zipURL = "zip_url"
		case releaseNotes = "release_notes"
	}
}

extension MeshtasticAPI {
	enum MeshtasticAPIError: Error, LocalizedError {
		case timedOut(TimeInterval)
		case unableToRetreviveJSON
		case unableToFindOrCreateEntity
		case unknownArchitecture
		case unknownPlatformIOTarget
		var errorDescription: String? {
			switch self {
			case .timedOut(let seconds):
				return "The operation timed out after \(seconds) seconds."
			case .unableToRetreviveJSON:
				return "Unable to retreive device hardware information."
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

class MeshtasticAPI: ObservableObject, @unchecked Sendable {
	// Singleton Access
	static let shared = {
		MeshtasticAPI(container: PersistenceController.shared.container)
	}()
	
	// MARK: - Constants
	static let deviceURLEndpoint = URL(string: "https://api.meshtastic.org/resource/deviceHardware")!
	static let imageURLPrefix = URL(string: "https://flasher.meshtastic.org/img/devices/")!
	static let firmwareURLEndpoint = URL(string: "https://api.meshtastic.org/github/firmware/list")!
	
	// MARK: - Private properties
	private let fileManager = FileManager.default
	private let decoder = JSONDecoder()
	private let container: ModelContainer
	
	@Published var isLoadingDeviceList: Bool = false
	@Published var isLoadingFirmwareList: Bool = false
	
	private init(container: ModelContainer) {
		self.container = container
		Task.detached {
			try? await self.refreshDevicesAPIData()
			try? await self.refreshFirmwareAPIData()
		}
	}
	
	// MARK: - Main Logic
	
	func refreshFirmwareAPIData() async throws {
		await MainActor.run {
			self.isLoadingFirmwareList = true
		}
		
		let apiData = try await Self.firmwareURLEndpoint.data(timeout: 5.0)
		
		let decodedFirmware = try decoder.decode(FirmwareReleases.self, from: apiData)

		let stableVersions = Set(decodedFirmware.releases.stable.map { $0.id })
		let alphaVersions = Set(decodedFirmware.releases.alpha.map { $0.id })

		// All DB work on mainContext so @Query observers see changes
		await MainActor.run {
			let context = container.mainContext

			for stableRelease in decodedFirmware.releases.stable {
				self.processFirmware(release: stableRelease, releaseType: .stable, context: context)
			}

			for alphaRelease in decodedFirmware.releases.alpha {
				self.processFirmware(release: alphaRelease, releaseType: .alpha, context: context)
			}

			// Anything that's left in stableVersions and alphaVersions is no longer present in the API and should be deleted.
			let stableArray = Array(stableVersions)
			let alphaArray = Array(alphaVersions)
			let stableRaw = ReleaseType.stable.rawValue
			let alphaRaw = ReleaseType.alpha.rawValue
			let deleteDescriptor = FetchDescriptor<FirmwareReleaseEntity>(
				predicate: #Predicate {
					($0.releaseType == stableRaw && !stableArray.contains($0.versionId))
					|| ($0.releaseType == alphaRaw && !alphaArray.contains($0.versionId))
				}
			)
			if let objectsToDelete = try? context.fetch(deleteDescriptor) {
				for object in objectsToDelete {
					Logger.services.info("Deleting orphaned firmware release: \(object.versionId, privacy: .public)")
					context.delete(object)
				}
			}

			try? context.save()
		}
		
		// Save the last update date for the firmware
		UserDefaults.lastFirmwareAPIUpdate = Date()
		
		await MainActor.run {
			self.isLoadingFirmwareList = false
		}

	}
	
	func refreshDevicesAPIData() async throws {
		await MainActor.run {
			self.isLoadingDeviceList = true
		}

		// PHASE 1: Network (Async) - Get the JSON first
		var apiData: Data?
		do {
			apiData = try await Self.deviceURLEndpoint.data(timeout: 5.0)
		} catch {
			Logger.services.error("Unable to fetch device hardware from network: \(error.localizedDescription, privacy: .public)")
		}
		
		// Fallback to local bundle
		if apiData == nil {
			if let bundledJsonURL = Bundle.main.url(forResource: "DeviceHardware.json", withExtension: nil) {
				apiData = try? Data(contentsOf: bundledJsonURL)
			}
		}
		
		guard let finalData = apiData else {
			throw MeshtasticAPIError.unableToRetreviveJSON
		}
		
		// Decode Swift Structs (Safe to do off the DB thread)
		let decodedDevices = try decoder.decode([DeviceHardware].self, from: finalData)

		// PHASE 2: Database on mainContext so @Query observers see changes
		try await MainActor.run {
			let context = container.mainContext

			// 1. Update Devices and Tags
			for device in decodedDevices {
				let target = device.platformioTarget
				var descriptor = FetchDescriptor<DeviceHardwareEntity>(
					predicate: #Predicate { $0.platformioTarget == target }
				)
				descriptor.fetchLimit = 1

				let existing = try? context.fetch(descriptor).first
				let deviceEntity: DeviceHardwareEntity
				if let existing {
					deviceEntity = existing
				} else {
					deviceEntity = DeviceHardwareEntity()
					context.insert(deviceEntity)
				}

				// Update Properties
				deviceEntity.hwModel = Int64(device.hwModel)
				deviceEntity.hwModelSlug = device.hwModelSlug
				deviceEntity.platformioTarget = device.platformioTarget
				deviceEntity.architecture = device.architecture.rawValue
				deviceEntity.activelySupported = device.activelySupported
				deviceEntity.displayName = device.displayName

				// Handle Tags
				var tags = [DeviceHardwareTagEntity]()
				if let tagList = device.tags {
					for tagString in tagList {
						if let tagEntity = try? Self.findOrCreateTag(tag: tagString, context: context) {
							tags.append(tagEntity)
						}
					}
				}
				deviceEntity.tags = tags
			}

			// 2. Cleanup Orphans
			Self.deleteOrphanedTags(context: context)

			// 3. Save Device Metadata
			try context.save()
		}

		// PHASE 3: Images (Async Mixed)
		// Now that the devices exist in DB, we process images one by one.
		// We loop through the *Decoded Structs* (not DB objects) to get URLs.
		await withTaskGroup(of: Void.self) { group in
			for device in decodedDevices {
				group.addTask {
					guard let imagesList = device.images else { return }
					for imageName in imagesList {
						await self.processImage(imageName: imageName, platform: device.platformioTarget)
					}
				}
			}
		}

		// Final cleanup of images on mainContext
		await MainActor.run {
			let context = container.mainContext
			Self.deleteOrphanedImages(context: context)
			try? context.save()
		}
		
		await MainActor.run {
			self.isLoadingDeviceList = false
		}

	}
	
	private func processFirmware(release: FirmwareRelease, releaseType: ReleaseType, context: ModelContext) {
		let releaseId = release.id
		var descriptor = FetchDescriptor<FirmwareReleaseEntity>(
			predicate: #Predicate { $0.versionId == releaseId }
		)
		descriptor.fetchLimit = 1

		let existingRelease: FirmwareReleaseEntity
		if let found = try? context.fetch(descriptor).first {
			existingRelease = found
		} else {
			existingRelease = FirmwareReleaseEntity()
			context.insert(existingRelease)
		}
		existingRelease.versionId = release.id
		existingRelease.title = release.title
		existingRelease.releaseNotes = release.releaseNotes
		existingRelease.pageUrl = release.pageURL
		existingRelease.releaseType = releaseType.rawValue

		let cleanString = release.id.hasPrefix("v") ? release.id.dropFirst() : Substring(release.id)
		let parts = cleanString.split(separator: ".")
		if parts.count >= 3 {
			existingRelease.versionMajor = Int32(parts[0]) ?? 0
			existingRelease.versionMinor = Int32(parts[1]) ?? 0
			existingRelease.versionPatch = Int32(parts[2]) ?? 0
		}

		Logger.services.info("Saving firmware release \(release.id, privacy: .public) in database.")
	}
	
	/// Handles the logic of checking ETag -> Checking DB -> Downloading -> Bundle Fallback -> Saving
	private func processImage(imageName: String, platform: String ) async {
		let url = Self.imageURLPrefix.appendingPathComponent(imageName)

		// 1. Network: Try to get ETag (Optional - might fail if offline or timeout)
		let remoteETag = try? await url.eTag()

		// 2. DB: Check if we already have this version or a usable cached version
		let isUpToDate: Bool = await MainActor.run {
			let context = container.mainContext
			var imageDescriptor = FetchDescriptor<DeviceHardwareImageEntity>(
				predicate: #Predicate { $0.fileName == imageName }
			)
			imageDescriptor.fetchLimit = 1

			if let existing = try? context.fetch(imageDescriptor).first,
			   let data = existing.svgData, !data.isEmpty {
				if let rTag = remoteETag {
					return existing.eTag == rTag
				}
				return true
			}
			return false
		}

		if isUpToDate {
			Logger.services.debug("Image \(imageName) is up to date (or cached offline).")
			return
		}

		// 3. Acquire Data (Network Primary -> Bundle Secondary)
		var dataToSave: Data?
		var eTagToSave: String?

		// A: Attempt Network Download (only if we successfully got an ETag previously)
		if let rTag = remoteETag {
			if let networkData = try? await url.data(timeout: 5.0) {
				dataToSave = networkData
				eTagToSave = rTag
			}
		}

		// B: Fallback to Bundle if Network failed or returned no data
		if dataToSave == nil {
			Logger.services.debug("Network unavailable or failed for \(imageName). Checking local bundle.")

			// Look in the 'images' subdirectory
			if let bundleURL = Bundle.main.url(forResource: imageName, withExtension: nil, subdirectory: "images"),
			   let bundleData = try? Data(contentsOf: bundleURL) {

				dataToSave = bundleData
				// We use "bundled" as a placeholder ETag.
				// Next time the app runs with internet, "bundled" != "real_etag", forcing an update.
				eTagToSave = "bundled"
			}
		}

		// 4. DB: Save Image and Link to Device on mainContext
		guard let finalData = dataToSave, let finalETag = eTagToSave else {
			Logger.services.error("Could not find image \(imageName) in Network or Bundle.")
			return
		}

		await MainActor.run {
			let context = container.mainContext

			// Find the Device
			var deviceDescriptor = FetchDescriptor<DeviceHardwareEntity>(
				predicate: #Predicate { $0.platformioTarget == platform }
			)
			deviceDescriptor.fetchLimit = 1
			guard let deviceEntity = try? context.fetch(deviceDescriptor).first else { return }

			// Find or Create Image Entity
			var imageDescriptor = FetchDescriptor<DeviceHardwareImageEntity>(
				predicate: #Predicate { $0.fileName == imageName }
			)
			imageDescriptor.fetchLimit = 1

			let existingImg = try? context.fetch(imageDescriptor).first
			let imageEntity: DeviceHardwareImageEntity
			if let existingImg {
				imageEntity = existingImg
			} else {
				imageEntity = DeviceHardwareImageEntity()
				context.insert(imageEntity)
			}

			imageEntity.fileName = imageName
			imageEntity.eTag = finalETag
			imageEntity.svgData = finalData

			// Create Relationship
			imageEntity.device = deviceEntity
			if !deviceEntity.images.contains(where: { $0.fileName == imageName }) {
				deviceEntity.images.append(imageEntity)
			}

			try? context.save()
			Logger.services.info("Saving \(imageName) in database. eTag=\(finalETag)")
		}
	}

	// MARK: - Helpers
	
	private static func findOrCreateTag(tag: String, context: ModelContext) throws -> DeviceHardwareTagEntity {
		var descriptor = FetchDescriptor<DeviceHardwareTagEntity>(
			predicate: #Predicate { $0.tag == tag }
		)
		descriptor.fetchLimit = 1
		
		if let existingTag = try context.fetch(descriptor).first {
			return existingTag
		}
		
		let newTag = DeviceHardwareTagEntity()
		newTag.tag = tag
		context.insert(newTag)
		return newTag
	}
	
	private static func deleteOrphanedTags(context: ModelContext) {
		let descriptor = FetchDescriptor<DeviceHardwareTagEntity>()
		if let tags = try? context.fetch(descriptor) {
			for tag in tags where tag.devices.isEmpty {
				context.delete(tag)
			}
		}
	}
	
	private static func deleteOrphanedImages(context: ModelContext) {
		let descriptor = FetchDescriptor<DeviceHardwareImageEntity>(
			predicate: #Predicate { $0.device == nil }
		)
		if let images = try? context.fetch(descriptor) {
			images.forEach { context.delete($0) }
		}
	}
}
