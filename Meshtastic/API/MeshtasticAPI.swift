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
import os

// These structs are public becase tehy are used elsewhere in the app to represent
// fields in the Core Data database.
enum ReleaseType: String {
	case stable = "Stable"
	case alpha = "Alpha"
	case nightly = "Nightly"
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
struct FirmwareReleases: Codable {
	let releases: Releases
	let pullRequests: [FirmwareRelease]
}
struct Releases: Codable {
	let stable, alpha: [FirmwareRelease]
}
struct FirmwareRelease: Codable {
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

/// Points at the current nightly build. Nightly artifacts live in one fixed
/// `firmware-nightly` directory that is overwritten each build, so this file is the
/// only way to learn which version is sitting in there right now.
struct NightlyFirmwareIndex: Codable {
	let version: String
	let id: String
	let title: String
	let commit: String?
}

private struct GitHubFirmwareRelease: Decodable {
	let tagName: String
	let name: String?
	let htmlURL: String
	let zipballURL: String
	let body: String?
	let prerelease: Bool
	let draft: Bool

	enum CodingKeys: String, CodingKey {
		case tagName = "tag_name"
		case name
		case htmlURL = "html_url"
		case zipballURL = "zipball_url"
		case body
		case prerelease
		case draft
	}
}

enum FirmwareReleaseCatalog {
	static func decode(_ data: Data) throws -> FirmwareReleases {
		let decoder = JSONDecoder()
		if let meshtasticReleases = try? decoder.decode(FirmwareReleases.self, from: data) {
			return meshtasticReleases
		}

		let githubReleases = try decoder.decode([GitHubFirmwareRelease].self, from: data)
		let publishedReleases = githubReleases.filter { !$0.draft }
		let stable = publishedReleases
			.filter { !$0.prerelease }
			.map { FirmwareRelease(gitHubRelease: $0) }
		let alpha = publishedReleases
			.filter(\.prerelease)
			.map { FirmwareRelease(gitHubRelease: $0) }

		return FirmwareReleases(
			releases: Releases(stable: stable, alpha: alpha),
			pullRequests: []
		)
	}
}

private extension FirmwareRelease {
	init(gitHubRelease: GitHubFirmwareRelease) {
		id = gitHubRelease.tagName
		title = gitHubRelease.name ?? gitHubRelease.tagName
		pageURL = gitHubRelease.htmlURL
		zipURL = gitHubRelease.zipballURL
		releaseNotes = gitHubRelease.body
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
	static let deviceURLEndpoint = URL(string: "https://apiv2.meshtastic.org/resource/deviceHardware")!
	static let imageURLPrefix = URL(string: "https://flasher.meshtastic.org/img/devices/")!
	static let firmwareURLEndpoint = URL(string: "https://apiv2.meshtastic.org/github/firmware/list")!
	static let firmwareGitHubURLEndpoint = URL(string: "https://api.github.com/repos/meshtastic/firmware/releases?per_page=100")!
	static let nightlyIndexEndpoint = URL(string: "https://raw.githubusercontent.com/meshtastic/meshtastic.github.io/master/firmware-nightly/index.json")!

	static let deviceCatalogETagKey = "deviceCatalog"
	static let firmwareListETagKey = "firmwareReleaseList"

	/// Last ETag seen for an endpoint. URLSession already spares us the download when nothing has
	/// changed; this spares us the rest — decoding the payload and re-writing rows that are
	/// already correct. Stored only after the write succeeds, so a run that fails part-way cannot
	/// convince the next one that the store is current.
	static func lastETag(for key: String) -> String? {
		UserDefaults.standard.string(forKey: "api.etag.\(key)")
	}

	static func setLastETag(_ eTag: String?, for key: String) {
		guard let eTag else { return }
		UserDefaults.standard.set(eTag, forKey: "api.etag.\(key)")
	}
	static let nightlyReleaseNotesEndpoint = URL(string: "https://raw.githubusercontent.com/meshtastic/meshtastic.github.io/master/firmware-nightly/release_notes.md")!
	static let eventFirmwareURLEndpoint = URL(string: "https://apiv2.meshtastic.org/resource/eventFirmware")!

	/// How long a completed device image + msh.to link pass stays fresh before another network pass
	/// is allowed. `processImage` issues a remote ETag HEAD per image (~78) up front, so running the
	/// pass on every reconnect is wasteful when nothing changed. `clearDatabase` invalidates the
	/// throttle (see `DeviceImageLinkThrottle`), so restore-after-clear ignores this window.
	static let staleDeviceImageLinkInterval: TimeInterval = 48 * 60 * 60

	// MARK: - Private properties
	private let fileManager = FileManager.default
	private let decoder = JSONDecoder()
	private let container: ModelContainer?
	
	@Published var isLoadingDeviceList: Bool = false
	@Published var isLoadingFirmwareList: Bool = false

	// Device-list loading is reported by two independently-scheduled passes (the local seed and
	// the network image/link pass) that can overlap — init's cascade, connect Step 3, and the
	// Reset Database action all drive them. A plain Bool lets whichever pass finishes first clear
	// the flag out from under one that is still running, so count the passes instead and only
	// lower the flag when the last one exits.
	@MainActor private var deviceListLoadDepth = 0

	@MainActor private func beginDeviceListLoad() {
		deviceListLoadDepth += 1
		isLoadingDeviceList = true
	}

	@MainActor private func endDeviceListLoad() {
		deviceListLoadDepth = max(0, deviceListLoadDepth - 1)
		if deviceListLoadDepth == 0 {
			isLoadingDeviceList = false
		}
	}
	
	// Not private: MeshtasticTests constructs an instance with an in-memory container to
	// assert the bundled seed stays network-free. `shared` remains the only app-side entry.
	// `startupRefresh: false` suppresses the launch refresh cascade below so a test can call a
	// single refresh function in isolation without the detached startup work racing it.
	init(container: ModelContainer?, startupRefresh: Bool = true) {
		self.container = container
		guard container != nil, startupRefresh else { return }
		Task.detached {
			// Load bundled catalog first — instant display, no network needed.
			try? await self.refreshBundledDevicesData()
			try? await self.refreshFirmwareAPIData()
			// Seed event-firmware branding from the bundle so it survives restarts offline.
			await self.refreshBundledEventFirmwareData()
			// Then silently update from the live API in the background.
			Task.detached(priority: .utility) {
				await self.refreshDevicesPreferringAPI()
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
		defer {
			Task { @MainActor in self.isLoadingFirmwareList = false }
		}

		let decodedFirmware: FirmwareReleases
		var firmwareListETag: String?
		do {
			let (apiData, eTag) = try await Self.firmwareURLEndpoint.dataWithETag(timeout: 5.0)
			// Same short-circuit as the catalog: an unchanged list is not worth re-writing.
			if let eTag, eTag == Self.lastETag(for: Self.firmwareListETagKey) {
				let hasReleases = await MainActor.run {
					((try? container.mainContext.fetchCount(FetchDescriptor<FirmwareReleaseEntity>())) ?? 0) > 0
				}
				if hasReleases {
					Logger.services.debug("Firmware list unchanged (ETag match), skipping the upsert")
					UserDefaults.lastFirmwareAPIUpdate = Date()
					return
				}
			}
			firmwareListETag = eTag
			decodedFirmware = try FirmwareReleaseCatalog.decode(apiData)
		} catch {
			Logger.services.warning("Firmware API request failed; falling back to GitHub releases: \(error.localizedDescription, privacy: .public)")
			let githubData = try await Self.firmwareGitHubURLEndpoint.data(timeout: 5.0)
			decodedFirmware = try FirmwareReleaseCatalog.decode(githubData)
		}
		let stableVersions = Set(decodedFirmware.releases.stable.map { $0.id })
		let alphaVersions = Set(decodedFirmware.releases.alpha.map { $0.id })
		let nightlyRelease = await fetchNightlyRelease()

		// All DB work on mainContext so @Query observers see changes
		await MainActor.run {
			let context = container.mainContext

			for stableRelease in decodedFirmware.releases.stable {
				self.processFirmware(release: stableRelease, releaseType: .stable, context: context)
			}

			for alphaRelease in decodedFirmware.releases.alpha {
				self.processFirmware(release: alphaRelease, releaseType: .alpha, context: context)
			}

			if let nightlyRelease {
				self.processFirmware(release: nightlyRelease, releaseType: .nightly, context: context)

				// Only one nightly exists at a time — the host overwrites the directory — so
				// drop yesterday's row. Skipped when the index could not be read, or a failed
				// fetch would empty the tab.
				let nightlyRaw = ReleaseType.nightly.rawValue
				let currentNightly = [nightlyRelease.id]
				let staleNightlyDescriptor = FetchDescriptor<FirmwareReleaseEntity>(
					predicate: #Predicate {
						$0.releaseType == nightlyRaw && !currentNightly.contains($0.versionId)
					}
				)
				if let staleNightlies = try? context.fetch(staleNightlyDescriptor) {
					for staleNightly in staleNightlies {
						context.delete(staleNightly)
					}
				}
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
		Self.setLastETag(firmwareListETag, for: Self.firmwareListETagKey)
	}

	/// Refresh the hardware catalog from the API.
	///
	/// `includeImages` runs the image/link pass afterwards. Callers that only need the
	/// metadata — a new board's name and PlatformIO target — pass false and skip it.
	func refreshDevicesAPIData(includeImages: Bool = true) async throws {
		guard let container else { return }
		// No spinner bookkeeping here: this function raises no loading flag of its own, and the
		// image/link pass it delegates to in PHASE 3 manages the flag around its own lifetime.
		// Clearing it here would lower a flag a concurrent seed still needs raised.
		// PHASE 1: Network only — no bundle fallback (bundle was already loaded at init).
		let (finalData, eTag) = try await Self.deviceURLEndpoint.dataWithETag(timeout: 10.0)
		guard !finalData.isEmpty else { throw MeshtasticAPIError.unableToRetreviveJSON }

		// Unchanged payload: skip the decode and the upsert. Guarded on the store actually holding
		// rows, because a database clear leaves the stored ETag behind and skipping then would
		// leave the catalog empty until the payload next changes.
		if let eTag, eTag == Self.lastETag(for: Self.deviceCatalogETagKey) {
			let hasRows = await MainActor.run {
				let context = container.mainContext
				let devices = (try? context.fetchCount(FetchDescriptor<DeviceHardwareEntity>())) ?? 0
				guard devices > 0 else { return false }
				guard includeImages else { return true }
				return ((try? context.fetchCount(FetchDescriptor<DeviceHardwareImageEntity>())) ?? 0) > 0
			}
			if hasRows {
				Logger.services.debug("Device catalog unchanged (ETag match), skipping the upsert")
				return
			}
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

		// PHASE 3: Images and msh.to links. This is the single image/link pass, driven by the
		// live device list so hardware present only in the API still gets its images. It runs
		// here, after the metadata upsert, so the device rows the images attach to already exist.
		Self.setLastETag(eTag, for: Self.deviceCatalogETagKey)

		guard includeImages else { return }
		await refreshDeviceImagesAndLinks(apiDevices: decodedDevices)
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
	
	/// Read the nightly pointer file. Best effort on purpose: no nightly, or an
	/// unreachable one, must not fail the stable and alpha list refresh.
	private func fetchNightlyRelease() async -> FirmwareRelease? {
		do {
			let data = try await Self.nightlyIndexEndpoint.data(timeout: 5.0)
			let index = try JSONDecoder().decode(NightlyFirmwareIndex.self, from: data)
			let notes = try? await Self.nightlyReleaseNotesEndpoint.data(timeout: 5.0)
			let pageURL = index.commit.map { "https://github.com/meshtastic/firmware/commit/\($0)" }
				?? "https://github.com/meshtastic/firmware/commits/master"
			return FirmwareRelease(
				id: index.id,
				title: index.title,
				pageURL: pageURL,
				zipURL: "",
				releaseNotes: notes.flatMap { String(data: $0, encoding: .utf8) }
			)
		} catch {
			Logger.services.warning("Nightly firmware index unavailable: \(error.localizedDescription, privacy: .public)")
			return nil
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
		guard let container else { return }
		// Skip if the pass was cancelled (connection teardown) — don't even do the bundle fallback.
		if Task.isCancelled { return }
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
	/// Seed the device catalog from the bundled `DeviceHardware.json`.
	///
	/// Local only — decode plus a SwiftData upsert, no network. That is what makes it safe to
	/// await from latency-sensitive paths such as BLE connect Step 3, which has a 30s budget and
	/// restarts the whole connect when it is exceeded. Device images and the msh.to link catalog
	/// are network-backed and live in `refreshDeviceImagesAndLinks()`; keep them out of here.
	func refreshBundledDevicesData() async throws {
		guard let container else { return }
		await beginDeviceListLoad()
		// Clear on every exit, not just the happy path: a failed bundle read, decode, or save
		// would otherwise leave the hardware views pinned in their loading state for good.
		defer { Task { @MainActor in self.endDeviceListLoad() } }
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
	}

	/// Refresh the device catalog, images and msh.to links, preferring the live API.
	///
	/// The API refresh owns the image/link pass and drives it from the live device list; only when
	/// it fails do we fall back to a bundle-only pass, whose `processImage()` resolves images from
	/// the app bundle and whose `importDeviceLinks()` falls back to the bundled `urls.json`.
	///
	/// This is the shape all three network-pass callers need — launch, the Reset Database action,
	/// and BLE connect Step 3b — so it lives here rather than being restated at each call site.
	/// Every one of them must run it detached: both halves hit the network and must never be
	/// awaited inside connect Step 3's 30s budget (issue #2196).
	func refreshDevicesPreferringAPI() async {
		do {
			try await refreshDevicesAPIData()
		} catch {
			// A disconnect cancels the Step 3b task that runs this (closeConnection). URLSession
			// surfaces that cancellation as URLError.cancelled, not CancellationError, but
			// Task.isCancelled is set either way — treat it as teardown and do NOT start a second
			// 78-request bundle pass, which would only amplify work on the way out. Any other error is
			// a genuine API failure, so fall back to the bundle-only pass.
			guard !Task.isCancelled else { return }
			Logger.services.warning(
				"Device API refresh failed; falling back to the bundled image/link pass: \(error.localizedDescription, privacy: .public)"
			)
			await refreshDeviceImagesAndLinks()
		}
	}

	/// Refresh device images and the msh.to link catalog from the bundled catalog alone.
	///
	/// This is the offline path: `processImage` falls back to the app bundle, so it is what puts
	/// device images on screen with no connectivity. When the live API is reachable,
	/// `refreshDevicesAPIData()` runs the pass instead, from the fuller API device list.
	func refreshDeviceImagesAndLinks() async {
		await refreshDeviceImagesAndLinks(apiDevices: nil)
	}

	/// The single image/link refresh pass.
	///
	/// Both halves hit the network, so this must never be awaited from the connect path. On a
	/// captive portal or a zero-rated cellular link the image requests neither succeed nor fail
	/// fast: `URL.eTag()` sets no timeout and inherits `URLSession.shared`'s 60s default, so none
	/// of the 82 image requests resolve inside connect Step 3's 30s budget (issue #2196). Callers
	/// must run this detached.
	///
	/// The work list is the union of the bundled catalog and, when the caller has one, the live
	/// API list. The bundled seed and the API refresh used to run a pass each, so every online
	/// startup fetched every ETag twice. Unioning here keeps it to one pass without dropping
	/// images for hardware that appears in only one of the lists.
	///
	/// Deduplication is on image file name, not (platform, name): the request URL derives from the
	/// file name alone, and `DeviceHardwareImageEntity` is keyed by `fileName` with a single
	/// `device` relationship, so a name shared by several platforms (3 in the current catalog, and
	/// 82 entries collapse to 78 names) can only ever belong to one device row. Previously that was
	/// a fetch per platform racing to claim the row; now it is one fetch attached to the first
	/// device in catalog order.
	private func refreshDeviceImagesAndLinks(apiDevices: [DeviceHardware]?) async {
		guard let container else { return }

		// Bail before claiming a throttle token if the connection already tore down. closeConnection
		// cancels the Step 3b task that runs this pass; returning here leaves the throttle un-armed so
		// the next connect runs a real restore rather than skipping.
		guard !Task.isCancelled else { return }

		// Throttle the network image/link pass to at most once per `staleDeviceImageLinkInterval`
		// (48h). `processImage` issues a remote ETag HEAD per image (~78) before it even consults
		// the cache, and Step 3b fires this on every reconnect, so an un-throttled pass re-hits the
		// network each connect when nothing changed. A database clear (factory/NodeDB reset,
		// foreign-database device switch) invalidates the throttle in `clearDatabase`, so the
		// restore-after-clear pass still runs regardless of this window.
		//
		// The token pins this pass to the clear-generation it started under. This runs detached, so
		// a clear can land while it is still downloading; completing against a stale token must not
		// re-arm the throttle or the just-wiped rows stay wiped for the rest of the window.
		guard let throttleToken = DeviceImageLinkThrottle.beginIfStale(
			interval: Self.staleDeviceImageLinkInterval
		) else {
			Logger.services.debug("Device images/links refreshed within the last 48h; skipping network pass.")
			return
		}

		// The hardware views key their placeholder on this flag: DeviceHardwareImage,
		// SupportedHardwareBadge and NodeInfoItem all show a spinner while it is true and the
		// "UNSET" artwork once it is false. Before the seed/network split it stayed raised across
		// this pass; raising it here keeps that, rather than showing UNSET for the whole download.
		await beginDeviceListLoad()
		defer { Task { @MainActor in self.endDeviceListLoad() } }

		let bundledDevices: [DeviceHardware]
		if let bundledData = try? Self.bundledDeviceHardwareData(),
		   let decoded = try? decoder.decode([DeviceHardware].self, from: bundledData) {
			bundledDevices = decoded
		} else {
			Logger.services.warning("Unable to load bundled device hardware for image refresh")
			bundledDevices = []
		}

		var work: [(imageName: String, platform: String)] = []
		var seen = Set<String>()
		for device in bundledDevices + (apiDevices ?? []) {
			for imageName in device.images ?? [] where seen.insert(imageName).inserted {
				work.append((imageName: imageName, platform: device.platformioTarget))
			}
		}

		await withTaskGroup(of: Void.self) { group in
			for item in work {
				if Task.isCancelled { break }   // teardown mid-pass: stop queueing image fetches
				group.addTask {
					await self.processImage(imageName: item.imageName, platform: item.platform)
				}
			}
		}
		// If the connection tore down mid-pass, skip the orphan cleanup, link import and throttle
		// completion. Leaving the throttle un-armed makes the next connect run a real restore rather
		// than skipping a catalog that never finished downloading.
		guard !Task.isCancelled else {
			Logger.services.debug("Device image/link pass cancelled (connection teardown); throttle left un-armed.")
			return
		}
		await MainActor.run {
			let context = container.mainContext
			Self.deleteOrphanedImages(context: context)
			try? context.save()
		}
		await importDeviceLinks()
		// Mark the pass complete so the next reconnect within the window skips the network. Recorded
		// even when the pass reached no network: processImage falls back to the app bundle, so it
		// still restored artwork/links locally — the window only bounds how often we re-check for
		// updates. Dropped if a clear superseded this pass, so the restore still gets its turn.
		DeviceImageLinkThrottle.complete(token: throttleToken)
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
struct EventFirmwareFile {
	let version: Int?
	let editions: [EventFirmwarePayload]
}

struct EventFirmwarePayload: Decodable {
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

	private enum CodingKeys: String, CodingKey {
		case edition
		case displayName
		case welcomeMessage
		case tag
		case eventStart
		case eventEnd
		case timeZone
		case location
		case iconUrl
		case accentColor
		case domain
		case links
		case theme
		case firmware
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		edition = try container.decode(String.self, forKey: .edition)
		displayName = try? container.decodeIfPresent(String.self, forKey: .displayName)
		welcomeMessage = try? container.decodeIfPresent(String.self, forKey: .welcomeMessage)
		tag = try? container.decodeIfPresent(String.self, forKey: .tag)
		eventStart = try? container.decodeIfPresent(String.self, forKey: .eventStart)
		eventEnd = try? container.decodeIfPresent(String.self, forKey: .eventEnd)
		timeZone = try? container.decodeIfPresent(String.self, forKey: .timeZone)
		location = try? container.decodeIfPresent(String.self, forKey: .location)
		iconUrl = try? container.decodeIfPresent(String.self, forKey: .iconUrl)
		accentColor = try? container.decodeIfPresent(String.self, forKey: .accentColor)
		domain = try? container.decodeIfPresent(String.self, forKey: .domain)
		links = (try? container.decodeIfPresent(
			[LossyEventFirmwareLink].self,
			forKey: .links
		))?.compactMap(\.value)
		theme = try? container.decodeIfPresent(EventFirmwareThemePayload.self, forKey: .theme)
		firmware = try? container.decodeIfPresent(EventFirmwareBuildPayload.self, forKey: .firmware)
	}
}

struct EventFirmwareLinkPayload: Decodable {
	let label: String
	let url: String
}

private struct LossyEventFirmwareLink: Decodable {
	let value: EventFirmwareLinkPayload?

	init(from decoder: Decoder) throws {
		value = try? EventFirmwareLinkPayload(from: decoder)
	}
}

struct EventFirmwareThemePayload: Decodable {
	let name: String?
	let tagline: String?
	let colors: EventFirmwareColorsPayload?
	let palette: [String]?
	let fonts: EventFirmwareFontsPayload?
}

struct EventFirmwareColorsPayload: Decodable {
	let primary: String?
	let secondary: String?
	let accent: String?
}

struct EventFirmwareFontsPayload: Decodable {
	let heading: String?
	let body: String?
}

struct EventFirmwareBuildPayload: Decodable {
	let slug: String?
	let version: String?
	let id: String?
	let title: String?
	let releaseNotes: String?
}

enum EventFirmwareManifestDecoder {

	/// Decode each edition independently so one missing field or malformed nested value cannot
	/// suppress otherwise valid event branding.
	static func decode(_ data: Data) throws -> EventFirmwareFile {
		guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
			  let rawEditions = root["editions"] as? [Any] else {
			throw DecodingError.dataCorrupted(.init(
				codingPath: [],
				debugDescription: "Event firmware manifest is missing its editions array"
			))
		}

		let decoder = JSONDecoder()
		let editions = rawEditions.compactMap { rawValue -> EventFirmwarePayload? in
			guard let rawEdition = rawValue as? [String: Any],
				  let edition = rawEdition["edition"] as? String,
				  !edition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
				  JSONSerialization.isValidJSONObject(rawEdition),
				  let entryData = try? JSONSerialization.data(withJSONObject: rawEdition) else {
				return nil
			}
			return try? decoder.decode(EventFirmwarePayload.self, from: entryData)
		}
		return EventFirmwareFile(version: root["version"] as? Int, editions: editions)
	}
}

enum EventFirmwareRefreshPolicy {

	static let minimumAttemptInterval: TimeInterval = 6 * 60 * 60

	static func shouldRefresh(lastAttempt: Date, now: Date = Date()) -> Bool {
		let elapsed = now.timeIntervalSince(lastAttempt)
		return elapsed < 0 || elapsed >= minimumAttemptInterval
	}
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
			  let decoded = try? EventFirmwareManifestDecoder.decode(data) else {
			Logger.services.warning("Unable to load bundled event_firmware.json")
			return
		}
		// The bundle is a floor. Existing rows came from a newer live response and must not be
		// downgraded on relaunch while the refresh throttle is active.
		await importEventEditions(decoded.editions, overwriteExisting: false)
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
		let attemptDate = Date()
		guard EventFirmwareRefreshPolicy.shouldRefresh(
			lastAttempt: UserDefaults.lastEventFirmwareAPIAttempt,
			now: attemptDate
		) else {
			return
		}
		UserDefaults.lastEventFirmwareAPIAttempt = attemptDate

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

		guard let decoded = try? EventFirmwareManifestDecoder.decode(data),
			  !decoded.editions.isEmpty else {
			// A decode failure or an editions-less payload must not clobber the cache.
			Logger.services.warning("Event firmware API returned no usable editions — keeping cache")
			return
		}

		// Treat the remote display manifest as additive. A malformed or partial response must not
		// delete previously cached editions or erase complete fields.
		await importEventEditions(decoded.editions, overwriteExisting: true)
		UserDefaults.lastEventFirmwareAPIUpdate = Date()
		Logger.services.info("Refreshed event firmware from API (\(decoded.editions.count, privacy: .public) editions)")
	}

	/// Merge display-only event metadata into the cache.
	///
	/// Bundled data creates missing rows but never overwrites a live row. Live data updates only
	/// fields it actually supplied, so one malformed/partial edition cannot destroy a complete
	/// offline cache. Executable artifact URLs and hashes are deliberately not persisted here:
	/// those require the separate signed per-target OTA contract.
	func importEventEditions(_ editions: [EventFirmwarePayload], overwriteExisting: Bool) async {
		guard let container else { return }
		await MainActor.run {
			let context = container.mainContext

			for payload in editions {
				let key = payload.edition
				var descriptor = FetchDescriptor<EventFirmwareEntity>(
					predicate: #Predicate { $0.edition == key }
				)
				descriptor.fetchLimit = 1

				let entity: EventFirmwareEntity
				if let existing = try? context.fetch(descriptor).first {
					guard overwriteExisting else { continue }
					entity = existing
				} else {
					entity = EventFirmwareEntity(edition: key)
					context.insert(entity)
				}

				if let value = payload.displayName { entity.displayName = value }
				if let value = payload.welcomeMessage { entity.welcomeMessage = value }
				if let value = payload.tag { entity.tag = value }
				if let value = payload.eventStart { entity.eventStart = value }
				if let value = payload.eventEnd { entity.eventEnd = value }
				if let value = payload.timeZone { entity.timeZone = value }
				if let value = payload.location { entity.location = value }
				if let value = EventFirmwareURLPolicy.httpsURL(from: payload.iconUrl)?.absoluteString {
					entity.iconUrl = value
				}
				if let value = payload.accentColor,
				   EventFirmwareEntity.color(fromHex: value) != nil {
					entity.accentColor = value
				}
				if let value = payload.domain { entity.domain = value }
				if let links = payload.links {
					let safeLinks = links.map {
						EventFirmwareEntity.Link(label: $0.label, url: $0.url)
					}.filter {
						EventFirmwareURLPolicy.httpsURL(from: $0.url) != nil
					}
					if !safeLinks.isEmpty {
						entity.setLinks(safeLinks)
					}
				}
				if let value = payload.theme?.name { entity.themeName = value }
				if let value = payload.theme?.tagline { entity.themeTagline = value }
				if let value = payload.theme?.colors?.primary,
				   EventFirmwareEntity.color(fromHex: value) != nil {
					entity.themePrimaryColor = value
				}
				if let value = payload.theme?.colors?.secondary,
				   EventFirmwareEntity.color(fromHex: value) != nil {
					entity.themeSecondaryColor = value
				}
				if let value = payload.theme?.colors?.accent,
				   EventFirmwareEntity.color(fromHex: value) != nil {
					entity.themeAccentColor = value
				}
				if let palette = payload.theme?.palette {
					let validPalette = palette.filter {
						EventFirmwareEntity.color(fromHex: $0) != nil
					}
					if !validPalette.isEmpty {
						entity.themePalette = validPalette
					}
				}
				if let value = payload.theme?.fonts?.heading { entity.themeFontHeading = value }
				if let value = payload.theme?.fonts?.body { entity.themeFontBody = value }
				if let value = payload.firmware?.slug { entity.firmwareSlug = value }
				if let value = payload.firmware?.version { entity.firmwareVersion = value }
				if let value = payload.firmware?.id { entity.firmwareId = value }
				if let value = payload.firmware?.title { entity.firmwareTitle = value }
				if let value = payload.firmware?.releaseNotes { entity.firmwareReleaseNotes = value }
			}

			try? context.save()
		}
	}
}
