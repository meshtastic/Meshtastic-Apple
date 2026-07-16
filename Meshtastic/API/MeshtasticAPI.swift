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
	let architecture: String
	let activelySupported: Bool
	let displayName: String
	let supportLevel: Int?
	let tags: [String]?
	let images: [String]?
	let requiresDfu: Bool?
	let hasInkHud: Bool?
	let partitionScheme: String?
	let hasMui: Bool?
	let key: String?
	let variant: String?
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
	static let shared: MeshtasticAPI = {
		let isTest = NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
		if isTest {
			return MeshtasticAPI(container: nil)
		}
#if DEBUG
		let environment = ProcessInfo.processInfo.environment
		let arguments = ProcessInfo.processInfo.arguments
		if arguments.contains("--meshtastic-perf-seed") || environment["MESHTASTIC_PERF_SEED_NODES"] != nil {
			return MeshtasticAPI(container: nil)
		}
#endif
		return MeshtasticAPI(container: MainActor.assumeIsolated { PersistenceController.shared.container })
	}()
	
	// MARK: - Constants
	static let deviceURLEndpoint = URL(string: "https://api.meshtastic.org/resource/deviceHardware")!
	static let imageURLPrefix = URL(string: "https://flasher.meshtastic.org/img/devices/")!
	static let firmwareURLEndpoint = URL(string: "https://api.meshtastic.org/github/firmware/list")!
	static let eventFirmwareURLEndpoint = URL(string: "https://api.meshtastic.org/resource/eventFirmware")!
	
	// MARK: - Private properties
	private let fileManager = FileManager.default
	private let decoder = JSONDecoder()
	private let container: ModelContainer?
	
	@Published var isLoadingDeviceList: Bool = false
	@Published var isLoadingFirmwareList: Bool = false
	
	private init(container: ModelContainer?) {
		self.container = container
		guard container != nil else { return }
		Task.detached {
			// Load bundled catalog first — instant display, no network needed.
			try? await self.refreshBundledDevicesData()
			try? await self.refreshFirmwareAPIData()
			// Seed event-firmware branding from the bundle so it survives restarts offline.
			await self.refreshBundledEventFirmwareData()
			// Then silently update from the live API in the background.
			Task.detached(priority: .utility) {
				try? await self.refreshDevicesAPIData()
			}
			Task.detached(priority: .utility) {
				await self.refreshEventFirmwareAPIData()
			}
		}
	}
	
	// MARK: - Main Logic
	
	func refreshFirmwareAPIData() async throws {
		// No container in seed/test mode — the DB-backed API is intentionally disabled there
		// (see the singleton init), so skip rather than force-unwrap a nil container.
		guard let container else { return }
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
		guard let container else { return }
		// Silent background update — bundled data already loaded at launch, no spinner needed.
		defer {
			Task { @MainActor in self.isLoadingDeviceList = false }
		}
		// PHASE 1: Network only — no bundle fallback (bundle was already loaded at init).
		let finalData = try await Self.deviceURLEndpoint.data(timeout: 10.0)
		guard !finalData.isEmpty else { throw MeshtasticAPIError.unableToRetreviveJSON }
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
deviceEntity.architecture = device.architecture
				deviceEntity.activelySupported = device.activelySupported
				deviceEntity.displayName = device.displayName
				deviceEntity.supportLevel = device.supportLevel ?? 0
				deviceEntity.requiresDfu = device.requiresDfu ?? false
				deviceEntity.hasInkHud = device.hasInkHud ?? false
				deviceEntity.partitionScheme = device.partitionScheme
				deviceEntity.hasMui = device.hasMui ?? false
				deviceEntity.key = device.key
				deviceEntity.variant = device.variant

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
		// PHASE 4: Import msh.to device links
		await importDeviceLinks()
	}

	// MARK: - Device Links Import

	/// Import the msh.to URL catalog into `DeviceLinkEntity` records.
	private func importDeviceLinks() async {
		guard let container else { return }
		guard let decoded = await loadMshToUrls() else {
			Logger.services.warning("Unable to load msh.to urls (API and bundled fallback both failed)")
			return
		}

		await MainActor.run {
			let context = container.mainContext
			var importedCount = 0
			let importedShortCodes = Set(decoded.routes.map { $0.shortCode })

			for route in decoded.routes {
				let code = route.shortCode
				let isVendor = route.type == .vendor
				let isMarketplace = route.type == .marketplace

				// Marketplace shipping regions: the marketplace key appears as a prefix or
				// suffix of the short code (e.g. "rokland-…" or "…-aliexpress").
				// Non-marketplace links keep an empty `regions` (see DeviceLinkEntity).
				var regions: [String] = []
				if isMarketplace {
					regions = decoded.marketplaces.first(where: { entry in
						let key = entry.key
						return code == key
							|| code.hasPrefix("\(key)-") || code.hasPrefix("\(key)_")
							|| code.hasSuffix("-\(key)") || code.hasSuffix("_\(key)")
					})?.value.regions ?? []
				}

				let redirectUrl = "https://msh.to/\(code)"

				var descriptor = FetchDescriptor<DeviceLinkEntity>(
					predicate: #Predicate { $0.shortCode == code }
				)
				descriptor.fetchLimit = 1

				if let existing = try? context.fetch(descriptor).first {
					existing.originalUrl = redirectUrl
					existing.linkDescription = route.description
					existing.isVendor = isVendor
					existing.isMarketplace = isMarketplace
					existing.targets = route.targets
					existing.regions = regions
				} else {
					context.insert(DeviceLinkEntity(
						shortCode: code,
						originalUrl: redirectUrl,
						linkDescription: route.description,
						isVendor: isVendor,
						isMarketplace: isMarketplace,
						targets: route.targets,
						regions: regions
					))
				}
				importedCount += 1
			}

			// Delete orphaned links no longer present in the catalog
			let allLinksDescriptor = FetchDescriptor<DeviceLinkEntity>()
			if let allLinks = try? context.fetch(allLinksDescriptor) {
				for link in allLinks where !importedShortCodes.contains(link.shortCode) {
					context.delete(link)
				}
			}

			Logger.services.info("Device links import: \(importedCount, privacy: .public) short codes imported")
			try? context.save()
		}
	}

	/// Load the msh.to URL catalog from the API, falling back to the bundled `urls.json`
	/// when the network is unavailable (e.g. first launch offline, or a connect with no
	/// internet). Both share the new `{ Routes, Marketplaces }` shape.
	private func loadMshToUrls() async -> MshToUrlsFile? {
		if let url = URL(string: "https://msh.to/api/urls") {
			var request = URLRequest(url: url)
			request.timeoutInterval = 15
			request.cachePolicy = .reloadRevalidatingCacheData
			if let (data, response) = try? await URLSession.shared.data(for: request),
			   let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
			   let decoded = try? JSONDecoder().decode(MshToUrlsFile.self, from: data) {
				Logger.services.info("Loaded msh.to urls from API (\(decoded.routes.count, privacy: .public) routes)")
				return decoded
			}
			Logger.services.warning("msh.to API fetch failed; falling back to bundled urls.json")
		}

		guard let bundledURL = Bundle.main.url(forResource: "urls", withExtension: "json"),
			  let data = try? Data(contentsOf: bundledURL),
			  let decoded = try? JSONDecoder().decode(MshToUrlsFile.self, from: data) else {
			return nil
		}
		Logger.services.info("Loaded msh.to urls from bundled urls.json (\(decoded.routes.count, privacy: .public) routes)")
		return decoded
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
		guard let container else { return }
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

extension MeshtasticAPI {
	func refreshBundledDevicesData() async throws {
		guard let container else { return }
		await MainActor.run { self.isLoadingDeviceList = true }
		let bundledData = try Self.bundledDeviceHardwareData()
		let decodedDevices = try decoder.decode([DeviceHardware].self, from: bundledData)
		try await MainActor.run {
			let context = container.mainContext
			for device in decodedDevices {
				let target = device.platformioTarget
				var descriptor = FetchDescriptor<DeviceHardwareEntity>(predicate: #Predicate { $0.platformioTarget == target })
				descriptor.fetchLimit = 1
				let existing = try? context.fetch(descriptor).first
				let deviceEntity: DeviceHardwareEntity
				if let existing {
					deviceEntity = existing
				} else {
					deviceEntity = DeviceHardwareEntity()
					context.insert(deviceEntity)
				}
				deviceEntity.hwModel = Int64(device.hwModel)
				deviceEntity.hwModelSlug = device.hwModelSlug
				deviceEntity.platformioTarget = device.platformioTarget
			deviceEntity.architecture = device.architecture
				deviceEntity.activelySupported = device.activelySupported
				deviceEntity.displayName = device.displayName
				deviceEntity.supportLevel = device.supportLevel ?? 0
				deviceEntity.requiresDfu = device.requiresDfu ?? false
				deviceEntity.hasInkHud = device.hasInkHud ?? false
				deviceEntity.partitionScheme = device.partitionScheme
				deviceEntity.hasMui = device.hasMui ?? false
				deviceEntity.key = device.key
				deviceEntity.variant = device.variant
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
			Self.deleteOrphanedTags(context: context)
			try context.save()
		}
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
		await MainActor.run {
			let context = container.mainContext
			Self.deleteOrphanedImages(context: context)
			try? context.save()
		}
		await importDeviceLinks()
		await MainActor.run { self.isLoadingDeviceList = false }
	}

	private static func bundledDeviceHardwareData() throws -> Data {
		guard let bundledJsonURL = Bundle.main.url(forResource: "DeviceHardware.json", withExtension: nil),
			  let bundledData = try? Data(contentsOf: bundledJsonURL) else {
			throw MeshtasticAPIError.unableToRetreviveJSON
		}
		return bundledData
	}
}

// MARK: - Event Firmware Metadata

// Decoding structs for `GET https://api.meshtastic.org/resource/eventFirmware` (version 2).
// Every field except `edition` is independently optional; a new event may ship with only a
// subset populated, so all use `decodeIfPresent`.
private struct EventFirmwareFile: Codable {
	let version: Int?
	let editions: [EventFirmwarePayload]
}

private struct EventFirmwarePayload: Codable {
	let edition: String
	let displayName: String?
	let welcomeMessage: String?
	let tag: String?
	let eventStart: String?
	let eventEnd: String?
	let timeZone: String?
	let location: String?
	let iconUrl: String?
	let accentColor: String?
	let domain: String?
	let links: [EventFirmwareLinkPayload]?
	let theme: EventFirmwareThemePayload?
	let firmware: EventFirmwareBuildPayload?
}

private struct EventFirmwareLinkPayload: Codable {
	let label: String
	let url: String
}

private struct EventFirmwareThemePayload: Codable {
	let name: String?
	let tagline: String?
	let palette: [String]?
	let fonts: EventFirmwareFontsPayload?
}

private struct EventFirmwareFontsPayload: Codable {
	let heading: String?
	let body: String?
}

private struct EventFirmwareBuildPayload: Codable {
	let slug: String?
	let version: String?
	let id: String?
	let title: String?
	let zipUrl: String?
	let releaseNotes: String?
}

extension MeshtasticAPI {

	/// Load the bundled `event_firmware.json` seed into the cache. Runs at launch so event
	/// branding is available instantly and survives restarts offline (the live refresh then
	/// updates it in the background). Never throws — a missing/corrupt bundle is logged and
	/// leaves any existing cache intact.
	func refreshBundledEventFirmwareData() async {
		guard container != nil else { return }
		guard let bundledURL = Bundle.main.url(forResource: "event_firmware", withExtension: "json"),
			  let data = try? Data(contentsOf: bundledURL),
			  let decoded = try? decoder.decode(EventFirmwareFile.self, from: data) else {
			Logger.services.warning("Unable to load bundled event_firmware.json")
			return
		}
		// pruneMissing: false — the bundle is a *floor*, not authoritative. It must never delete
		// an edition that a prior successful live refresh cached but that isn't in the bundled
		// snapshot; that edition would otherwise vanish on every offline relaunch (the exact
		// poor-connectivity-at-the-venue scenario this cache exists for).
		await importEventEditions(decoded.editions, pruneMissing: false)
		Logger.services.info("Loaded bundled event firmware (\(decoded.editions.count, privacy: .public) editions)")
	}

	/// Silently refresh the event-firmware metadata from the live API.
	///
	/// IMPORTANT: this deliberately does NOT use the short `data(timeout:)` deadline the device
	/// and firmware calls use. `api.meshtastic.org` is measured at 20–60s for this resource; a
	/// short deadline cancels every refresh and pins users to the bundled seed (Android hit
	/// exactly this and removed its local deadline). We rely on the default URLSession timeout
	/// plus stale-while-revalidate. An empty or failed response is a **no-op** — it must leave
	/// the existing cache intact, never wipe it.
	func refreshEventFirmwareAPIData() async {
		guard container != nil else { return }

		var request = URLRequest(url: Self.eventFirmwareURLEndpoint)
		// No short local timeout — see the doc comment above. Revalidate against the server
		// cache so a 304 is cheap while still surfacing new events.
		request.cachePolicy = .reloadRevalidatingCacheData

		guard let (data, response) = try? await URLSession.shared.data(for: request),
			  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
			  !data.isEmpty else {
			Logger.services.warning("Event firmware API fetch failed or empty — keeping cached editions")
			return
		}

		guard let decoded = try? decoder.decode(EventFirmwareFile.self, from: data),
			  !decoded.editions.isEmpty else {
			// A decode failure or an editions-less payload must not clobber the cache.
			Logger.services.warning("Event firmware API returned no usable editions — keeping cache")
			return
		}

		// pruneMissing: true — the live API is authoritative, so an edition it no longer lists is
		// genuinely retired and should be removed from the cache.
		await importEventEditions(decoded.editions, pruneMissing: true)
		UserDefaults.lastEventFirmwareAPIUpdate = Date()
		Logger.services.info("Refreshed event firmware from API (\(decoded.editions.count, privacy: .public) editions)")
	}

	/// Upsert the given editions into `EventFirmwareEntity`. When `pruneMissing` is true, also
	/// delete rows not present in `editions` — this is reserved for the **authoritative** live-API
	/// import. The bundled seed passes `pruneMissing: false` so it only upserts/seeds and never
	/// deletes an edition cached from a prior successful API refresh. Called with a non-empty
	/// list from both paths; the caller guarantees an empty/failed fetch never reaches here.
	private func importEventEditions(_ editions: [EventFirmwarePayload], pruneMissing: Bool) async {
		guard let container else { return }
		await MainActor.run {
			let context = container.mainContext
			let importedKeys = Set(editions.map { $0.edition })

			for payload in editions {
				let key = payload.edition
				var descriptor = FetchDescriptor<EventFirmwareEntity>(
					predicate: #Predicate { $0.edition == key }
				)
				descriptor.fetchLimit = 1

				let entity: EventFirmwareEntity
				if let existing = try? context.fetch(descriptor).first {
					entity = existing
				} else {
					entity = EventFirmwareEntity(edition: key)
					context.insert(entity)
				}

				entity.displayName = payload.displayName
				entity.welcomeMessage = payload.welcomeMessage
				entity.tag = payload.tag
				entity.eventStart = payload.eventStart
				entity.eventEnd = payload.eventEnd
				entity.timeZone = payload.timeZone
				entity.location = payload.location
				entity.iconUrl = payload.iconUrl
				entity.accentColor = payload.accentColor
				entity.domain = payload.domain
				entity.setLinks((payload.links ?? []).map {
					EventFirmwareEntity.Link(label: $0.label, url: $0.url)
				})
				entity.themeName = payload.theme?.name
				entity.themeTagline = payload.theme?.tagline
				entity.themePalette = payload.theme?.palette ?? []
				entity.themeFontHeading = payload.theme?.fonts?.heading
				entity.themeFontBody = payload.theme?.fonts?.body
				entity.firmwareSlug = payload.firmware?.slug
				entity.firmwareVersion = payload.firmware?.version
				entity.firmwareId = payload.firmware?.id
				entity.firmwareTitle = payload.firmware?.title
				entity.firmwareZipUrl = payload.firmware?.zipUrl
				entity.firmwareReleaseNotes = payload.firmware?.releaseNotes
			}

			// Delete editions no longer present — only for the authoritative live-API import.
			if pruneMissing {
				let allDescriptor = FetchDescriptor<EventFirmwareEntity>()
				if let all = try? context.fetch(allDescriptor) {
					for row in all where !importedKeys.contains(row.edition) {
						context.delete(row)
					}
				}
			}

			try? context.save()
		}
	}
}
