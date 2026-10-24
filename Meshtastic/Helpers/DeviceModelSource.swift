//
//  DeviceModelSource.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/15/26.
//

import Foundation
import OSLog

/// Which 3D device model, if any, belongs to a hardware catalog entry.
///
/// Models are named after the device's image in the hardware list, so most entries map by
/// swapping the image's extension. A few models were made for a variant whose catalog entry
/// still points at a shared image; those are listed by target.
enum DeviceModelCatalog {

	/// Every model in `Meshtastic/Resources/DeviceModels` and on the web flasher. iPhone, iPad,
	/// Mac and Vision Pro builds bundle these files; the list also gates the download fallback
	/// used when a bundled copy is absent.
	static let modelNames: Set<String> = [
		"crowpanel_2_4", "crowpanel_2_8", "crowpanel_3_5", "crowpanel_5_0", "crowpanel_7_0",
		"heltec-mesh-node-t114", "heltec-mesh-node-t114-case", "heltec-meshnode-t1", "heltec-t096",
		"heltec-v3", "heltec-v3-case", "heltec-vision-master-e213", "heltec-vision-master-e290",
		"heltec-vision-master-t190", "heltec-wireless-paper", "heltec-wireless-tracker", "heltec-wsl-v3",
		"heltec_mesh_pocket", "heltec_v4", "heltec_wireless_tracker_v2",
		"lilygo-tlora-pager",
		"muzi_base", "muzi_r1_neo",
		"rak-wismesh-tap-v2", "rak-wismeshtap", "rak11200", "rak11310", "rak2560", "rak3401", "rak4631",
		"rak4631_case", "rak6421", "rak_3312", "rak_wismesh_pocket", "rak_wismesh_tag",
		"seeed-sensecap-indicator", "seeed-xiao-s3", "seeed_mesh_tracker_x1", "seeed_solar",
		"seeed_wio_tracker_l1_pro_1w", "seeed_wio_tracker_l2", "seeed_xiao_nrf52_kit",
		"t-deck", "t-echo", "t-echo_plus", "t-watch-s3",
		"tbeam-1w", "tbeam-s3-core",
		"tdeck_pro",
		"thinknode_m1", "thinknode_m2", "thinknode_m3", "thinknode_m4", "thinknode_m6", "thinknode_m7",
		"thinknode_m9",
		"tlora-t3s3-epaper", "tlora-t3s3-v1",
		"tracker-t1000-e",
		"wio-tracker-wm1110", "wio_tracker_l1_case", "wio_tracker_l1_eink"
	]

	/// Chirpy, bundled beside the device models. He isn't hardware, so he's not in `modelNames`
	/// and is never downloaded.
	static let chirpy = "chirpy"

	/// Models whose catalog entry may not name a matching image, keyed by lowercased
	/// platformio target or hardware model slug.
	static let overrides: [String: String] = [
		"rak_wismesh_pocket": "rak_wismesh_pocket",
		"seeed_wio_tracker_l1_pro_1w": "seeed_wio_tracker_l1_pro_1w",
		"seeed_wio_tracker_l2": "seeed_wio_tracker_l2",
		"seeed_wio_tracker_l2-tft": "seeed_wio_tracker_l2"
	]

	/// The model for a catalog entry, or nil when there is none.
	static func modelName(platformioTarget: String?, hwModelSlug: String?, imageFileNames: [String]) -> String? {
		for key in [platformioTarget, hwModelSlug].compactMap({ $0?.lowercased() }) {
			if let name = overrides[key] { return name }
		}
		for fileName in imageFileNames.sorted() {
			let base = (fileName as NSString).deletingPathExtension
			if modelNames.contains(base) { return base }
		}
		return nil
	}

	/// The model for a node's hardware, using the same catalog entry the hardware image shows.
	static func modelName(for hwModel: Int64, in hardware: [DeviceHardwareEntity]) -> String? {
		guard let target = HardwareCatalogResolver.presentation(for: hwModel, in: hardware)?.platformioTarget,
			let entity = hardware.first(where: { $0.platformioTarget == target }) else { return nil }
		return modelName(
			platformioTarget: entity.platformioTarget,
			hwModelSlug: entity.hwModelSlug,
			imageFileNames: entity.images.compactMap(\.fileName)
		)
	}

	static func remoteURL(for name: String) -> URL? {
		URL(string: "https://flasher.meshtastic.org/models/devices/\(name).usdz")
	}
}

/// On-disk cache for downloaded models, with a marker for models the server didn't have so they
/// aren't asked for again for a day.
struct DeviceModelCache: Sendable {
	static let missingRetryInterval: TimeInterval = 24 * 60 * 60

