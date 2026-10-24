import Foundation
import MapKit
import OSLog
import Combine

/// Manager for handling user-uploaded map data files
class MapDataManager: ObservableObject {
	static let shared = MapDataManager()
	/// `directoryName` is the folder under Documents; tests pass their own so they don't touch the app's files.
	init(directoryName: String = "MapData") {
		mapDataDirectory = directoryName
	}

	// MARK: - Constants
	/// The most a map file may be, as picked and as stored once converted. Android takes 50 MB
	/// for files shared into the app, and KML and KMZ exports of real surveys run well past 10.
	static let maxFileSize: Int64 = 50 * 1024 * 1024
	private var maxFileSize: Int64 { Self.maxFileSize }
	private let mapDataDirectory: String
	private let userUploadedDirectory = "user_uploaded"
	private let metadataFileName = "upload_history.json"

	// MARK: - Properties
	@Published private var uploadedFiles: [MapDataMetadata] = []
	private var activeFeatureCollection: GeoJSONFeatureCollection?
	/// The Site Planner files each import switched off, so `discardImport` can turn them back on.
	private var switchedOffBy: [UUID: [UUID]] = [:]

	// MARK: - File Management

	/// Get the base URL for map data storage
	private func getMapDataDirectory() -> URL? {
		guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
			Logger.services.error("🗂️ Could not access documents directory")
			return nil
		}
		return documentsURL.appendingPathComponent(mapDataDirectory)
	}

	/// Get the URL for user uploaded files
	private func getUserUploadedDirectory() -> URL? {
		guard let baseURL = getMapDataDirectory() else { return nil }
		return baseURL.appendingPathComponent(userUploadedDirectory)
	}

	/// Get the URL for metadata file
	private func getMetadataFileURL() -> URL? {
		guard let baseURL = getMapDataDirectory() else { return nil }
		return baseURL.appendingPathComponent(metadataFileName)
	}

	/// Create necessary directories
	private func createDirectoriesIfNeeded() -> Bool {
		guard let userDir = getUserUploadedDirectory() else { return false }

		do {
			try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
			return true
		} catch {
			Logger.services.error("🗂️ Failed to create directories: \(error.localizedDescription, privacy: .public)")
			return false
		}
	}

	// MARK: - File Upload & Processing

	/// Process and store an uploaded file
	func processUploadedFile(from sourceURL: URL, source: MapDataSource = .manualUpload, coverage: SitePlannerCoverageInfo? = nil, assets: [String: Data]? = nil) async throws -> MapDataMetadata {

		// 1. Start accessing security-scoped resource
		let isAccessing = sourceURL.startAccessingSecurityScopedResource()
		defer {
			if isAccessing {
				sourceURL.stopAccessingSecurityScopedResource()
			}
		}

		// A KML or KMZ becomes a GeoJSON layer (plus its images) and goes through this same
		// pipeline from there.
		if KMLFileTypes.isKMLOrKMZ(sourceURL) {
			return try await importKMLFile(from: sourceURL, source: source)
		}

		// 2. Validate file
		try validateFile(at: sourceURL)

		// 2. Create directories if needed
		guard createDirectoriesIfNeeded() else {
			throw MapDataError.directoryCreationFailed
		}

		// 3. Generate destination filename
		let timestamp = Date().timeIntervalSince1970
		let originalName = sourceURL.deletingPathExtension().lastPathComponent
		let fileExtension = sourceURL.pathExtension
		let newFilename = "\(originalName)_\(Int(timestamp)).\(fileExtension)"

		guard let destURL = getUserUploadedDirectory()?.appendingPathComponent(newFilename) else {
			throw MapDataError.invalidDestination
		}

		// 4. Copy file to app storage
		try FileManager.default.copyItem(at: sourceURL, to: destURL)

		// 5. Process and validate content
		let metadata = try await processFileContent(at: destURL, originalName: originalName, source: source, coverage: coverage)

		// Images a KMZ brought along sit beside the layer, in a folder named for its file.
		if let assets, !assets.isEmpty {
			do {
				try writeAssets(assets, forFilename: newFilename)
			} catch {
				removeAssets(forFilename: newFilename)
				try? FileManager.default.removeItem(at: destURL)
				throw error
			}
		}

		// 6. Save metadata and update UI on main thread
		await MainActor.run {
			uploadedFiles.append(metadata)
			// A new Site Planner run replaces the previous run from the same transmitter,
			// so estimates for different nodes can show together. Manual uploads are never
			// touched — their visibility belongs to the user.
			var switchedOff: [UUID] = []
			for index in uploadedFiles.indices
			where uploadedFiles[index].id != metadata.id && Self.replaces(metadata, uploadedFiles[index]) {
				if uploadedFiles[index].isActive { switchedOff.append(uploadedFiles[index].id) }
				uploadedFiles[index].isActive = false
			}
			if !switchedOff.isEmpty { switchedOffBy[metadata.id] = switchedOff }
			// Clear cached configuration to force reload
			activeFeatureCollection = nil
		}
		try saveMetadata()

		return metadata
	}

	/// Imports an in-memory GeoJSON string (e.g. the coverage `FeatureCollection` handed back by
	/// the Site Planner's native bridge) through the same pipeline as `processUploadedFile`, so it
	/// reuses the exact validation + render + styling path with no round-trip to the share sheet.
	/// `name` becomes the on-disk file / layer name; a `.geojson` extension is enforced.
	/// `coverage` describes the transmitter of a Site Planner run and is saved with the file.
	func importFromString(_ geoJSON: String, name: String, source: MapDataSource = .manualUpload, coverage: SitePlannerCoverageInfo? = nil, assets: [String: Data]? = nil) async throws -> MapDataMetadata {
		guard let data = geoJSON.data(using: .utf8) else {
			throw MapDataError.invalidContent
		}
		guard data.count <= maxFileSize else {
			throw MapDataError.fileTooLarge
		}

		// Sanitise the caller-supplied name into a safe single path component and enforce `.geojson`.
		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		let base = trimmed.isEmpty ? "coverage" : trimmed
		let safeBase = base
			.components(separatedBy: CharacterSet(charactersIn: "/\\:\n\r\t"))
			.joined(separator: "-")
		let fileName = safeBase.lowercased().hasSuffix(".geojson") ? safeBase : "\(safeBase).geojson"

		let tempURL = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString)
			.appendingPathComponent(fileName)
		try FileManager.default.createDirectory(at: tempURL.deletingLastPathComponent(), withIntermediateDirectories: true)
		try data.write(to: tempURL)
		defer { try? FileManager.default.removeItem(at: tempURL) }

		return try await processUploadedFile(from: tempURL, source: source, coverage: coverage, assets: assets)
	}

	/// Reads a KML or KMZ, converts it to a GeoJSON layer and stores that, with any images a KMZ
	/// held that the layer draws. Called with security-scoped access already open.
	private func importKMLFile(from sourceURL: URL, source: MapDataSource) async throws -> MapDataMetadata {
		let attributes = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
		guard attributes.isRegularFile == true else { throw MapDataError.invalidFileType }
		guard let size = attributes.fileSize, Int64(size) <= maxFileSize else { throw MapDataError.fileTooLarge }
		let originalName = sourceURL.deletingPathExtension().lastPathComponent

		// Unpacking and converting can take a while on a big survey, so it stays off the main actor.
		let package = try await Task.detached(priority: .userInitiated) { () -> KMLImportPackage in
			let data = try Data(contentsOf: sourceURL)
			if KMZArchive.isArchive(data) {
				let archive = try KMZArchive(data: data)
				return try KMLImporter.package(kml: try archive.kmlData(), imageData: { archive.data(forHref: $0) })
			}
			return try KMLImporter.package(kml: data, imageData: { _ in nil })
		}.value

		var assets = package.assets
		if let overlays = package.groundOverlaysJSON { assets[Self.groundOverlaysFileName] = overlays }
		return try await importFromString(package.geoJSON, name: originalName, source: source, assets: assets)
	}

	/// The list of a layer's ground overlays, kept beside its images.
	static let groundOverlaysFileName = "ground-overlays.json"

	// MARK: - Layer images

	private func assetsDirectoryURL(forFilename filename: String) -> URL? {
		getUserUploadedDirectory()?.appendingPathComponent(filename + ".assets", isDirectory: true)
	}

	/// Where an image a layer names is kept, or nil when the layer has none by that name.
	func assetURL(forFilename filename: String, name: String) -> URL? {
		// A name from the layer's own file is never trusted to be a path.
		guard name == (name as NSString).lastPathComponent, !name.hasPrefix(".") else { return nil }
		guard let url = assetsDirectoryURL(forFilename: filename)?.appendingPathComponent(name),
			  FileManager.default.fileExists(atPath: url.path) else { return nil }
		return url
	}

	private func writeAssets(_ assets: [String: Data], forFilename filename: String) throws {
		guard let directory = assetsDirectoryURL(forFilename: filename) else { throw MapDataError.invalidDestination }
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		for (name, data) in assets where name == (name as NSString).lastPathComponent {
			try data.write(to: directory.appendingPathComponent(name))
		}
	}

	private func removeAssets(forFilename filename: String) {
		guard let directory = assetsDirectoryURL(forFilename: filename) else { return }
		try? FileManager.default.removeItem(at: directory)
	}

	/// The ground overlays (images laid on the map between four edges) of the given layers.
	func groundOverlays(for files: [MapDataMetadata]) -> [ImportedGroundOverlay] {
		var result: [ImportedGroundOverlay] = []
		for file in files {
			// Only a layer that kept images beside it can have ground overlays.
			guard let listURL = assetsDirectoryURL(forFilename: file.filename)?
					.appendingPathComponent(Self.groundOverlaysFileName),
				  let data = try? Data(contentsOf: listURL),
				  let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { continue }
			for (index, entry) in entries.enumerated() {
				guard let imageName = entry["image"] as? String,
					  let imageURL = assetURL(forFilename: file.filename, name: imageName),
					  let north = entry["north"] as? Double, let south = entry["south"] as? Double,
					  let east = entry["east"] as? Double, let west = entry["west"] as? Double else { continue }
				result.append(ImportedGroundOverlay(
					id: "\(file.id.uuidString)-\(index)",
					name: entry["name"] as? String,
					imageURL: imageURL,
					north: north, south: south, east: east, west: west,
					rotation: entry["rotation"] as? Double ?? 0
				))
			}
		}
		return result
	}

	/// Points a layer's features at the image files they name, so drawing needs no lookup back to
	/// the file. The path is made at load time and never saved.
	private func resolvingAssets(in collection: GeoJSONFeatureCollection, for file: MapDataMetadata) -> GeoJSONFeatureCollection {
		guard collection.features.contains(where: { feature in
			if case .string = feature.properties?["icon-image"] { return true }
			return false
		}) else { return collection }
		let features = collection.features.map { feature -> GeoJSONFeature in
			guard case .string(let name) = feature.properties?["icon-image"],
				  let url = assetURL(forFilename: file.filename, name: name) else { return feature }
			var properties = feature.properties ?? [:]
			properties["icon-path"] = .string(url.path)
			return GeoJSONFeature(type: feature.type, id: feature.id, geometry: feature.geometry, properties: properties)
		}
		return GeoJSONFeatureCollection(type: collection.type, features: features)
	}

	/// Whether a new file switches an older one off: only Site Planner runs from the same node, or
	/// from no node (a map-center run, or a file saved before the node was recorded).
	static func replaces(_ newer: MapDataMetadata, _ older: MapDataMetadata) -> Bool {
		newer.source == .sitePlanner && older.source == .sitePlanner
			&& newer.coverage?.nodeNum == older.coverage?.nodeNum
	}

	/// Validate uploaded file
	private func validateFile(at url: URL) throws {
		let fileAttributes = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])

		// Check file size
		guard let fileSize = fileAttributes.fileSize, fileSize <= maxFileSize else {
			throw MapDataError.fileTooLarge
		}

		// Check if it's a regular file
		guard fileAttributes.isRegularFile == true else {
			throw MapDataError.invalidFileType
		}

		// Check file extension
		let allowedExtensions = ["json", "geojson"]
		let fileExtension = url.pathExtension.lowercased()
		guard allowedExtensions.contains(fileExtension) else {
			throw MapDataError.unsupportedFormat
		}
	}

	/// Process file content and extract metadata
	private func processFileContent(at url: URL, originalName: String, source: MapDataSource, coverage: SitePlannerCoverageInfo?) async throws -> MapDataMetadata {
		let fileAttributes = try url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
		let fileSize = fileAttributes.fileSize ?? 0
		let uploadDate = fileAttributes.creationDate ?? Date()

		// Read and process file content on background queue
		let (data, overlayCount) = try await withCheckedThrowingContinuation { continuation in
			Task.detached {
				do {
					let data = try Data(contentsOf: url)
					let overlayCount = try self.getOverlayCount(from: data)
					continuation.resume(returning: (data, overlayCount))
				} catch {
					continuation.resume(throwing: error)
				}
			}
		}

		// Validate GeoJSON schema
		let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
		guard let geoJSON = jsonObject as? [String: Any] else {
			throw NSError(domain: "MapDataManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid GeoJSON format"])
		}

		// Check required properties
		guard let type = geoJSON["type"] as? String, type == "FeatureCollection",
			  let features = geoJSON["features"] as? [[String: Any]] else {
			throw NSError(domain: "MapDataManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "GeoJSON must be a FeatureCollection with features"])
		}

		// Validate each feature
		for feature in features {
			guard let geometry = feature["geometry"] as? [String: Any],
				  let coordinates = geometry["coordinates"] as? [Any],
				  let geometryType = geometry["type"] as? String else {
				throw NSError(domain: "MapDataManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid feature structure in GeoJSON"])
			}
		}

		return MapDataMetadata(
			filename: url.lastPathComponent,
			originalName: originalName,
			uploadDate: uploadDate,
			fileSize: Int64(fileSize),
			format: url.pathExtension.lowercased(),
			license: nil, // Will be extracted from content if available
			attribution: nil, // Will be extracted from content if available
			overlayCount: overlayCount,
			// New files start visible: a coverage run replaces the previous one
			// (older planner files are deactivated by the caller), and a manual
			// upload shows immediately with its visibility toggle in the user's hands.
			isActive: true,
			source: source,
			coverage: coverage
		)
	}

	/// Get overlay count from raw GeoJSON data
	private func getOverlayCount(from data: Data) throws -> Int {
		// Parse as raw GeoJSON FeatureCollection
		if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
		   let features = json["features"] as? [[String: Any]] {
			// A KMZ made only of ground overlays has no features and is still worth showing.
			let groundOverlays = (json["groundOverlays"] as? [[String: Any]])?.count ?? 0
			return features.count + groundOverlays
		}
		throw MapDataError.invalidContent
	}

	/// Load feature collection from a single file
	private func loadFeatureCollectionFromFile(_ file: MapDataMetadata) throws -> GeoJSONFeatureCollection? {
		guard let fileURL = getUserUploadedDirectory()?.appendingPathComponent(file.filename) else {
			throw MapDataError.fileNotFound
		}

		let data = try Data(contentsOf: fileURL)
		return resolvingAssets(in: try GeoJSONFeatureCollection.parse(data), for: file)
	}

	// MARK: - Configuration Loading

	/// Load combined feature collection from specific files
	func loadFeatureCollectionForFiles(_ files: [MapDataMetadata]) -> GeoJSONFeatureCollection? {
		guard !files.isEmpty else {
			return nil
		}

		var allFeatures: [GeoJSONFeature] = []

		for file in files {
			do {
				if let featureCollection = try loadFeatureCollectionFromFile(file) {
					allFeatures.append(contentsOf: featureCollection.features)
				}
			} catch {
				Logger.services.error("📁 MapDataManager: Failed to load feature collection from \(file.filename, privacy: .public): \(error.localizedDescription, privacy: .public)")
				continue
			}
		}

		guard !allFeatures.isEmpty else {
			return nil
		}
		return GeoJSONFeatureCollection(type: "FeatureCollection", features: allFeatures)
	}

	/// Load and combine raw GeoJSON feature collections from all active files
	func loadFeatureCollection() -> GeoJSONFeatureCollection? {
		if let cached = activeFeatureCollection {
			return cached
		}

		// Find active user files
		let activeFiles = uploadedFiles.filter { $0.isActive }

		guard !activeFiles.isEmpty else {
			return nil
		}

		var allFeatures: [GeoJSONFeature] = []

		// Load features from all active files
		for activeFile in activeFiles {

			guard let fileURL = getUserUploadedDirectory()?.appendingPathComponent(activeFile.filename) else {
				Logger.services.error("📁 MapDataManager: Could not construct file URL for: \(activeFile.filename, privacy: .public)")
				continue
			}

			// Check if file exists before trying to load it
			if !FileManager.default.fileExists(atPath: fileURL.path) {
				Logger.services.error("📁 MapDataManager: Active file does not exist at path: \(fileURL.path, privacy: .public)")

				// Remove the missing file from our metadata
				if let index = uploadedFiles.firstIndex(where: { $0.filename == activeFile.filename }) {
					uploadedFiles.remove(at: index)
					do {
						try saveMetadata()
					} catch {
						Logger.services.error("📁 MapDataManager: Failed to save cleaned metadata: \(error.localizedDescription, privacy: .public)")
					}
				}
				continue
			}

			do {
				let data = try Data(contentsOf: fileURL)
				let featureCollection = resolvingAssets(
					in: try GeoJSONFeatureCollection.parse(data),
					for: activeFile
				)

				allFeatures.append(contentsOf: featureCollection.features)
			} catch {
				Logger.services.error("📁 MapDataManager: Failed to load feature collection from \(activeFile.filename, privacy: .public): \(error.localizedDescription, privacy: .public)")
			}
		}

		// Create combined feature collection
		let combinedCollection = GeoJSONFeatureCollection(
			type: "FeatureCollection",
			features: allFeatures
		)

		activeFeatureCollection = combinedCollection
		return combinedCollection
	}

	// MARK: - File Management

	/// Get all uploaded files
	func getUploadedFiles() -> [MapDataMetadata] {
		return uploadedFiles
	}

	/// Set the active state of an uploaded file explicitly (the settings toggles
	/// persist through this, so visibility survives relaunch).
	func setFileActive(_ fileId: UUID, _ isActive: Bool) {
		guard let index = uploadedFiles.firstIndex(where: { $0.id == fileId }),
			  uploadedFiles[index].isActive != isActive else { return }
		let previous = uploadedFiles[index].isActive
		uploadedFiles[index].isActive = isActive
		do {
			try saveMetadata()
			activeFeatureCollection = nil
		} catch {
			// Revert so the session never shows a visibility the manifest does not
			// hold — otherwise a relaunch would silently flip it back.
			uploadedFiles[index].isActive = previous
			Logger.services.error("🚨 MapDataManager: FAILED to save metadata after setting file active: \(error.localizedDescription)")
		}
	}

	/// Toggle the active state of an uploaded file
	func toggleFileActive(_ fileId: UUID) {
		if let index = uploadedFiles.firstIndex(where: { $0.id == fileId }) {
			uploadedFiles[index].isActive.toggle()

			// Save metadata changes
			do {
				try saveMetadata()
				// Clear cached data to force reload
				activeFeatureCollection = nil
			} catch {
				Logger.services.error("🚨 MapDataManager: FAILED to save metadata after toggling file: \(error.localizedDescription)")
			}
		}
	}

	/// Delete a file that was just imported and turn back on the files its import switched off, unless a
	/// newer active file replaces them. Used when a coverage run is cancelled while its file is saving.
	func discardImport(_ metadata: MapDataMetadata) async throws {
		let switchedOff = await MainActor.run { switchedOffBy[metadata.id] ?? [] }
		try await deleteFile(metadata)
		guard !switchedOff.isEmpty else { return }
		await MainActor.run {
			for id in switchedOff {
				guard let index = uploadedFiles.firstIndex(where: { $0.id == id }) else { continue }
				let older = uploadedFiles[index]
				let stillReplaced = uploadedFiles.contains { $0.id != older.id && $0.isActive && Self.replaces($0, older) }
				if !stillReplaced { uploadedFiles[index].isActive = true }
			}
			activeFeatureCollection = nil
		}
		try saveMetadata()
	}

	/// Delete uploaded file
	func deleteFile(_ metadata: MapDataMetadata) async throws {

		guard let fileURL = getUserUploadedDirectory()?.appendingPathComponent(metadata.filename) else {
			Logger.services.error("🗑️ MapDataManager: Could not construct file URL for: \(metadata.filename, privacy: .public)")
			throw MapDataError.fileNotFound
		}

		// Check if file exists before trying to delete
		if !FileManager.default.fileExists(atPath: fileURL.path) {
			Logger.services.warning("🗑️ MapDataManager: File does not exist at path: \(fileURL.path, privacy: .public)")
		}

		do {
			try FileManager.default.removeItem(at: fileURL)
		} catch {
			Logger.services.error("🗑️ MapDataManager: Failed to remove file: \(error.localizedDescription, privacy: .public)")
			throw error
		}
		removeAssets(forFilename: metadata.filename)

		// Update UI-related properties on main thread
		await MainActor.run {
			switchedOffBy[metadata.id] = nil
			if let index = uploadedFiles.firstIndex(where: { $0.filename == metadata.filename }) {
				uploadedFiles.remove(at: index)
			} else {
				Logger.services.warning("🗑️ MapDataManager: File not found in uploadedFiles array")
			}
		}

		do {
			try saveMetadata()
		} catch {
			Logger.services.error("🗑️ MapDataManager: Failed to save metadata: \(error.localizedDescription, privacy: .public)")
			throw error
		}

		// Clear cache if this was the active file
		await MainActor.run {
			if activeFeatureCollection != nil {
				activeFeatureCollection = nil
			}
		}

		// Clear GeoJSON overlay manager cache
		GeoJSONOverlayManager.shared.clearCache()

		// Notify UI components that a file was deleted
		await MainActor.run {
			NotificationCenter.default.post(name: Foundation.Notification.Name.mapDataFileDeleted, object: metadata.id)
		}

	}

	// MARK: - Metadata Persistence

	/// Load metadata from disk
	func loadMetadata() {
		guard let metadataURL = getMetadataFileURL(),
			  let data = try? Data(contentsOf: metadataURL),
			  let files = try? JSONDecoder().decode([MapDataMetadata].self, from: data) else {
			uploadedFiles = []
			return
		}

		uploadedFiles = files
	}

	/// Save metadata to disk
	private func saveMetadata() throws {
		guard let metadataURL = getMetadataFileURL() else {
			throw MapDataError.invalidDestination
		}

		let data = try JSONEncoder().encode(uploadedFiles)
		try data.write(to: metadataURL)
	}

	// MARK: - Initialization

	/// Initialize the manager
	func initialize() {
		loadMetadata()
	}
}

