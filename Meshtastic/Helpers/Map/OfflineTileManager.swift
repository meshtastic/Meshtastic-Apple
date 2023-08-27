//
//  OfflineTileManager.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 4/23/23.
//

import Foundation
import MapKit

class OfflineTileManager: ObservableObject {
	enum DownloadStatus {
		case download, downloading, downloaded
	}
	static let shared = OfflineTileManager()
	init() {
		print("Documents Directory = \(documentsDirectory)")
		createDirectoriesIfNecessary()
	}
	// MARK: - Private properties
	private var overlay: MKTileOverlay { MKTileOverlay(urlTemplate: UserDefaults.mapTileServer.tileUrl.count > 1 ? UserDefaults.mapTileServer.tileUrl : MapTileServer.openStreetMap.tileUrl) }
	private var documentsDirectory: URL { fileManager.urls(for: .documentDirectory, in: .userDomainMask).first! }
	private let fileManager = FileManager.default
	// MARK: - Public property
	var progress: Float = 0
	var status: DownloadStatus = .download
	// MARK: - Public methods
	func getAllDownloadedSize() -> String {
		fileManager.allocatedSizeOfDirectory(at: documentsDirectory.appendingPathComponent("tiles"))
	}
	func hasBeenDownloaded(for boundingBox: MKMapRect) -> Bool {
		getEstimatedDownloadSize(for: boundingBox) == 0
	}
	func getEstimatedDownloadSize(for boundingBox: MKMapRect) -> Double {
		let paths = self.computeTileOverlayPaths(boundingBox: boundingBox)
		let count = self.filterTilesAlreadyExisting(paths: paths).count
		let size: Double = 30000 // Bytes (average size)
		return Double(count) * size
	}
	func getDownloadedSize(for mapTileLink: MapTileServer) -> Double {
		var accumulatedSize: UInt64 = 0
		let mapTiles = try! fileManager.contentsOfDirectory(at: documentsDirectory.appendingPathComponent("tiles"), includingPropertiesForKeys: [])
		let matchingTiles = mapTiles.filter { fileName in
			let fileNameLower = fileName.absoluteString
			return fileNameLower.contains(mapTileLink.id)
		}
		print("Deleting \(matchingTiles.count) tiles for \(mapTileLink.id)")
		for tile in matchingTiles {
			let url = documentsDirectory.appendingPathComponent(tile.absoluteString)
			accumulatedSize += (try? url.regularFileAllocatedSize()) ?? 0
		}
		return Double(accumulatedSize)
	}
	func getDownloadedSize(for boundingBox: MKMapRect) -> Double {
		let paths = self.computeTileOverlayPaths(boundingBox: boundingBox)
		var accumulatedSize: UInt64 = 0
		for path in paths {
			let file = "tiles/\(UserDefaults.mapTileServer.id)-z\(path.z)x\(path.x)y\(path.y).png"
			let url = documentsDirectory.appendingPathComponent(file)
			accumulatedSize += (try? url.regularFileAllocatedSize()) ?? 0
		}
		return Double(accumulatedSize)
	}
	func removeAll() {
		try? fileManager.removeItem(at: documentsDirectory.appendingPathComponent("tiles"))
		createDirectoriesIfNecessary()
	}
	func remove(for mapTileLink: MapTileServer) {
		let mapTiles = try! fileManager.contentsOfDirectory(at: documentsDirectory.appendingPathComponent("tiles"), includingPropertiesForKeys: [])
		let matchingTiles = mapTiles.filter { fileName in
			let fileNameLower = fileName.absoluteString
			return fileNameLower.contains(mapTileLink.id)
		}
		print("Deleting \(matchingTiles.count) tiles for \(mapTileLink.id)")
		for tile in matchingTiles {
			try? fileManager.removeItem(at: tile.absoluteURL)
		}
	}
	func remove(for boundingBox: MKMapRect) {
		let paths = self.computeTileOverlayPaths(boundingBox: boundingBox)
		for path in paths {
			let file = "tiles/\(UserDefaults.mapTileServer.id)-z\(path.z)x\(path.x)y\(path.y).png"
			let url = documentsDirectory.appendingPathComponent(file)
			try? fileManager.removeItem(at: url)
		}
		self.status = .download
	}
	/// Download and persist all tiles within the boundingBox
	func download(boundingBox: MKMapRect, name: String) {
		NetworkManager.shared.runIfNetwork {
			self.status = .downloading
			self.progress = 0.01
			let paths = self.computeTileOverlayPaths(boundingBox: boundingBox)
			let filteredPaths = self.filterTilesAlreadyExisting(paths: paths)
			for i in 0..<filteredPaths.count {
				self.persistLocally(path: filteredPaths[i])
				self.progress = Float(i) / Float(filteredPaths.count)
			}
			DispatchQueue.main.async {
				// NotificationManager.shared.sendNotification(title: "\("DownloadedTitle".localized) (\((self.getDownloadedSize(for: boundingBox)).toBytes))", message: "\("Downloaded".localized) (\(name))")
				self.progress = 0
				self.status = .downloaded
			}
		}
	}
	func getTileOverlay(for path: MKTileOverlayPath) -> URL {
		let file = "\(UserDefaults.mapTileServer.id)-z\(path.z)x\(path.x)y\(path.y).png"
		// Check is tile is already available
		let tilesUrl = documentsDirectory.appendingPathComponent("tiles").appendingPathComponent(file)
		if fileManager.fileExists(atPath: tilesUrl.path) {
			return tilesUrl
		} else {
			if UserDefaults.enableOfflineMaps { // Get and persist newTile
				return persistLocally(path: path)
			} else { // Else display empty tile (transparent over Maps tiles)
				return Bundle.main.url(forResource: "alpha", withExtension: "png")!
			}
		}
	}
	// MARK: Private methods
	private func computeTileOverlayPaths(boundingBox box: MKMapRect, maxZ: Int = 17) -> [MKTileOverlayPath] {
		var paths = [MKTileOverlayPath]()
		for z in 1...maxZ {
			let topLeft = tranformCoordinate(coordinates: MKMapPoint(x: box.minX, y: box.minY).coordinate, zoom: z)
			let topRight = tranformCoordinate(coordinates: MKMapPoint(x: box.maxX, y: box.minY).coordinate, zoom: z)
			let bottomLeft = tranformCoordinate(coordinates: MKMapPoint(x: box.minX, y: box.maxY).coordinate, zoom: z)
			for x in topLeft.x...topRight.x {
				for y in topLeft.y...bottomLeft.y {
					paths.append(MKTileOverlayPath(x: x, y: y, z: z, contentScaleFactor: 2))
				}
			}
		}
		return paths
	}
	private func tranformCoordinate(coordinates: CLLocationCoordinate2D, zoom: Int) -> TileCoordinates {
		let lng = coordinates.longitude
		let lat = coordinates.latitude
		let tileX = Int(floor((lng + 180) / 360.0 * pow(2.0, Double(zoom))))
		let tileY = Int(floor((1 - log( tan( lat * Double.pi / 180.0 ) + 1 / cos( lat * Double.pi / 180.0 )) / Double.pi ) / 2 * pow(2.0, Double(zoom))))
		return (tileX, tileY, zoom)
	}
	@discardableResult private func persistLocally(path: MKTileOverlayPath) -> URL {
		let url = overlay.url(forTilePath: path)
		let file = "tiles/\(UserDefaults.mapTileServer.id)-z\(path.z)x\(path.x)y\(path.y).png"
		let filename = documentsDirectory.appendingPathComponent(file)
		do {
			let data = try Data(contentsOf: url)
			try data.write(to: filename)
		} catch {
			print("💀 Save Tile Error = \(error)")
		}
		return url
	}
	private func filterTilesAlreadyExisting(paths: [MKTileOverlayPath]) -> [MKTileOverlayPath] {
		paths.filter {
			let file = "\(UserDefaults.mapTileServer.id)-z\($0.z)x\($0.x)y\($0.y).png"
			let tilesPath = documentsDirectory.appendingPathComponent("tiles").appendingPathComponent(file).path
			return !fileManager.fileExists(atPath: tilesPath)
		}
	}
	private func createDirectoriesIfNecessary() {
		let tiles = documentsDirectory.appendingPathComponent("tiles")
		try? fileManager.createDirectory(at: tiles, withIntermediateDirectories: true, attributes: [:])
	}
}
