//
//  NodeDetailItem.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 9/8/23.
//

import SwiftUI
import WeatherKit
import MapKit
import CoreLocation

struct NodeDetailItem: View {
	
	var node: NodeInfoEntity
	@FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: false)],
				  predicate: NSPredicate(
					format: "expire == nil || expire >= %@", Date() as NSDate
				  ), animation: .none)
	private var waypoints: FetchedResults<WaypointEntity>
	

	
	var body: some View {

		NavigationStack {
			
		}
	}
}