// MARK: - Supporting Types

/// Where a map data file came from. Site Planner coverage runs are managed
/// automatically (only the newest per transmitter stays active); manual uploads
/// keep whatever visibility the user set.
enum MapDataSource: String, Codable, Sendable {
	case manualUpload
	case sitePlanner
}

/// Where and how a Site Planner estimate was computed, saved with its file so the estimate can be
/// tied back to its node and transmitter.
struct SitePlannerCoverageInfo: Codable, Equatable, Sendable {
	/// The node the estimate was run for; nil when it was run for another location.
	var nodeNum: Int64?
	var latitude: Double
	var longitude: Double
	var maxRangeKm: Double
	var txHeightMeters: Double
	var colorScale: String
	var bounds: CoverageBounds?
}

/// Metadata for uploaded map data files
struct MapDataMetadata: Codable, Identifiable {
	let id: UUID
	let filename: String
	let originalName: String
	let uploadDate: Date
	let fileSize: Int64
	let format: String
	let license: String?
	let attribution: String?
	let overlayCount: Int
	var isActive: Bool
	var source: MapDataSource
	/// The transmitter of a Site Planner estimate; nil for uploads and older planner files.
	var coverage: SitePlannerCoverageInfo?

	init(filename: String, originalName: String, uploadDate: Date, fileSize: Int64, format: String, license: String?, attribution: String?, overlayCount: Int, isActive: Bool, source: MapDataSource = .manualUpload, coverage: SitePlannerCoverageInfo? = nil) {
		self.id = UUID()
		self.filename = filename
		self.originalName = originalName
		self.uploadDate = uploadDate
		self.fileSize = fileSize
		self.format = format
		self.license = license
		self.attribution = attribution
		self.overlayCount = overlayCount
		self.isActive = isActive
		self.source = source
		self.coverage = coverage
	}

