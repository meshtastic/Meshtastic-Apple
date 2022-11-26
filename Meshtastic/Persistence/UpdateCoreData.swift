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

public func deleteChannelMessages(channelIndex: Int32, context: NSManagedObjectContext) {

	let fetchChannelMessagesRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "MessageEntity")
	fetchChannelMessagesRequest.predicate = NSPredicate(format: "channel == %lld", Int32(channelIndex))
	do {
		let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchChannelMessagesRequest)
		try context.executeAndMergeChanges(using: deleteRequest)
		try context.save()
		
	} catch let error as NSError {
		print("Error: \(error.localizedDescription)")
		abort()
	}
}

public func deleteUserMessages(user: UserEntity, context: NSManagedObjectContext) {

	let fetchUserMessagesRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "MessageEntity")
	fetchUserMessagesRequest.predicate = NSPredicate(format: "((toUser.num == %lld) OR (fromUser.num == %lld)) AND toUser != nil AND fromUser != nil AND admin == false", Int64(user.num), Int64(user.num))
	do {
		let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchUserMessagesRequest)
		try context.executeAndMergeChanges(using: deleteRequest)
		try context.save()
		
	} catch let error as NSError {
		print("Error: \(error.localizedDescription)")
		abort()
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

public func setChannelMute(channel: Int32, mute: Bool, context: NSManagedObjectContext) {

	let fetchChannelRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "ChannelEntity")
	fetchChannelRequest.predicate = NSPredicate(format: "index == %lld", Int32(channel))
	do {
		let fetchedChannel = try context.fetch(fetchChannelRequest) as! [ChannelEntity]
		fetchedChannel[0].mute = mute
		fetchedChannel[0].objectWillChange.send()
		
		do {
			try context.save()
		} catch {
			context.rollback()
			print("💥 Save Channel Error")
		}
	} catch {
		print("💥 Fetch Channel Error")
	}
}

public func setUserMute(num: Int64, mute: Bool, context: NSManagedObjectContext) {

	let fetchUserRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "UserEntity")
	fetchUserRequest.predicate = NSPredicate(format: "num == %lld", Int64(num))
	do {
		let fetchedUser = try context.fetch(fetchUserRequest) as! [UserEntity]
		fetchedUser[0].mute = mute
		do {
			try context.save()
		} catch {
			context.rollback()
			print("💥 Save User Mute Error")
		}
	} catch {
		print("💥 Fetch User Error")
	}
}
