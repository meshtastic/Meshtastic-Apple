//
//  SpatialTerrainDownload.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/12/26.
//
import Foundation

/// What a terrain download for the spatial map's box has to do, given the offline regions
/// already on the device. Offline regions must not overlap, so the download either adds terrain
/// to the region that is there or replaces it.
enum SpatialTerrainDownloadPlan: Equatable {
	/// A region with terrain already reaches into the box, even if only partly.
	case covered
	/// A basemap region without terrain overlaps the box: download terrain for that region.
	case addTerrain(regionID: UUID)
	/// A region with neither basemap nor terrain overlaps the box: replace it with a
	/// terrain-only region for the box.
	case replace(regionID: UUID)
	/// Nothing overlaps: download a new terrain-only region for the box.
	case newRegion
	/// Several terrain-less regions without a basemap overlap the box; one download cannot
	/// replace them all.
	case unavailable

	static func make(box: GeoBounds, regions: [OfflineMapRegion]) -> SpatialTerrainDownloadPlan {
		// Edges that only touch count as overlapping, the same rule OfflineMapManager uses to refuse a download.
		let overlapping = regions.filter { region in
			region.bounds.minLon <= box.maxLon && region.bounds.maxLon >= box.minLon
				&& region.bounds.minLat <= box.maxLat && region.bounds.maxLat >= box.minLat
		}
		if overlapping.contains(where: { $0.terrain != nil }) { return .covered }
		if let basemap = overlapping.first(where: \.hasBasemap) { return .addTerrain(regionID: basemap.id) }
		switch overlapping.count {
		case 0: return .newRegion
		case 1: return .replace(regionID: overlapping[0].id)
		default: return .unavailable
		}
	}

	var canDownload: Bool {
		switch self {
		case .addTerrain, .replace, .newRegion: return true
		case .covered, .unavailable: return false
		}
	}
}

extension GeoBounds {
	/// Width and height in meters, measured across the middle of the box.
	var sizeInMeters: (width: Double, height: Double) {
		let frame = SpatialFrame(bounds: self)
		return ((maxLon - minLon) * frame.metersPerDegreeLongitude, (maxLat - minLat) * SpatialFrame.metersPerDegreeLatitude)
	}
}