	/// Manifests written before `source` existed decode as manual uploads — every
	/// file back then came from the file picker.
	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		id = try container.decode(UUID.self, forKey: .id)
		filename = try container.decode(String.self, forKey: .filename)
		originalName = try container.decode(String.self, forKey: .originalName)
		uploadDate = try container.decode(Date.self, forKey: .uploadDate)
		fileSize = try container.decode(Int64.self, forKey: .fileSize)
		format = try container.decode(String.self, forKey: .format)
		license = try container.decodeIfPresent(String.self, forKey: .license)
		attribution = try container.decodeIfPresent(String.self, forKey: .attribution)
		overlayCount = try container.decode(Int.self, forKey: .overlayCount)
		isActive = try container.decode(Bool.self, forKey: .isActive)
		source = try container.decodeIfPresent(MapDataSource.self, forKey: .source) ?? .manualUpload
		coverage = try container.decodeIfPresent(SitePlannerCoverageInfo.self, forKey: .coverage)
	}

	var fileSizeString: String {
		let formatter = ByteCountFormatter()
		formatter.allowedUnits = [.useKB, .useMB]
		formatter.countStyle = .file
		return formatter.string(fromByteCount: fileSize)
	}
}

/// Errors that can occur during map data operations
enum MapDataError: Error, LocalizedError {
	case fileTooLarge
	case invalidFileType
	case unsupportedFormat
	case invalidContent
	case directoryCreationFailed
	case invalidDestination
	case fileNotFound
	case saveFailed
	case noMappableContent

	var errorDescription: String? {
		switch self {
		case .fileTooLarge:
			let limit = ByteCountFormatter.string(fromByteCount: MapDataManager.maxFileSize, countStyle: .memory)
			return String(localized: "File is too large. Maximum size is \(limit).")
		case .invalidFileType:
			return "Invalid file type. Please select a regular file."
		case .unsupportedFormat:
			return String(localized: "Unsupported file format. Supported formats: GeoJSON, JSON, KML and KMZ.")
		case .invalidContent:
			return String(localized: "Invalid file content. Please check the file format.")
		case .directoryCreationFailed:
			return "Failed to create storage directory."
		case .invalidDestination:
			return "Invalid destination path."
		case .fileNotFound:
			return "File not found."
		case .saveFailed:
			return "Failed to save file."
		case .noMappableContent:
			return String(localized: "This file has no points, lines, shapes or images the map can show.")
		}
	}
}

// MARK: - Notification Names
extension Foundation.Notification.Name {
	static let mapDataFileDeleted = Foundation.Notification.Name("mapDataFileDeleted")
}
