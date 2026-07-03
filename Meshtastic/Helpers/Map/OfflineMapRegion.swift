//
//  OfflineMapRegion.swift
//  Meshtastic
//
//  A downloaded offline map area, extracted from the Protomaps basemap into a
//  local `.pmtiles` archive in the app's Documents folder. Persisted as Codable
//  JSON in a manifest (see `OfflineMapManager`) rather than SwiftData, mirroring
//  the file-backed pattern used for user-imported map overlays.
//

import Foundation
import MapKit

/// Metadata describing one downloaded offline map region. The geometry is stored
/// as four doubles (Codable-friendly); `bounds`/`region` expose the map types.
struct OfflineMapRegion: Identifiable, Codable, Hashable {
	let id: UUID
	var name: String
	/// File name of the extracted archive within the offline maps directory, e.g. `"<uuid>.pmtiles"`.
	var fileName: String
	var minLongitude: Double
	var minLatitude: Double
	var maxLongitude: Double
	var maxLatitude: Double
	var minZoom: Int
	var maxZoom: Int
	var fileSize: Int64
	var createdDate: Date
	var updatedDate: Date
	/// Protomaps daily build the tiles were extracted from, e.g. `"20260623"`.
	var sourceBuild: String

	init(
		id: UUID = UUID(),
		name: String,
		fileName: String,
		bounds: GeoBounds,
		minZoom: Int,
		maxZoom: Int,
		fileSize: Int64,
		createdDate: Date = .now,
		updatedDate: Date = .now,
		sourceBuild: String
	) {
		self.id = id
		self.name = name
		self.fileName = fileName
		self.minLongitude = bounds.minLon
		self.minLatitude = bounds.minLat
		self.maxLongitude = bounds.maxLon
		self.maxLatitude = bounds.maxLat
		self.minZoom = minZoom
		self.maxZoom = maxZoom
		self.fileSize = fileSize
		self.createdDate = createdDate
		self.updatedDate = updatedDate
		self.sourceBuild = sourceBuild
	}

	var bounds: GeoBounds {
		GeoBounds(minLon: minLongitude, minLat: minLatitude, maxLon: maxLongitude, maxLat: maxLatitude)
	}

	/// A coordinate region that frames this area, for previews and "show on map".
	var region: MKCoordinateRegion {
		let center = CLLocationCoordinate2D(
			latitude: (minLatitude + maxLatitude) / 2,
			longitude: (minLongitude + maxLongitude) / 2
		)
		let span = MKCoordinateSpan(
			latitudeDelta: max(maxLatitude - minLatitude, 0.01),
			longitudeDelta: max(maxLongitude - minLongitude, 0.01)
		)
		return MKCoordinateRegion(center: center, span: span)
	}

	var formattedSize: String {
		ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
	}
}
