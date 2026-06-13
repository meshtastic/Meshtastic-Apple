import Foundation
import MapKit
import OSLog
import Combine

/// Manager for handling user-uploaded map data files
class MapDataManager: ObservableObject {
	static let shared = MapDataManager()
	private init() {}

	// MARK: - Constants
	private let maxFileSize: Int64 = 10 * 1024 * 1024 // 10MB
	private let mapDataDirectory = "MapData"
	private let userUploadedDirectory = "user_uploaded"
	private let metadataFileName = "upload_history.json"

	// MARK: - Properties
	@Published private var uploadedFiles: [MapDataMetadata] = []
	private var activeFeatureCollection: GeoJSONFeatureCollection?

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
	func processUploadedFile(from sourceURL: URL) async throws -> MapDataMetadata {

		// 1. Start accessing security-scoped resource
		let isAccessing = sourceURL.startAccessingSecurityScopedResource()
		defer {
			if isAccessing {
				sourceURL.stopAccessingSecurityScopedResource()
			}
		}

		// 2. Validate file
		try validateFile(at: sourceURL)

		let originalName = sourceURL.deletingPathExtension().lastPathComponent
		let data = try Data(contentsOf: sourceURL)
		return try await processGeoJSONData(
			data,
			originalName: originalName,
			fileExtension: sourceURL.pathExtension,
			makeActive: uploadedFiles.isEmpty
		)
	}

	/// Process and store GeoJSON data from a remote source such as Meshtastic Site Planner contours.
	func processGeoJSONData(_ data: Data, originalName: String, fileExtension: String = "geojson", makeActive: Bool = true) async throws -> MapDataMetadata {
		guard Int64(data.count) <= maxFileSize else {
			throw MapDataError.fileTooLarge
		}

		guard createDirectoriesIfNeeded() else {
			throw MapDataError.directoryCreationFailed
		}

		let normalizedData: Data
		do {
			normalizedData = try SitePlannerCoverageClient.normalizedFeatureCollectionData(from: data)
		} catch SitePlannerCoverageError.missingFeatureCollection {
			throw MapDataError.invalidContent
		}
		_ = try getOverlayCount(from: normalizedData)

		let timestamp = Date().timeIntervalSince1970
		let sanitizedName = sanitizedFilenameComponent(originalName)
		let sanitizedExtension = sanitizedFileExtension(fileExtension)
		let newFilename = "\(sanitizedName)_\(Int(timestamp)).\(sanitizedExtension)"

		guard let destURL = getUserUploadedDirectory()?.appendingPathComponent(newFilename) else {
			throw MapDataError.invalidDestination
		}

		try normalizedData.write(to: destURL, options: .atomic)

		let metadata = try await processFileContent(at: destURL, originalName: originalName, makeActive: makeActive)

		await MainActor.run {
			uploadedFiles.append(metadata)
			activeFeatureCollection = nil
		}
		try saveMetadata()
		GeoJSONOverlayManager.shared.clearCache()
		await MainActor.run {
			NotificationCenter.default.post(name: Foundation.Notification.Name.mapDataFileImported, object: metadata.id)
		}

		return metadata
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
	private func processFileContent(at url: URL, originalName: String, makeActive: Bool) async throws -> MapDataMetadata {
		let fileAttributes = try url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
		let fileSize = fileAttributes.fileSize ?? 0
		let uploadDate = fileAttributes.creationDate ?? Date()

		let data = try Data(contentsOf: url)
		let overlayCount = try getOverlayCount(from: data)

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
				  geometry["coordinates"] is [Any],
				  geometry["type"] is String else {
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
			isActive: makeActive
		)
	}

	/// Get overlay count from raw GeoJSON data
	private func getOverlayCount(from data: Data) throws -> Int {
		// Parse as raw GeoJSON FeatureCollection
		if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
		   let features = json["features"] as? [[String: Any]] {
			return features.count
		}
		throw MapDataError.invalidContent
	}

	private func sanitizedFilenameComponent(_ value: String) -> String {
		let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
		let sanitized = value.unicodeScalars.map { scalar in
			allowedCharacters.contains(scalar) ? String(scalar) : "_"
		}
		.joined()
		.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
		return sanitized.isEmpty ? "map_overlay" : sanitized
	}

	private func sanitizedFileExtension(_ value: String) -> String {
		let lowercased = value.lowercased()
		let allowedExtensions = ["json", "geojson"]
		return allowedExtensions.contains(lowercased) ? lowercased : "geojson"
	}

	/// Load feature collection from a single file
	private func loadFeatureCollectionFromFile(_ file: MapDataMetadata) throws -> GeoJSONFeatureCollection? {
		guard let fileURL = getUserUploadedDirectory()?.appendingPathComponent(file.filename) else {
			throw MapDataError.fileNotFound
		}

		let data = try Data(contentsOf: fileURL)
		return try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: data)
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
				let featureCollection = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: data)

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

