//
//  MeshtasticAPI.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/4/25.
//

import Foundation
import OSLog
import SwiftUI
import CoreData

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
	let releaseNotes: String

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
	private let container: NSPersistentContainer
	
	@Published var isLoadingDeviceList: Bool = false
	@Published var isLoadingFirmwareList: Bool = false
	
	private init(container: NSPersistentContainer) {
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
		
		await withTaskGroup(of: Void.self) { group in
			
			for stableRelease in decodedFirmware.releases.stable {
				group.addTask {
					await self.processFirmware(release: stableRelease, releaseType: .stable)
				}
			}
			
			for alphaRelease in decodedFirmware.releases.alpha {
				group.addTask {
					await self.processFirmware(release: alphaRelease, releaseType: .alpha)
				}
			}
		}
		
		// Anything that's left in stableVersions and alphaVersions is no longer present in the API and should be deleted.
		let context = container.newBackgroundContext()
		context.performAndWait {
			let deleteRequest = FirmwareReleaseEntity.fetchRequest()
			deleteRequest.predicate = Self.firmwareCompoundPredicate(stableVersions: stableVersions, alphaVersions: alphaVersions)
			if let objectsToDelete = try? context.fetch(deleteRequest) {
				for object in objectsToDelete {
					Logger.services.info("Deleting orphaned firmware release: \(object.versionId ?? "unknown")")
					context.delete(object)
				}
			}
		}
		
		// Save the deletions if any
		if context.hasChanges {
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

		// PHASE 2: Database (Sync) - Update Devices & Tags
		let context = container.newBackgroundContext()
		context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
		
		// We will perform the bulk update and return a simple list of images we need to check next.
		// We DO NOT do network calls for images inside this block.
		try await context.perform {
			
			// 1. Update Devices and Tags
			for device in decodedDevices {
				let fetchRequest = DeviceHardwareEntity.fetchRequest()
				fetchRequest.predicate = NSPredicate(format: "platformioTarget == %@", device.platformioTarget)
				fetchRequest.fetchLimit = 1
				
				let existing = try? context.fetch(fetchRequest).first
				let deviceEntity = existing ?? DeviceHardwareEntity(context: context)
				
				// Update Properties
				deviceEntity.hwModel = Int64(device.hwModel)
				deviceEntity.hwModelSlug = device.hwModelSlug
				deviceEntity.platformioTarget = device.platformioTarget
				deviceEntity.architecture = device.architecture.rawValue
				deviceEntity.activelySupported = device.activelySupported
				deviceEntity.displayName = device.displayName
				
				// Handle Tags (Helper function is now synchronous)
				var tags = Set<DeviceHardwareTagEntity>()
				if let tagList = device.tags {
					for tagString in tagList {
						// Safe because findOrCreateTag is synchronous and uses `context`
						if let tagEntity = try? Self.findOrCreateTag(tag: tagString, context: context) {
							tags.insert(tagEntity)
						}
					}
				}
				deviceEntity.tags = tags as NSSet
			}
			
			// 2. Cleanup Orphans
			Self.deleteOrphanedTags(context: context)
			
			// 3. Save Device Metadata
			if context.hasChanges {
				try context.save()
			}
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
		
		// Final cleanup of images (Sync)
		try await context.perform {
			Self.deleteOrphanedImages(context: context)
			if context.hasChanges { try context.save() }
		}
		
		await MainActor.run {
			self.isLoadingDeviceList = false
		}

	}
	
	private func processFirmware(release: FirmwareRelease, releaseType: ReleaseType) async {
		let context = container.newBackgroundContext()

		await context.perform {
			let fetchRequest = FirmwareReleaseEntity.fetchRequest()
			fetchRequest.predicate = NSPredicate(format: "versionId == %@", release.id)
			fetchRequest.fetchLimit = 1
			
			let existingRelease = (try? context.fetch(fetchRequest).first) ?? FirmwareReleaseEntity(context: context)
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
			
			try? context.save()
			Logger.services.info("Saving firmware release \(release.id) in database.")
		}
	}
	
	/// Handles the logic of checking ETag -> Checking DB -> Downloading -> Bundle Fallback -> Saving
	private func processImage(imageName: String, platform: String ) async {
		let url = Self.imageURLPrefix.appendingPathComponent(imageName)
		
		// 1. Network: Try to get ETag (Optional - might fail if offline or timeout)
		let remoteETag = try? await url.eTag()
		
		let context = container.newBackgroundContext()
		context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

		// 2. DB: Check if we already have this version or a usable cached version
		let dbStatus: (isUpToDate: Bool, hasData: Bool) = await context.perform {
			let request = DeviceHardwareImageEntity.fetchRequest()
			request.predicate = NSPredicate(format: "fileName == %@", imageName)
			request.fetchLimit = 1
			
			if let existing = try? context.fetch(request).first,
			   let data = existing.svgData, !data.isEmpty {
				
				// A: If we have a remote tag, does it match?
				if let rTag = remoteETag {
					return (existing.eTag == rTag, true)
				}
				
				// B: We are offline (no remote ETag), but we have data. Keep it.
				return (true, true)
			}
			
			// No data in DB
			return (false, false)
		}
		
		if dbStatus.isUpToDate {
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
		
		// 4. DB: Save Image and Link to Device
		guard let finalData = dataToSave, let finalETag = eTagToSave else {
			Logger.services.error("Could not find image \(imageName) in Network or Bundle.")
			return
		}
		
		await context.perform {
			// Find the Device (we must fetch it in THIS context)
			let deviceReq = DeviceHardwareEntity.fetchRequest()
			deviceReq.predicate = NSPredicate(format: "platformioTarget == %@", platform)
			
			guard let deviceEntity = try? context.fetch(deviceReq).first else { return }
			
			// Find or Create Image Entity
			let imageReq = DeviceHardwareImageEntity.fetchRequest()
			imageReq.predicate = NSPredicate(format: "fileName == %@", imageName)
			
			let existingImg = try? context.fetch(imageReq).first
			let imageEntity = existingImg ?? DeviceHardwareImageEntity(context: context)
			
			imageEntity.fileName = imageName
			imageEntity.eTag = finalETag
			imageEntity.svgData = finalData
			
			// Create Relationship
			deviceEntity.addToImages(imageEntity)
						
			try? context.save()
			Logger.services.info("Saving \(imageName) in database. eTag=\(finalETag)")
		}
	}

	// MARK: - Helpers
	
	// Removed @MainActor - this must run on the background context passed in
	private static func findOrCreateTag(tag: String, context: NSManagedObjectContext) throws -> DeviceHardwareTagEntity {
		let fetchRequest = DeviceHardwareTagEntity.fetchRequest()
		fetchRequest.predicate = NSPredicate(format: "tag == %@", tag)
		fetchRequest.fetchLimit = 1
		
		if let existingTag = try context.fetch(fetchRequest).first {
			return existingTag
		}
		
		let newTag = DeviceHardwareTagEntity(context: context)
		newTag.tag = tag
		return newTag
	}
	
	private static func deleteOrphanedTags(context: NSManagedObjectContext) {
		let req = DeviceHardwareTagEntity.fetchRequest()
		req.predicate = NSPredicate(format: "devices.@count == 0")
		if let tags = try? context.fetch(req) {
			tags.forEach { context.delete($0) }
		}
	}
	
	private static func deleteOrphanedImages(context: NSManagedObjectContext) {
		let req = DeviceHardwareImageEntity.fetchRequest()
		req.predicate = NSPredicate(format: "device == nil")
		if let images = try? context.fetch(req) {
			images.forEach { context.delete($0) }
		}
	}
	
	// Helper to build compound predicate for firmware deletion (selects orphans)
	static func firmwareCompoundPredicate(stableVersions: Set<String>, alphaVersions: Set<String>) -> NSPredicate {
		let stablePredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
			NSPredicate(format: "releaseType == %@", ReleaseType.stable.rawValue),
			NSPredicate(format: "NOT (versionId IN %@)", stableVersions)
		])
		let alphaPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
			NSPredicate(format: "releaseType == %@", ReleaseType.alpha.rawValue),
			NSPredicate(format: "NOT (versionId IN %@)", alphaVersions)
		])
		return NSCompoundPredicate(orPredicateWithSubpredicates: [stablePredicate, alphaPredicate])
	}
}

// Image Manifest Decoding
private struct ImageManifest: Codable {
	let files: [String: [String: String]]
	let api_hash: String
}
