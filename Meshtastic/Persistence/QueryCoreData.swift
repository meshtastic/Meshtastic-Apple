//
//  QueryCoreData.swift
//  Meshtastic
//
//  Created(c) Garth Vander Houwen 1/16/23.
//

import Foundation
import SwiftData

func getNodeInfo(id: Int64, context: ModelContext) -> NodeInfoEntity? {
	let num = id
	var descriptor = FetchDescriptor<NodeInfoEntity>(
		predicate: #Predicate { $0.num == num }
	)
	descriptor.fetchLimit = 1
	return try? context.fetch(descriptor).first
}

func getStoreAndForwardMessageIds(seconds: Int, context: ModelContext) -> [UInt32] {
	let time = seconds * -1
	let timeRange = Calendar.current.date(byAdding: .minute, value: time, to: Date())
	let milleseconds = Int32(timeRange?.timeIntervalSince1970 ?? 0)
	let descriptor = FetchDescriptor<MessageEntity>(
		predicate: #Predicate { $0.messageTimestamp >= milleseconds }
	)
	let fetchedMessages = (try? context.fetch(descriptor)) ?? []
	return fetchedMessages.map { UInt32($0.messageId) }
}

func getTraceRoute(id: Int64, context: ModelContext) -> TraceRouteEntity? {
	let traceId = id
	var descriptor = FetchDescriptor<TraceRouteEntity>(
		predicate: #Predicate { $0.id == traceId }
	)
	descriptor.fetchLimit = 1
	return try? context.fetch(descriptor).first
}

func getUser(id: Int64, context: ModelContext) -> UserEntity {
	let userNum = id
	let descriptor = FetchDescriptor<UserEntity>(
		predicate: #Predicate { $0.num == userNum }
	)
	if let existing = try? context.fetch(descriptor).first {
		return existing
	}
	let newUser = UserEntity()
	newUser.num = id
	context.insert(newUser)
	return newUser
}

func getWaypoint(id: Int64, context: ModelContext) -> WaypointEntity {
	let waypointId = id
	let descriptor = FetchDescriptor<WaypointEntity>(
		predicate: #Predicate { $0.id == waypointId }
	)
	if let existing = try? context.fetch(descriptor).first {
		return existing
	}
	let newWaypoint = WaypointEntity()
	newWaypoint.id = id
	context.insert(newWaypoint)
	return newWaypoint
}
