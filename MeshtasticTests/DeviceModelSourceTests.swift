//
//  DeviceModelSourceTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/15/26.
//
import Foundation
import Testing
@testable import Meshtastic

@Suite("Device model catalog")
struct DeviceModelCatalogTests {

	@Test("image file name maps to the model with the same name")
	func imageNameMatch() {
		#expect(DeviceModelCatalog.modelName(platformioTarget: "tracker-t1000-e", hwModelSlug: "TRACKER_T1000_E", imageFileNames: ["tracker-t1000-e.svg"]) == "tracker-t1000-e")
		#expect(DeviceModelCatalog.modelName(platformioTarget: "thinknode_m5", hwModelSlug: "THINKNODE_M5", imageFileNames: ["thinknode_m1.svg"]) == "thinknode_m1")
	}

	@Test("first image with a model wins, in the same order the image grid uses")
	func multipleImages() {
		#expect(DeviceModelCatalog.modelName(platformioTarget: "rak4631", hwModelSlug: "RAK4631", imageFileNames: ["rak4631_case.svg", "rak4631.svg"]) == "rak4631")
		#expect(DeviceModelCatalog.modelName(platformioTarget: "x", hwModelSlug: nil, imageFileNames: ["station-g2.svg", "rak2560.svg"]) == "rak2560")
	}

	@Test("variants with a shared image use their own model")
	func overrides() {
		#expect(DeviceModelCatalog.modelName(platformioTarget: "rak_wismesh_pocket", hwModelSlug: "RAK4631", imageFileNames: ["rak4631.svg"]) == "rak_wismesh_pocket")
		#expect(DeviceModelCatalog.modelName(platformioTarget: "seeed_wio_tracker_L1_Pro_1W", hwModelSlug: "SEEED_WIO_TRACKER_L1_PRO_1W", imageFileNames: ["wio_tracker_l1_case.svg"]) == "seeed_wio_tracker_l1_pro_1w")
		#expect(DeviceModelCatalog.modelName(platformioTarget: "seeed_wio_tracker_L2-tft", hwModelSlug: "SEEED_WIO_TRACKER_L2", imageFileNames: []) == "seeed_wio_tracker_l2")
	}

	@Test("hardware without a model gets none")
	func noModel() {
		#expect(DeviceModelCatalog.modelName(platformioTarget: "station-g2", hwModelSlug: "STATION_G2", imageFileNames: ["station-g2.svg"]) == nil)
		#expect(DeviceModelCatalog.modelName(platformioTarget: nil, hwModelSlug: nil, imageFileNames: []) == nil)
	}

	@Test("every override points at a known model")
	func overridesAreKnown() {
		for name in DeviceModelCatalog.overrides.values {
			#expect(DeviceModelCatalog.modelNames.contains(name))
		}
	}

	@Test("known model list matches the files in Resources/DeviceModels")
	func listMatchesFiles() throws {
		let folder = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent("Meshtastic/Resources/DeviceModels")
		let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
			.filter { $0.hasSuffix(".usdz") }
			.map { ($0 as NSString).deletingPathExtension }
		#expect(Set(files) == DeviceModelCatalog.modelNames.union([DeviceModelCatalog.chirpy]))
	}

	@Test("remote URL is on the web flasher")
	func remoteURL() {
		#expect(DeviceModelCatalog.remoteURL(for: "rak4631")?.absoluteString == "https://flasher.meshtastic.org/models/devices/rak4631.usdz")
	}
}

@Suite("Device model cache")
struct DeviceModelCacheTests {

	private func makeCache() -> DeviceModelCache {
		DeviceModelCache(directory: FileManager.default.temporaryDirectory
			.appendingPathComponent("DeviceModelCacheTests-\(UUID().uuidString)", isDirectory: true))
	}

	@Test("files live under the cache directory by model name")
	func paths() {
		let cache = makeCache()
		#expect(cache.fileURL(for: "rak4631").lastPathComponent == "rak4631.usdz")
		#expect(cache.fileURL(for: "rak4631").deletingLastPathComponent() == cache.directory)
		#expect(cache.missingMarkerURL(for: "rak4631").lastPathComponent == "rak4631.missing")
		#expect(DeviceModelCache.standard.directory.lastPathComponent == "DeviceModels")
	}

	@Test("a missing model is remembered for a day")
	func missingMarker() throws {
		let cache = makeCache()
		defer { try? FileManager.default.removeItem(at: cache.directory) }
		#expect(!cache.isRecentlyMissing("rak4631"))

		try cache.markMissing("rak4631")
		#expect(cache.isRecentlyMissing("rak4631"))
		// Built outside #expect: the macro's rewrite loses the Int-literal to
		// TimeInterval inference on the CI toolchain and fails to compile.
		let justUnderADay = Date.now.addingTimeInterval(23 * 60 * 60)
		let justOverADay = Date.now.addingTimeInterval(25 * 60 * 60)
		#expect(cache.isRecentlyMissing("rak4631", now: justUnderADay))
		#expect(!cache.isRecentlyMissing("rak4631", now: justOverADay))
	}

	@Test("storing a download replaces the old copy and clears the missing marker")
	func store() throws {
		let cache = makeCache()
		defer { try? FileManager.default.removeItem(at: cache.directory) }
		#expect(cache.cachedFile(for: "rak4631") == nil)
		try cache.markMissing("rak4631")

		for contents in ["first", "second"] {
			let download = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
			try Data(contents.utf8).write(to: download)
			_ = try cache.store(downloadedFile: download, for: "rak4631")
		}

		let stored = try #require(cache.cachedFile(for: "rak4631"))
		#expect(try String(contentsOf: stored, encoding: .utf8) == "second")
		#expect(!cache.isRecentlyMissing("rak4631"))
	}

	@Test("a 404 or the flasher's web page counts as missing")
	func missingReply() {
		#expect(DeviceModelSource.isMissingReply(status: 404, mimeType: "text/html"))
		#expect(DeviceModelSource.isMissingReply(status: 200, mimeType: "text/html"))
		#expect(!DeviceModelSource.isMissingReply(status: 200, mimeType: "model/vnd.usdz+zip"))
		#expect(!DeviceModelSource.isMissingReply(status: 503, mimeType: nil))
	}

	@Test("hardware without a model never reaches the network")
	func unknownModel() async {
		let source = DeviceModelSource(cache: makeCache())
		#expect(await source.localURL(for: "station-g2") == nil)
	}
}
