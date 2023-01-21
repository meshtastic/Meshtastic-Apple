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
	do {
		let objects = channel.allPrivateMessages// try context.fetch(fetchChannelMessagesRequest) as! [NSManagedObject]
		   for object in objects {
			   context.delete(object)
		   }
		try context.save()
	} catch let error as NSError {
		print("Error: \(error.localizedDescription)")
	}
}

public func deleteUserMessages(user: UserEntity, context: NSManagedObjectContext) {

	do {
		let objects = user.messageList//try context.fetch(fetchUserMessagesRequest) as! [NSManagedObject]
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

func upsertLoraConfigPacket(config: Config, nodeNum: Int64, context: NSManagedObjectContext) {
	
	let logString = String.localizedStringWithFormat(NSLocalizedString("mesh.log.lora.config %@", comment: "LoRa config received: %@"), String(nodeNum))
	MeshLogger.log("📻 \(logString)")
	
	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", nodeNum)
	
	do {
		
		let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
		// Found a node, save LoRa Config
		if !fetchedNode.isEmpty {
			if fetchedNode[0].loRaConfig == nil {
				let newLoRaConfig = LoRaConfigEntity(context: context)
				newLoRaConfig.regionCode = Int32(config.lora.region.rawValue)
				newLoRaConfig.usePreset = config.lora.usePreset
				newLoRaConfig.modemPreset = Int32(config.lora.modemPreset.rawValue)
				newLoRaConfig.bandwidth = Int32(config.lora.bandwidth)
				newLoRaConfig.spreadFactor = Int32(config.lora.spreadFactor)
				newLoRaConfig.codingRate = Int32(config.lora.codingRate)
				newLoRaConfig.frequencyOffset = config.lora.frequencyOffset
				newLoRaConfig.hopLimit = Int32(config.lora.hopLimit)
				newLoRaConfig.txPower = Int32(config.lora.txPower)
				newLoRaConfig.txEnabled = config.lora.txEnabled
				newLoRaConfig.channelNum = Int32(config.lora.channelNum)
				fetchedNode[0].loRaConfig = newLoRaConfig
			} else {
				fetchedNode[0].loRaConfig?.regionCode = Int32(config.lora.region.rawValue)
				fetchedNode[0].loRaConfig?.usePreset = config.lora.usePreset
				fetchedNode[0].loRaConfig?.modemPreset = Int32(config.lora.modemPreset.rawValue)
				fetchedNode[0].loRaConfig?.bandwidth = Int32(config.lora.bandwidth)
				fetchedNode[0].loRaConfig?.spreadFactor = Int32(config.lora.spreadFactor)
				fetchedNode[0].loRaConfig?.codingRate = Int32(config.lora.codingRate)
				fetchedNode[0].loRaConfig?.frequencyOffset = config.lora.frequencyOffset
				fetchedNode[0].loRaConfig?.hopLimit = Int32(config.lora.hopLimit)
				fetchedNode[0].loRaConfig?.txPower = Int32(config.lora.txPower)
				fetchedNode[0].loRaConfig?.txEnabled = config.lora.txEnabled
				fetchedNode[0].loRaConfig?.channelNum = Int32(config.lora.channelNum)
			}
			do {
				try context.save()
				context.refreshAllObjects()
				print("💾 Updated LoRa Config for node number: \(String(nodeNum))")
			} catch {
				context.rollback()
				let nsError = error as NSError
				print("💥 Error Updating Core Data LoRaConfigEntity: \(nsError)")
			}
		} else {
			print("💥 No Nodes found in local database matching node number \(nodeNum) unable to save Lora Config")
		}
	} catch {
		let nsError = error as NSError
		print("💥 Fetching node for core data LoRaConfigEntity failed: \(nsError)")
	}
}