		// Update UI-related properties on main thread
		await MainActor.run {
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

	init(filename: String, originalName: String, uploadDate: Date, fileSize: Int64, format: String, license: String?, attribution: String?, overlayCount: Int, isActive: Bool) {
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

	var errorDescription: String? {
		switch self {
		case .fileTooLarge:
			return "File is too large. Maximum size is 10MB."
		case .invalidFileType:
			return "Invalid file type. Please select a regular file."
		case .unsupportedFormat:
			return "Unsupported file format. Supported formats: JSON, GeoJSON, KML, KMZ, GZ, ZLIB."
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
		}
	}
}

// MARK: - Notification Names
extension Foundation.Notification.Name {
	static let mapDataFileDeleted = Foundation.Notification.Name("mapDataFileDeleted")
	static let mapDataFileImported = Foundation.Notification.Name("mapDataFileImported")
}

struct SitePlannerCoverageClient: Sendable {
	var session: URLSession = .shared
	var pollIntervalNanoseconds: UInt64 = 1_000_000_000
	var timeoutInterval: TimeInterval = 180

	func generateContours(from sitePlannerURL: URL, request payload: SitePlannerCoverageRequest) async throws -> Data {
		try await generateCoverage(from: sitePlannerURL, request: payload)
	}

	func generateCoverage(from sitePlannerURL: URL, request payload: SitePlannerCoverageRequest) async throws -> Data {
		let predictURL = Self.predictURL(from: sitePlannerURL)
		var request = URLRequest(url: predictURL)
		request.httpMethod = "POST"
		request.timeoutInterval = timeoutInterval
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("application/geo+json, application/json, image/tiff", forHTTPHeaderField: "Accept")
		request.httpBody = try JSONEncoder().encode(payload)

		let (data, _) = try await data(for: request)
		if let normalizedData = try? Self.normalizedFeatureCollectionData(from: data) {
			return normalizedData
		}

		let prediction = try JSONDecoder().decode(SitePlannerPredictionResponse.self, from: data)
		return try await pollCoverageResult(taskID: prediction.taskId, baseURL: Self.baseURL(from: sitePlannerURL))
	}

	static func normalizedFeatureCollectionData(from data: Data) throws -> Data {
		let jsonObject = try JSONSerialization.jsonObject(with: data)
		guard let featureCollection = findFeatureCollection(in: jsonObject) else {
			throw SitePlannerCoverageError.missingFeatureCollection
		}

		let normalizedData = try JSONSerialization.data(withJSONObject: featureCollection, options: [])
		_ = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: normalizedData)
		return normalizedData
	}

	private static func findFeatureCollection(in object: Any) -> [String: Any]? {
		if let dictionary = object as? [String: Any] {
			if dictionary["type"] as? String == "FeatureCollection",
			   dictionary["features"] is [[String: Any]] {
				return dictionary
			}

			let preferredKeys = ["geojson", "contours", "featureCollection", "coverage", "data", "result"]
			for key in preferredKeys {
				if let value = dictionary[key],
				   let featureCollection = findFeatureCollection(in: value) {
					return featureCollection
				}
			}

			for value in dictionary.values {
				if let featureCollection = findFeatureCollection(in: value) {
					return featureCollection
				}
			}
		}

		if let features = object as? [[String: Any]],
		   !features.isEmpty,
		   features.allSatisfy(isGeoJSONFeature) {
			return ["type": "FeatureCollection", "features": features]
		}

		return nil
	}

	private static func isGeoJSONFeature(_ object: [String: Any]) -> Bool {
		object["type"] as? String == "Feature" && object["geometry"] is [String: Any]
	}

	private static func responseSnippet(from data: Data) -> String? {
		guard let string = String(data: data, encoding: .utf8)?
			.trimmingCharacters(in: .whitespacesAndNewlines),
			  !string.isEmpty else {
			return nil
		}
		return String(string.prefix(240))
	}

	private func pollCoverageResult(taskID: String, baseURL: URL) async throws -> Data {
		let deadline = Date().addingTimeInterval(timeoutInterval)
		while true {
			let statusURL = baseURL.appendingPathComponent("status").appendingPathComponent(taskID)
			var statusRequest = URLRequest(url: statusURL)
			statusRequest.timeoutInterval = timeoutInterval
			statusRequest.setValue("application/json", forHTTPHeaderField: "Accept")

			let (statusData, _) = try await data(for: statusRequest)
			let statusResponse = try JSONDecoder().decode(SitePlannerStatusResponse.self, from: statusData)
			switch statusResponse.status.lowercased() {
			case "completed", "complete", "done", "success":
				return try await fetchCoverageResult(taskID: taskID, baseURL: baseURL)
			case "failed", "error":
				throw SitePlannerCoverageError.failed(statusResponse.error)
			case "processing", "pending", "running", "queued":
				break
			default:
				throw SitePlannerCoverageError.unexpectedStatus(statusResponse.status)
			}

			guard Date() < deadline else {
				throw SitePlannerCoverageError.timeout
			}
			try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
		}
	}

	private func fetchCoverageResult(taskID: String, baseURL: URL) async throws -> Data {
		let resultURL = baseURL.appendingPathComponent("result").appendingPathComponent(taskID)
		var request = URLRequest(url: resultURL)
		request.timeoutInterval = timeoutInterval
		request.setValue("application/geo+json, application/json, image/tiff", forHTTPHeaderField: "Accept")

		let (data, response) = try await data(for: request)
		if let normalizedData = try? Self.normalizedFeatureCollectionData(from: data) {
			return normalizedData
		}
		if Self.isTIFF(data: data, response: response) {
			throw SitePlannerCoverageError.unsupportedGeoTIFFResult
		}
		throw SitePlannerCoverageError.missingFeatureCollection
	}

	private func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
		let (data, response) = try await session.data(for: request)
		guard let httpResponse = response as? HTTPURLResponse else {
			throw SitePlannerCoverageError.invalidResponse
		}
		guard (200...299).contains(httpResponse.statusCode) else {
			if httpResponse.statusCode == 405,
			   request.url?.host?.lowercased() == "site.meshtastic.org" {
				throw SitePlannerCoverageError.publicSiteAPIUnavailable
			}
			throw SitePlannerCoverageError.httpStatus(httpResponse.statusCode, Self.responseSnippet(from: data))
		}
		return (data, httpResponse)
	}