	let directory: URL

	static var standard: DeviceModelCache {
		let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
		return DeviceModelCache(directory: caches.appendingPathComponent("DeviceModels", isDirectory: true))
	}

	func fileURL(for name: String) -> URL {
		directory.appendingPathComponent(name).appendingPathExtension("usdz")
	}

	func missingMarkerURL(for name: String) -> URL {
		directory.appendingPathComponent(name).appendingPathExtension("missing")
	}

	func cachedFile(for name: String) -> URL? {
		let url = fileURL(for: name)
		return FileManager.default.fileExists(atPath: url.path) ? url : nil
	}

	func isRecentlyMissing(_ name: String, now: Date = .now) -> Bool {
		let url = missingMarkerURL(for: name)
		guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
			let marked = attributes[.modificationDate] as? Date else { return false }
		return now.timeIntervalSince(marked) < Self.missingRetryInterval
	}

	func markMissing(_ name: String) throws {
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		try Data().write(to: missingMarkerURL(for: name))
	}

	/// Moves a finished download into place, replacing any older copy.
	func store(downloadedFile: URL, for name: String) throws -> URL {
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let destination = fileURL(for: name)
		try? FileManager.default.removeItem(at: destination)
		try FileManager.default.moveItem(at: downloadedFile, to: destination)
		try? FileManager.default.removeItem(at: missingMarkerURL(for: name))
		return destination
	}
}

/// Finds a local file for a device model: the bundled copy when the app ships one, otherwise a
/// cached or freshly downloaded copy from the web flasher.
actor DeviceModelSource {
	static let shared = DeviceModelSource()

	private let cache: DeviceModelCache
	private let session: URLSession
	private var inFlight: [String: Task<URL?, Error>] = [:]

	init(cache: DeviceModelCache = .standard, session: URLSession? = nil) {
		self.cache = cache
		if let session {
			self.session = session
		} else {
			let configuration = URLSessionConfiguration.default
			// Models are a nicety; don't spend a Low Data Mode allowance on them.
			configuration.allowsConstrainedNetworkAccess = false
			configuration.timeoutIntervalForRequest = 30
			self.session = URLSession(configuration: configuration)
		}
	}

	/// A local file URL for the model, or nil when there's no model or it couldn't be fetched.
	func localURL(for name: String) async -> URL? {
		guard DeviceModelCatalog.modelNames.contains(name) || name == DeviceModelCatalog.chirpy else { return nil }
		// A model built into the app wins; otherwise it's downloaded and cached.
		if let bundled = Bundle.main.url(forResource: name, withExtension: "usdz") {
			return bundled
		}
		guard name != DeviceModelCatalog.chirpy else { return nil }
		if let cached = cache.cachedFile(for: name) { return cached }
		if cache.isRecentlyMissing(name) { return nil }

		let task: Task<URL?, Error>
		if let existing = inFlight[name] {
			task = existing
		} else {
			task = Task { [cache, session] in
				try await Self.download(name, cache: cache, session: session)
			}
			inFlight[name] = task
		}
		defer { inFlight[name] = nil }
		do {
			return try await withTaskCancellationHandler {
				try await task.value
			} onCancel: {
				task.cancel()
			}
		} catch {
			if !(error is CancellationError), (error as? URLError)?.code != .cancelled {
				Logger.services.debug("Device model \(name, privacy: .public) not loaded: \(error.localizedDescription, privacy: .public)")
			}
			return nil
		}
	}

	/// Removes a cached copy that turned out not to open, so the next view fetches it again.
	func discardCachedFile(for name: String) {
		try? FileManager.default.removeItem(at: cache.fileURL(for: name))
	}

	private static func download(_ name: String, cache: DeviceModelCache, session: URLSession) async throws -> URL? {
		guard let url = DeviceModelCatalog.remoteURL(for: name) else { return nil }
		let (downloaded, response) = try await session.download(from: url)
		let status = (response as? HTTPURLResponse)?.statusCode ?? 0
		let missing = isMissingReply(status: status, mimeType: response.mimeType)
		guard status == 200, !missing else {
			try? FileManager.default.removeItem(at: downloaded)
			if missing { try cache.markMissing(name) }
			return nil
		}
		return try cache.store(downloadedFile: downloaded, for: name)
	}

	/// Whether a reply means the flasher doesn't have the model. It answers a missing file with
	/// its web page and a 200, so a text reply counts as missing as well as a 404.
	static func isMissingReply(status: Int, mimeType: String?) -> Bool {
		status == 404 || (mimeType?.hasPrefix("text/") ?? false)
	}
}
