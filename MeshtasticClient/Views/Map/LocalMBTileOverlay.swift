//
//  LocalMBTileOverlay.swift
//  MeshtasticClient
//
//  Created by Joshua Pirihi on 16/01/22.
//

import UIKit
import MapKit
import SQLite

class LocalMBTileOverlay: MKTileOverlay {

	var path: String!
	
	var mb: Connection!
	
	init(mbTilePath path: String) {
		
		super.init(urlTemplate: nil)
		self.path = path
		
		do {
			self.mb = try Connection(self.path, readonly: true)
			let metadata = Table("metadata")
			
			let name = Expression<String>("name")
			let value = Expression<String>("value")
			
			let minZQuery = try mb.pluck(metadata.select(value).filter(name == "minzoom"))
			self.minimumZ = Int(minZQuery![value])!
			
			let maxZQuery = try mb.pluck(metadata.select(value).filter(name == "maxzoom"))
			self.maximumZ = Int(maxZQuery![value])!
			
			self.isGeometryFlipped = true
			
			//let boundingBoxString = try mb.pluck(metadata.select(value).filter(name == "bounds"))
			//let boundCoords = boundingBoxString![value].split(separator: ",")
			//self.boundingMapRect = MKMapRect(coordinates: [CLLocationCoordinate2D(latitude: Double(boundCoords[0]) ?? 0, longitude: Double(boundCoords[1]) ?? 0), CLLocationCoordinate2D(latitude: Double(boundCoords[2]) ?? 0, longitude: Double(boundCoords[3]) ?? 0)])
			
			
		} catch {
			
		}
		
		
	}
	
	override func loadTile(at path: MKTileOverlayPath) async throws -> Data {
		
		let tileX = Int64(path.x)
		let tileY = Int64(path.y)
		let tileZ = Int64(path.z) 
		
		let tileData = Expression<SQLite.Blob>("tile_data")
		let zoomLevel = Expression<Int64>("zoom_level")
		let tileColumn = Expression<Int64>("tile_column")
		let tileRow = Expression<Int64>("tile_row")
		
		if let dataQuery = try self.mb.pluck(Table("tiles").select(tileData).filter(zoomLevel == tileZ).filter(tileColumn == tileX).filter(tileRow == tileY)) {
		
			let data = Data(bytes: dataQuery[tileData].bytes, count: dataQuery[tileData].bytes.count)//dataQuery![tileData].bytes
		
			return data
			
		} else {
			return Data()
		}
	}
	
}
