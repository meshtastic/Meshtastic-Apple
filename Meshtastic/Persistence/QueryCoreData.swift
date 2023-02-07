//
//  QueryCoreData.swift
//  Meshtastic
//
//  Created(c) Garth Vander Houwen 1/16/23.
//

import CoreData

public func getNodeInfo(id: Int64, context: NSManagedObjectContext) -> NodeInfoEntity? {
	
	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(id))
	
	do {
		let fetchNodeInfo = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
		if fetchNodeInfo.count == 1 {
			return fetchNodeInfo[0]
		}
	} catch {
		return nil
	}
	return nil
}

public func getUser(id: Int64, context: NSManagedObjectContext) -> UserEntity {
	
	let fetchUserRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "UserEntity")
	fetchUserRequest.predicate = NSPredicate(format: "num == %lld", Int64(id))
	
	do {
		let fetchedUser = try context.fetch(fetchUserRequest) as! [UserEntity]
		if fetchedUser.count == 1 {
			return fetchedUser[0]
		}
	} catch {
		return UserEntity(context: context)
	}
	return UserEntity(context: context)
}

public func getWaypoint(id: Int64, context: NSManagedObjectContext) -> WaypointEntity {
	
	let fetchWaypointRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "WaypointEntity")
	fetchWaypointRequest.predicate = NSPredicate(format: "id == %lld", Int64(id))
	
	do {
		let fetchedWaypoint = try context.fetch(fetchWaypointRequest) as! [WaypointEntity]
		if fetchedWaypoint.count == 1 {
			return fetchedWaypoint[0]
		}
	} catch {
		return WaypointEntity(context: context)
	}
	return WaypointEntity(context: context)
}
