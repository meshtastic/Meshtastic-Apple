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
		guard let fetchedNode = try context.fetch(fetchNodeInfoRequest) as? [NodeInfoEntity] else {
			return nil
		}
		if fetchedNode.count == 1 {
			return fetchedNode[0]
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
		guard let fetchedUser = try context.fetch(fetchUserRequest) as? [UserEntity] else {
			return UserEntity(context: context)
		}
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
		guard let fetchedWaypoint = try context.fetch(fetchWaypointRequest) as? [WaypointEntity] else {
			return WaypointEntity(context: context)
		}
		if fetchedWaypoint.count == 1 {
			return fetchedWaypoint[0]
		}
	} catch {
		return WaypointEntity(context: context)
	}
	return WaypointEntity(context: context)
}

public func getDetectionSensorMessages(nodeNum: Int64?, context: NSManagedObjectContext) -> [MessageEntity] {

	let fetchDetectionMessagesPredicate: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "MessageEntity")
	fetchDetectionMessagesPredicate.predicate = NSPredicate(format: "portNum == %d", Int32(PortNum.detectionSensorApp.rawValue))

	do {
		let fetched = try context.fetch(fetchDetectionMessagesPredicate) as? [MessageEntity] ?? []
		if nodeNum == nil {
			return fetched.reversed()
		}
		return fetched.filter { message in
			return message.fromUser?.num == nodeNum!
		}.reversed()
	} catch {
		return []
	}
}
