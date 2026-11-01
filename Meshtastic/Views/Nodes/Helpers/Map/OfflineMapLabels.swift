//
//  OfflineMapLabels.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/31/26.
//

import MapKit

/// Which of the offline map's place and water names to show on the map. With no network the Apple
/// map has no names to draw, so the downloaded basemap's own are shown over it: the most important
/// first, at most one in each cell of a grid over the view, so they never pile up.
enum OfflineMapLabels {
	/// The grid over the visible region: one name per cell, so at most `columns × rows` on screen.
	static let columns = 5
	static let rows = 8

	/// The names to show in `region` at `zoom`, from labels already in `OfflineMapLabel.ranked` order: those meant to
	/// show at this zoom, the first in each grid cell.
	static func visible(_ ranked: [OfflineMapLabel], in region: MKCoordinateRegion, zoom: Double) -> [OfflineMapLabel] {
		let minLat = region.center.latitude - region.span.latitudeDelta / 2
		let minLon = region.center.longitude - region.span.longitudeDelta / 2
		let cellLat = region.span.latitudeDelta / Double(rows)
		let cellLon = region.span.longitudeDelta / Double(columns)
		guard cellLat > 0, cellLon > 0 else { return [] }
		var taken = Set<Int>()
		var result: [OfflineMapLabel] = []
		for label in ranked where label.minZoom <= zoom {
			let row = Int(((label.coordinate.latitude - minLat) / cellLat).rounded(.down))
			let column = Int(((label.coordinate.longitude - minLon) / cellLon).rounded(.down))
			guard (0..<rows).contains(row), (0..<columns).contains(column), taken.insert(row * columns + column).inserted else { continue }
			result.append(label)
			if result.count == rows * columns { break }
		}
		return result
	}
}
