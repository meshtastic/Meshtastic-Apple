//
//  QueryCoreData.swift
//  Meshtastic
//
//  Created(c) Garth Vander Houwen 1/16/23.
//

import CoreData

public func getWaypoint(id: Int64, context: NSManagedObjectContext) -> WaypointEntity {
	
	let fetchWaypointRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "WaypointEntity")
	fetchWaypointRequest.predicate = NSPredicate(format: "id == %lld", Int64(id))
	
	do {
		let fetchedWaypoint = try context.fetch(fetchWaypointRequest) as! [WaypointEntity]
		if fetchedWaypoint.count == 1 {
			return fetchedWaypoint[0]
		}
	} catch {
		return WaypointEntity()
	}
	return WaypointEntity()
}
