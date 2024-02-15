//
//  TileOverlay.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 5/5/23.
//

import Foundation
import MapKit

typealias TileCoordinates = (x: Int, y: Int, z: Int)

class TileOverlay: MKTileOverlay {
	override func loadTile(at path: MKTileOverlayPath) async throws -> Data {
		return try OfflineTileManager.shared.loadAndCacheTileOverlay(for: path)
	}
}
