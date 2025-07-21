import Foundation
import MapKit
import OSLog

/// Manager for handling user-uploaded map data files
class MapDataManager {
    static let shared = MapDataManager()
    private init() {}

    // MARK: - Constants
    private let maxFileSize: Int64 = 10 * 1024 * 1024 // 10MB
    private let mapDataDirectory = "MapData"
    private let userUploadedDirectory = "user_uploaded"
    private let metadataFileName = "upload_history.json"

    // MARK: - Properties
    private var uploadedFiles: [MapDataMetadata] = []
    private var activeConfiguration: GeoJSONOverlayConfiguration?

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
        Logger.services.info("📁 Processing uploaded file: \(sourceURL.lastPathComponent, privacy: .public)")

        // 1. Start accessing security-scoped resource
        let isAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
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
        let metadata = try await processFileContent(at: destURL, originalName: originalName)

        // 6. Save metadata
        uploadedFiles.append(metadata)
        try saveMetadata()

        // 7. Clear cached configuration to force reload
        activeConfiguration = nil

        Logger.services.info("📁 Successfully processed file: \(newFilename, privacy: .public)")
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
        let allowedExtensions = ["json", "geojson", "kml", "kmz", "gz", "zlib"]
        let fileExtension = url.pathExtension.lowercased()
        guard allowedExtensions.contains(fileExtension) else {
            throw MapDataError.unsupportedFormat
        }
    }

    /// Process file content and extract metadata
    private func processFileContent(at url: URL, originalName: String) async throws -> MapDataMetadata {
        let fileAttributes = try url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
        let fileSize = fileAttributes.fileSize ?? 0
        let uploadDate = fileAttributes.creationDate ?? Date()

        // Read and process file content on background queue
        let (processedData, overlayCount) = try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                do {
                    let data = try Data(contentsOf: url)
                    let processedData = try self.processData(data, filename: url.lastPathComponent)
                    let overlayCount = try self.getOverlayCount(from: processedData)
                    continuation.resume(returning: (processedData, overlayCount))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        // If this is the first file uploaded, make it active by default
        let isFirstFile = uploadedFiles.isEmpty

        return MapDataMetadata(
            filename: url.lastPathComponent,
            originalName: originalName,
            uploadDate: uploadDate,
            fileSize: Int64(fileSize),
            format: url.pathExtension.lowercased(),
            license: nil, // Will be extracted from content if available
            attribution: nil, // Will be extracted from content if available
            overlayCount: overlayCount,
            isActive: isFirstFile
        )
    }

    /// Process data (decompress if needed)
    private func processData(_ data: Data, filename: String) throws -> Data {
        let fileExtension = filename.components(separatedBy: ".").last?.lowercased() ?? ""

        switch fileExtension {
        case "gz", "zlib":
            return try data.zlibDecompressed()
        default:
            return data
        }
    }

    /// Get overlay count from processed data
    private func getOverlayCount(from data: Data) throws -> Int {
        do {
            let config = try JSONDecoder().decode(GeoJSONOverlayConfiguration.self, from: data)
            return config.overlays.count
        } catch {
            // Try parsing as raw GeoJSON
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let features = json["features"] as? [[String: Any]] {
                return features.count
            }
            throw MapDataError.invalidContent
        }
    }

    // MARK: - Configuration Loading

    /// Load user configuration (priority over bundled)
    func loadUserConfiguration() -> GeoJSONOverlayConfiguration? {
        if let cached = activeConfiguration {
            return cached
        }

        // Find active user files
        let activeFiles = uploadedFiles.filter { $0.isActive }
        guard let activeFile = activeFiles.first else {
            return nil
        }

        guard let fileURL = getUserUploadedDirectory()?.appendingPathComponent(activeFile.filename) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let processedData = try processData(data, filename: activeFile.filename)
            let config = try JSONDecoder().decode(GeoJSONOverlayConfiguration.self, from: processedData)

            activeConfiguration = config
            return config
        } catch {
            Logger.services.error("📁 Failed to load user configuration: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - File Management

    /// Get all uploaded files
    func getUploadedFiles() -> [MapDataMetadata] {
        return uploadedFiles
    }

    /// Delete uploaded file
    func deleteFile(_ metadata: MapDataMetadata) throws {
        guard let fileURL = getUserUploadedDirectory()?.appendingPathComponent(metadata.filename) else {
            throw MapDataError.fileNotFound
        }

        try FileManager.default.removeItem(at: fileURL)

        if let index = uploadedFiles.firstIndex(where: { $0.filename == metadata.filename }) {
            uploadedFiles.remove(at: index)
        }

        try saveMetadata()

        // Clear cache if this was the active file
        if activeConfiguration != nil {
            activeConfiguration = nil
        }

        Logger.services.info("🗑️ Deleted file: \(metadata.filename, privacy: .public)")
    }

        /// Toggle file active status
    func toggleFileActive(_ metadata: MapDataMetadata) throws {
        if let index = uploadedFiles.firstIndex(where: { $0.filename == metadata.filename }) {
            let newActiveState = !uploadedFiles[index].isActive

            // If making this file active, deactivate all others (only one can be active)
            if newActiveState {
                for i in uploadedFiles.indices {
                    uploadedFiles[i].isActive = (i == index)
                }
            } else {
                // Just deactivate this file
                uploadedFiles[index].isActive = false
            }

            try saveMetadata()

            // Clear cache to force reload
            activeConfiguration = nil
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

    var uploadDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: uploadDate)
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
            return "Invalid file content. Please check the file format."
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