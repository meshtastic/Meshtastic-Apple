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

/// Elevation data downloaded alongside a region: Mapterhorn terrain extracts of
/// the same bounding box. Absent for regions downloaded before terrain support.
struct OfflineMapTerrain: Codable, Hashable {
	/// File name of the global (z0–12) terrain extract, e.g. `"<uuid>-terrain.pmtiles"`.
	var fileName: String
	/// File name of the optional high-resolution regional extract, e.g. `"<uuid>-terrain-hi.pmtiles"`.
	var regionalFileName: String?
	/// Combined size of the terrain archives on disk.
	var byteCount: Int64
	/// When the terrain extract finished; drives cache invalidation.
	var downloadedAt: Date
	/// Highest zoom level with terrain data: 12 when global-only, higher with a regional extract.
	var maxZoom: Int
}

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
	/// Terrain elevation extracts for the same bounds, when downloaded.
	/// Optional and additive: manifests written before terrain support decode with `nil`.
	var terrain: OfflineMapTerrain?

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
		sourceBuild: String,
		terrain: OfflineMapTerrain? = nil
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
		self.terrain = terrain
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

	/// The terrain component's size for display, or nil when no terrain is downloaded.
	var formattedTerrainSize: String? {
		terrain.map { ByteCountFormatter.string(fromByteCount: $0.byteCount, countStyle: .file) }
	}

	/// Whether this archive's zoom range covers what the map actually needs, or leaves a gap the
	/// user will see as blank/blurry basemap. Imported archives (unlike the app's own z0-based
	/// downloads) can carry any range, so this is advisory only — a narrow range is a legitimate
	/// regional export, not a corrupt file, and is never rejected on import.
	var zoomCoverage: OfflineMapZoomCoverage {
		OfflineMapZoomCoverage(minZoom: minZoom, maxZoom: maxZoom)
	}
}

/// Advisory assessment of an offline map's zoom range against the levels the app renders at.
enum OfflineMapZoomCoverage: Equatable {
	/// Covers overview through detail — no warning.
	case full
	/// Tops out below street-level detail; zooming in to a node shows no basemap detail.
	case limitedDetail(maxZoom: Int)
	/// Starts above the overview levels; zooming out shows blank basemap.
	case limitedOverview(minZoom: Int)
	/// Both ends are missing.
	case limited(minZoom: Int, maxZoom: Int)

	/// Highest zoom at or below which street-level detail is expected. The app's own "standard"
	/// download reaches z13; z10 is roughly metro/arterial-road level and the point below which an
	/// imported basemap stops being useful for locating a node.
	static let detailFloor = 10
	/// Lowest zoom the archive must include to have zoomed-out context; the app always downloads
	/// from z0, so anything starting above z6 (sub-continental) loses the pan-out view.
	static let overviewCeiling = 6

	init(minZoom: Int, maxZoom: Int) {
		let missingDetail = maxZoom < Self.detailFloor
		let missingOverview = minZoom > Self.overviewCeiling
		switch (missingOverview, missingDetail) {
		case (false, false): self = .full
		case (false, true): self = .limitedDetail(maxZoom: maxZoom)
		case (true, false): self = .limitedOverview(minZoom: minZoom)
		case (true, true): self = .limited(minZoom: minZoom, maxZoom: maxZoom)
		}
	}

	/// True when the user should be warned; `.full` is the only silent case.
	var isLimited: Bool { self != .full }

	/// A short, human caption for the map row/detail, or nil when coverage is full.
	var warningLabel: String? {
		switch self {
		case .full:
			return nil
		case .limitedDetail:
			return String(localized: "Limited detail — no close-up basemap", comment: "Offline map warning: archive lacks high zoom levels")
		case .limitedOverview:
			return String(localized: "Limited overview — no zoomed-out basemap", comment: "Offline map warning: archive lacks low zoom levels")
		case .limited:
			return String(localized: "Limited zoom coverage", comment: "Offline map warning: archive lacks both low and high zoom levels")
		}
	}
}

/// An on-disk archive paired with the region metadata that describes it.
struct OfflineMapRegionFile: Equatable {
	let region: OfflineMapRegion
	let url: URL
}
