//
//  OfflineTileManager.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 4/23/23.
//

import Foundation
import MapKit
import OSLog

class OfflineTileManager: ObservableObject {
	static let shared = OfflineTileManager()

	// MARK: - Public properties

	@Published var status: DownloadStatus = .downloaded

	enum DownloadStatus {
		case downloaded, downloading
	}

	init() {
		Logger.services.info("🗂️ Documents Directory = \(self.documentsDirectory.absoluteString, privacy: .public)")
		createDirectoriesIfNecessary()
	}

	// MARK: - Private properties

	private var overlay: MKTileOverlay { MKTileOverlay(urlTemplate: UserDefaults.mapTileServer.tileUrl.count > 1 ? UserDefaults.mapTileServer.tileUrl : MapTileServer.openStreetMap.tileUrl) }
	private var documentsDirectory: URL { fileManager.urls(for: .documentDirectory, in: .userDomainMask).first! }
	private let fileManager = FileManager.default

	// MARK: - Public methods

	func getAllDownloadedSize() -> String {
		fileManager.allocatedSizeOfDirectory(at: documentsDirectory.appendingPathComponent("tiles"))
	}

	func removeAll() {
		try? fileManager.removeItem(at: documentsDirectory.appendingPathComponent("tiles"))
		createDirectoriesIfNecessary()
	}

	func loadAndCacheTileOverlay(for path: MKTileOverlayPath) throws -> Data {
		guard UserDefaults.enableOfflineMaps, UserDefaults.mapTileServer.zoomRange.contains(path.z) else {
			return try Data(contentsOf: Bundle.main.url(forResource: "alpha", withExtension: "png")!)
		}

		let tilesUrl = documentsDirectory
			.appendingPathComponent("tiles")
			.appendingPathComponent("\(UserDefaults.mapTileServer.id)-z\(path.z)x\(path.x)y\(path.y)")
			.appendingPathExtension("png")

		do {
			return try Data(contentsOf: tilesUrl)
		} catch let error as NSError where error.code == NSFileReadNoSuchFileError {
			DispatchQueue.main.async { self.status = .downloading }
			defer {
				DispatchQueue.main.async { self.status = .downloaded }
			}
			let data = try Data(contentsOf: overlay.url(forTilePath: path))
			try data.write(to: tilesUrl)
			return data
		}
	}

	// MARK: Private methods

	private func createDirectoriesIfNecessary() {
		let tiles = documentsDirectory.appendingPathComponent("tiles")
		try? fileManager.createDirectory(at: tiles, withIntermediateDirectories: true, attributes: [:])
	}
}
