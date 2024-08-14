//
//  QueryCoreData.swift
//  Meshtastic
//
//  Created(c) Garth Vander Houwen 1/16/23.
//

import CoreData

public func getNodeInfo(id: Int64, context: NSManagedObjectContext) -> NodeInfoEntity? {

	let fetchNodeInfoRequest = NodeInfoEntity.fetchRequest()
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(id))

	do {
		let fetchedNode = try context.fetch(fetchNodeInfoRequest)
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
	let fetchMessagesRequest = MessageEntity.fetchRequest()
	let timeRange = Calendar.current.date(byAdding: .minute, value: time, to: Date())
	let milleseconds = Int32(timeRange?.timeIntervalSince1970 ?? 0)
	fetchMessagesRequest.predicate =  NSPredicate(format: "messageTimestamp >= %d", milleseconds)

	do {
		let fetchedMessages = try context.fetch(fetchMessagesRequest)
		if fetchedMessages.count == 1 {
			return fetchedMessages.map { UInt32($0.messageId) }
		}
	} catch {
		return []
	}
	return []
}

public func getTraceRoute(id: Int64, context: NSManagedObjectContext) -> TraceRouteEntity? {

	let fetchTraceRouteRequest = TraceRouteEntity.fetchRequest()
	fetchTraceRouteRequest.predicate = NSPredicate(format: "id == %lld", Int64(id))

	do {
		let fetchedTraceRoute = try context.fetch(fetchTraceRouteRequest)
		if fetchedTraceRoute.count == 1 {
			return fetchedTraceRoute[0]
		}
	} catch {
		return nil
	}
	return nil
}

public func getUser(id: Int64, context: NSManagedObjectContext) -> UserEntity {

	let fetchUserRequest = UserEntity.fetchRequest()
	fetchUserRequest.predicate = NSPredicate(format: "num == %lld", Int64(id))

	do {
		let fetchedUser = try context.fetch(fetchUserRequest)
		if fetchedUser.count == 1 {
			return fetchedUser[0]
		}
	} catch {
		return UserEntity(context: context)
	}
	return UserEntity(context: context)
}

public func getWaypoint(id: Int64, context: NSManagedObjectContext) -> WaypointEntity {

	let fetchWaypointRequest = WaypointEntity.fetchRequest()
	fetchWaypointRequest.predicate = NSPredicate(format: "id == %lld", Int64(id))

	do {
		let fetchedWaypoint = try context.fetch(fetchWaypointRequest)
		if fetchedWaypoint.count == 1 {
			return fetchedWaypoint[0]
		}
	} catch {
		return WaypointEntity(context: context)
	}
	return WaypointEntity(context: context)
}
