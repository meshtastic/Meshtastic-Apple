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

public func getStoreAndForwardMessageIds(seconds: Int, context: NSManagedObjectContext) -> [UInt32] {
	
	let time = seconds * -1
	let fetchMessagesRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "MessageEntity")
	let timeRange = Calendar.current.date(byAdding: .minute, value: time, to: Date())
	let milleseconds = Int32(timeRange?.timeIntervalSince1970 ?? 0)
	fetchMessagesRequest.predicate =  NSPredicate(format: "receivedTimestamp >= %d", milleseconds)

	do {
		guard let fetchedMessages = try context.fetch(fetchMessagesRequest) as? [MessageEntity] else {
			return []
		}
		if fetchedMessages.count == 1 {
			return fetchedMessages.map { UInt32($0.messageId) }
		}
	} catch {
		return []
	}
	return []
}

public func getTraceRoute(id: Int64, context: NSManagedObjectContext) -> TraceRouteEntity? {

	let fetchTraceRouteRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "TraceRouteEntity")
	fetchTraceRouteRequest.predicate = NSPredicate(format: "id == %lld", Int64(id))

	do {
		guard let fetchedTraceRoute = try context.fetch(fetchTraceRouteRequest) as? [TraceRouteEntity] else {
			return nil
		}
		if fetchedTraceRoute.count == 1 {
			return fetchedTraceRoute[0]
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