	private static func predictURL(from sitePlannerURL: URL) -> URL {
		if sitePlannerURL.lastPathComponent.lowercased() == "predict" {
			return sitePlannerURL
		}
		return sitePlannerURL.appendingPathComponent("predict")
	}

	private static func baseURL(from sitePlannerURL: URL) -> URL {
		var baseURL = sitePlannerURL
		if baseURL.lastPathComponent.lowercased() == "predict" {
			baseURL.deleteLastPathComponent()
		}
		return baseURL
	}

	private static func isTIFF(data: Data, response: HTTPURLResponse) -> Bool {
		let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased()
		if contentType?.contains("image/tiff") == true || contentType?.contains("image/geotiff") == true {
			return true
		}

		return data.starts(with: Data([0x49, 0x49, 0x2A, 0x00])) || data.starts(with: Data([0x4D, 0x4D, 0x00, 0x2A]))
	}
}

private struct SitePlannerPredictionResponse: Decodable {
	var taskId: String

	enum CodingKeys: String, CodingKey {
		case taskId = "task_id"
	}
}

private struct SitePlannerStatusResponse: Decodable {
	var status: String
	var error: String?
}

/// Meshtastic Site Planner's legacy coverage request shape.
///
/// This mirrors the Site Planner request fields used by the current local
/// engine and the earlier `/predict` FastAPI backend.
struct SitePlannerCoverageRequest: Codable, Equatable, Sendable {
	var lat: Double
	var lon: Double
	var txHeight: Double
	var txPower: Double
	var txGain: Double
	var systemLoss: Double
	var frequencyMHz: Double
	var rxHeight: Double
	var rxGain: Double
	var signalThreshold: Double
	var clutterHeight: Double
	var groundDielectric: Double
	var groundConductivity: Double
	var atmosphereBending: Double
	var radioClimate: String
	var polarization: String
	var radius: Double
	var situationFraction: Double
	var timeFraction: Double
	var highResolution: Bool
	var colormap: String
	var minDbm: Double
	var maxDbm: Double

