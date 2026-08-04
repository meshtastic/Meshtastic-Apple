//
//  OfflineMapImport.swift
//  Meshtastic
//

import CryptoKit
import Foundation
import UniformTypeIdentifiers

extension UTType {
	static let meshtasticPMTiles = UTType(importedAs: "gvh.MeshtasticApple.pmtiles")
	static let meshtasticMBTiles = UTType(importedAs: "gvh.MeshtasticApple.mbtiles")
}

enum OfflineMapArchiveFormat: String, Sendable {
	case pmtiles
	case mbtiles

	var fileExtension: String { rawValue }
}

// MARK: - Errors

enum OfflineMapImportError: LocalizedError {
	case unreadableFile
	case invalidHeader
	case unsupportedTileType
	case invalidBounds
	case invalidZoomRange
	case exceedsPerMapLimit
	case exceedsTotalStorageLimit
	case exceedsMapCountLimit
	case duplicateMap
	case operationInProgress

	var errorDescription: String? {
		switch self {
		case .unreadableFile:
			return String(localized: "The offline map file could not be read.")
		case .invalidHeader:
			return String(localized: "This file is not a valid PMTiles or MBTiles map.")
		case .unsupportedTileType:
			return String(localized: "This map uses a tile format that Meshtastic cannot display.")
		case .invalidBounds:
			return String(localized: "This map has invalid geographic bounds.")
		case .invalidZoomRange:
			return String(localized: "This map has an invalid zoom range.")
		case .exceedsPerMapLimit:
			return String(localized: "This map is larger than the offline-map size limit.")
		case .exceedsTotalStorageLimit:
			return String(localized: "This map would exceed the offline-map storage limit.")
		case .exceedsMapCountLimit:
			return String(localized: "Remove an offline map before importing another one.")
		case .duplicateMap:
			return String(localized: "This offline map is already installed.")
		case .operationInProgress:
			return String(localized: "Finish the current offline map operation before importing another map.")
		}
	}
}

// MARK: - Metadata

struct OfflineMapImportMetadata: Equatable, Sendable {
	let bounds: GeoBounds
	let minZoom: Int
	let maxZoom: Int
}

// MARK: - Validation

enum OfflineMapImportValidator {
	static func validate(fileURL: URL) throws -> OfflineMapImportMetadata {
		guard let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
			throw OfflineMapImportError.unreadableFile
		}
		guard let format = format(for: fileURL) else {
			throw OfflineMapImportError.invalidHeader
		}
		switch format {
		case .pmtiles:
			guard let header = PMTilesArchive.header(url: fileURL) else {
				throw OfflineMapImportError.invalidHeader
			}
			return try validate(header: header, fileSize: Int64(fileSize))
		case .mbtiles:
			guard let archive = MBTilesArchive(url: fileURL),
				archive.hasTileData,
				let bounds = archive.geographicBounds
			else {
				throw OfflineMapImportError.invalidHeader
			}
			return try validate(
				bounds: bounds,
				minZoom: Int(archive.tileMinZoom),
				maxZoom: Int(archive.tileMaxZoom),
				fileSize: Int64(fileSize)
			)
		}
	}

	static func validate(header: PMTilesHeader, fileSize: Int64) throws -> OfflineMapImportMetadata {
		guard header.tileType == .png || header.tileType == .jpeg || header.tileType == .webp || header.tileType == .mvt else {
			throw OfflineMapImportError.unsupportedTileType
		}
		return try validate(
			bounds: header.bounds,
			minZoom: Int(header.minZoom),
			maxZoom: Int(header.maxZoom),
			fileSize: fileSize
		)
	}

	static func format(for fileURL: URL) -> OfflineMapArchiveFormat? {
		OfflineMapArchiveFormat(rawValue: fileURL.pathExtension.lowercased())
	}

	private static func validate(
		bounds: GeoBounds,
		minZoom: Int,
		maxZoom: Int,
		fileSize: Int64
	) throws -> OfflineMapImportMetadata {
		guard fileSize > 0 else { throw OfflineMapImportError.unreadableFile }
		guard fileSize <= OfflineMapStorageLimits.maxRegionBytes else {
			throw OfflineMapImportError.exceedsPerMapLimit
		}
		guard minZoom <= maxZoom else {
			throw OfflineMapImportError.invalidZoomRange
		}
		guard bounds.minLon.isFinite,
			bounds.maxLon.isFinite,
			bounds.minLat.isFinite,
			bounds.maxLat.isFinite,
			bounds.minLon >= -180,
			bounds.maxLon <= 180,
			bounds.minLat >= -90,
			bounds.maxLat <= 90,
			bounds.minLon < bounds.maxLon,
			bounds.minLat < bounds.maxLat
		else { throw OfflineMapImportError.invalidBounds }
		return OfflineMapImportMetadata(
			bounds: bounds,
			minZoom: minZoom,
			maxZoom: maxZoom
		)
	}
}

// MARK: - Import Results

struct OfflineMapImportSource: Sendable {
	let fileName: String
	let fileSize: Int64
	let digest: Data
	let format: OfflineMapArchiveFormat
}

struct OfflineMapImportedArchive: Sendable {
	let metadata: OfflineMapImportMetadata
	let fileSize: Int64
	let digest: Data
}

// MARK: - Worker

enum OfflineMapImportWorker {
	static func inspectSource(at sourceURL: URL) throws -> OfflineMapImportSource {
		_ = try OfflineMapImportValidator.validate(fileURL: sourceURL)
		guard let fileSize = try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
			throw OfflineMapImportError.unreadableFile
		}
		guard let format = OfflineMapImportValidator.format(for: sourceURL) else {
			throw OfflineMapImportError.invalidHeader
		}
		return OfflineMapImportSource(
			fileName: sourceURL.deletingPathExtension().lastPathComponent,
			fileSize: Int64(fileSize),
			digest: try digest(of: sourceURL),
			format: format
		)
	}

	static func existingDigests(for urls: [URL]) -> [Data] {
		urls.compactMap { try? digest(of: $0) }
	}

	static func copyAndValidate(from sourceURL: URL, to destinationURL: URL) throws -> OfflineMapImportedArchive {
		do {
			try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
			let metadata = try OfflineMapImportValidator.validate(fileURL: destinationURL)
			guard let fileSize = try? destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
				throw OfflineMapImportError.unreadableFile
			}
			return OfflineMapImportedArchive(
				metadata: metadata,
				fileSize: Int64(fileSize),
				digest: try digest(of: destinationURL)
			)
		} catch {
			try? FileManager.default.removeItem(at: destinationURL)
			throw error
		}
	}

	private static func digest(of url: URL) throws -> Data {
		let handle = try FileHandle(forReadingFrom: url)
		defer { try? handle.close() }
		var hasher = SHA256()
		while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
			hasher.update(data: chunk)
		}
		return Data(hasher.finalize())
	}
}
