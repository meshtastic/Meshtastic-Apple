//
//  UpdateCoreData.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/3/22.

import CoreData

public func clearPositions(destNum: Int64, context: NSManagedObjectContext) -> Bool {

	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(destNum))

	do {

		let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
			
		let newPostions = [PositionEntity]()
		fetchedNode[0].positions? = NSOrderedSet(array: newPostions)
		
		do {
			try context.save()
			return true
			
		} catch {
			context.rollback()
			return false
		}

	} catch {
		print("💥 Fetch NodeInfoEntity Error")
		return false
	}
}

public func clearTelemetry(destNum: Int64, metricsType: Int32, context: NSManagedObjectContext) -> Bool {
	
	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(destNum))

	do {

		let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
			
		let emptyTelemetry = [TelemetryEntity]()
		fetchedNode[0].telemetries? = NSOrderedSet(array: emptyTelemetry)
		
		do {
			try context.save()
			return true
			
		} catch {
			context.rollback()
			return false
		}

	} catch {
		print("💥 Fetch NodeInfoEntity Error")
		return false
	}
}

public func deleteChannelMessages(channel: ChannelEntity, context: NSManagedObjectContext) {
	let fetchChannelMessagesRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "MessageEntity")
	fetchChannelMessagesRequest.predicate = NSPredicate(format: "channel == %i AND toUser == nil AND admin == false", Int32(channel.id))
	fetchChannelMessagesRequest.includesPropertyValues = false
	do {
		let objects = try context.fetch(fetchChannelMessagesRequest) as! [NSManagedObject]
		   for object in objects {
			   context.delete(object)
		   }
		try context.save()
	} catch let error as NSError {
		print("Error: \(error.localizedDescription)")
	}
}

public func deleteUserMessages(user: UserEntity, context: NSManagedObjectContext) {

	let fetchUserMessagesRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "MessageEntity")
	fetchUserMessagesRequest.predicate = NSPredicate(format: "((toUser.num == %lld) OR (fromUser.num == %lld)) AND toUser != nil AND fromUser != nil AND admin == false", Int64(user.num), Int64(user.num))
	fetchUserMessagesRequest.includesPropertyValues = false
	do {
		let objects = try context.fetch(fetchUserMessagesRequest) as! [NSManagedObject]
		   for object in objects {
			   context.delete(object)
		   }
		try context.save()
	} catch let error as NSError {
		print("Error: \(error.localizedDescription)")
	}
}

public func clearCoreDataDatabase(context: NSManagedObjectContext) {
	
	let persistenceController = PersistenceController.shared.container
	for i in 0...persistenceController.managedObjectModel.entities.count-1 {
		let entity = persistenceController.managedObjectModel.entities[i]
		let query = NSFetchRequest<NSFetchRequestResult>(entityName: entity.name!)
		let deleteRequest = NSBatchDeleteRequest(fetchRequest: query)
			
		do {
			try context.executeAndMergeChanges(using: deleteRequest)
		} catch let error as NSError {
			 print(error)
		}
	}
}