	enum CodingKeys: String, CodingKey {
		case lat
		case lon
		case txHeight = "tx_height"
		case txPower = "tx_power"
		case txGain = "tx_gain"
		case systemLoss = "system_loss"
		case frequencyMHz = "frequency_mhz"
		case rxHeight = "rx_height"
		case rxGain = "rx_gain"
		case signalThreshold = "signal_threshold"
		case clutterHeight = "clutter_height"
		case groundDielectric = "ground_dielectric"
		case groundConductivity = "ground_conductivity"
		case atmosphereBending = "atmosphere_bending"
		case radioClimate = "radio_climate"
		case polarization
		case radius
		case situationFraction = "situation_fraction"
		case timeFraction = "time_fraction"
		case highResolution = "high_resolution"
		case colormap
		case minDbm = "min_dbm"
		case maxDbm = "max_dbm"
	}

	init(
		lat: Double,
		lon: Double,
		txHeight: Double = 2.0,
		txPower: Double = 20.0,
		txGain: Double = 2.0,
		systemLoss: Double = 2.0,
		frequencyMHz: Double = 907.0,
		rxHeight: Double = 1.0,
		rxGain: Double = 2.0,
		signalThreshold: Double = -130.0,
		clutterHeight: Double = 1.0,
		groundDielectric: Double = 15.0,
		groundConductivity: Double = 0.005,
		atmosphereBending: Double = 301.0,
		radioClimate: String = "continental_temperate",
		polarization: String = "vertical",
		radius: Double = 30_000.0,
		situationFraction: Double = 95.0,
		timeFraction: Double = 95.0,
		highResolution: Bool = false,
		colormap: String = "plasma",
		minDbm: Double = -130.0,
		maxDbm: Double = -80.0
	) {
		self.lat = lat
		self.lon = lon
		self.txHeight = txHeight
		self.txPower = txPower
		self.txGain = txGain
		self.systemLoss = systemLoss
		self.frequencyMHz = frequencyMHz
		self.rxHeight = rxHeight
		self.rxGain = rxGain
		self.signalThreshold = signalThreshold
		self.clutterHeight = clutterHeight
		self.groundDielectric = groundDielectric
		self.groundConductivity = groundConductivity
		self.atmosphereBending = atmosphereBending
		self.radioClimate = radioClimate
		self.polarization = polarization
		self.radius = radius
		self.situationFraction = situationFraction
		self.timeFraction = timeFraction
		self.highResolution = highResolution
		self.colormap = colormap
		self.minDbm = minDbm
		self.maxDbm = maxDbm
	}
}

enum SitePlannerCoverageError: Error, LocalizedError {
	case missingEndpoint
	case invalidResponse
	case publicSiteAPIUnavailable
	case httpStatus(Int, String?)
	case failed(String?)
	case timeout
	case unexpectedStatus(String)
	case missingFeatureCollection
	case unsupportedGeoTIFFResult

	var errorDescription: String? {
		switch self {
		case .missingEndpoint:
			return "Enter a Site Planner URL before generating coverage. Hosted Site Planner APIs should expose /predict, /status/{task_id}, and /result/{task_id}."
		case .invalidResponse:
			return "Site Planner returned an invalid response."
		case .publicSiteAPIUnavailable:
			return "The public Site Planner website returned HTTP 405 for /predict. Enter a hosted Site Planner API URL that exposes /predict, /status/{task_id}, and /result/{task_id}."
		case .httpStatus(let statusCode, let responseBody):
			if let responseBody {
				return "Site Planner request failed with HTTP \(statusCode): \(responseBody)"
			}
			return "Site Planner request failed with HTTP \(statusCode)."
		case .failed(let message):
			if let message, !message.isEmpty {
				return "Site Planner prediction failed: \(message)"
			}
			return "Site Planner prediction failed."
		case .timeout:
			return "Site Planner prediction timed out before a result was ready."
		case .unexpectedStatus(let status):
			return "Site Planner returned an unexpected prediction status: \(status)."
		case .missingFeatureCollection:
			return "Site Planner response did not contain GeoJSON contours."
		case .unsupportedGeoTIFFResult:
			return "Site Planner returned a GeoTIFF raster result. Map coverage generation currently imports GeoJSON contours; use a Site Planner API result that returns GeoJSON."
		}
	}
}
