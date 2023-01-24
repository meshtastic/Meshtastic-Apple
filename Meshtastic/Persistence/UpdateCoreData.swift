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

func upsertBluetoothConfigPacket(config: Config, nodeNum: Int64, context: NSManagedObjectContext) {
	
	let logString = String.localizedStringWithFormat(NSLocalizedString("mesh.log.bluetooth.config %@", comment: "Bluetooth config received: %@"), String(nodeNum))
	MeshLogger.log("📶 \(logString)")
	
	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))
	
	do {
		
		let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
		// Found a node, save Device Config
		if !fetchedNode.isEmpty {
			if fetchedNode[0].bluetoothConfig == nil {
				let newBluetoothConfig = BluetoothConfigEntity(context: context)
				newBluetoothConfig.enabled = config.bluetooth.enabled
				newBluetoothConfig.mode = Int32(config.bluetooth.mode.rawValue)
				newBluetoothConfig.fixedPin = Int32(config.bluetooth.fixedPin)
				fetchedNode[0].bluetoothConfig = newBluetoothConfig
			} else {
				fetchedNode[0].bluetoothConfig?.enabled = config.bluetooth.enabled
				fetchedNode[0].bluetoothConfig?.mode = Int32(config.bluetooth.mode.rawValue)
				fetchedNode[0].bluetoothConfig?.fixedPin = Int32(config.bluetooth.fixedPin)
			}
			do {
				try context.save()
				print("💾 Updated Bluetooth Config for node number: \(String(nodeNum))")
			} catch {
				context.rollback()
				let nsError = error as NSError
				print("💥 Error Updating Core Data BluetoothConfigEntity: \(nsError)")
			}
		} else {
			print("💥 No Nodes found in local database matching node number \(nodeNum) unable to save Bluetooth Config")
		}
	} catch {
		let nsError = error as NSError
		print("💥 Fetching node for core data BluetoothConfigEntity failed: \(nsError)")
	}
}

func upsertDeviceConfigPacket(config: Config, nodeNum: Int64, context: NSManagedObjectContext) {
	
	let logString = String.localizedStringWithFormat(NSLocalizedString("mesh.log.device.config %@", comment: "Device config received: %@"), String(nodeNum))
	MeshLogger.log("📟 \(logString)")
	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))
	
	do {
		
		let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
		// Found a node, save Device Config
		if !fetchedNode.isEmpty {
			if fetchedNode[0].deviceConfig == nil {
				let newDeviceConfig = DeviceConfigEntity(context: context)
				newDeviceConfig.role = Int32(config.device.role.rawValue)
				newDeviceConfig.serialEnabled = config.device.serialEnabled
				newDeviceConfig.debugLogEnabled = config.device.debugLogEnabled
				newDeviceConfig.buttonGpio = Int32(config.device.buttonGpio)
				newDeviceConfig.buzzerGpio =  Int32(config.device.buzzerGpio)
				fetchedNode[0].deviceConfig = newDeviceConfig
			} else {
				fetchedNode[0].deviceConfig?.role = Int32(config.device.role.rawValue)
				fetchedNode[0].deviceConfig?.serialEnabled = config.device.serialEnabled
				fetchedNode[0].deviceConfig?.debugLogEnabled = config.device.debugLogEnabled
				fetchedNode[0].deviceConfig?.buttonGpio = Int32(config.device.buttonGpio)
				fetchedNode[0].deviceConfig?.buzzerGpio = Int32(config.device.buzzerGpio)
			}
			do {
				try context.save()
				print("💾 Updated Device Config for node number: \(String(nodeNum))")
			} catch {
				context.rollback()
				let nsError = error as NSError
				print("💥 Error Updating Core Data DeviceConfigEntity: \(nsError)")
			}
		}
	} catch {
		let nsError = error as NSError
		print("💥 Fetching node for core data DeviceConfigEntity failed: \(nsError)")
	}
}

func upsertDisplayConfigPacket(config: Config, nodeNum: Int64, context: NSManagedObjectContext) {
	
	let logString = String.localizedStringWithFormat(NSLocalizedString("mesh.log.display.config %@", comment: "Display config received: %@"), String(nodeNum))
	MeshLogger.log("🖥️ \(logString)")
	
	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))
	
	do {
		
		let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
		
		// Found a node, save Device Config
		if !fetchedNode.isEmpty {
			
			if fetchedNode[0].displayConfig == nil {
				
				let newDisplayConfig = DisplayConfigEntity(context: context)
				newDisplayConfig.gpsFormat = Int32(config.display.gpsFormat.rawValue)
				newDisplayConfig.screenOnSeconds = Int32(config.display.screenOnSecs)
				newDisplayConfig.screenCarouselInterval = Int32(config.display.autoScreenCarouselSecs)
				newDisplayConfig.compassNorthTop = config.display.compassNorthTop
				newDisplayConfig.flipScreen = config.display.flipScreen
				newDisplayConfig.oledType = Int32(config.display.oled.rawValue)
				fetchedNode[0].displayConfig = newDisplayConfig
				
			} else {
				
				fetchedNode[0].displayConfig?.gpsFormat = Int32(config.display.gpsFormat.rawValue)
				fetchedNode[0].displayConfig?.screenOnSeconds = Int32(config.display.screenOnSecs)
				fetchedNode[0].displayConfig?.screenCarouselInterval = Int32(config.display.autoScreenCarouselSecs)
				fetchedNode[0].displayConfig?.compassNorthTop = config.display.compassNorthTop
				fetchedNode[0].displayConfig?.flipScreen = config.display.flipScreen
				fetchedNode[0].displayConfig?.oledType = Int32(config.display.oled.rawValue)
			}
			
			do {
				
				try context.save()
				print("💾 Updated Display Config for node number: \(String(nodeNum))")
				
			} catch {
				
				context.rollback()
				
				let nsError = error as NSError
				print("💥 Error Updating Core Data DisplayConfigEntity: \(nsError)")
			}
		} else {
			
			print("💥 No Nodes found in local database matching node number \(nodeNum) unable to save Display Config")
		}
		
	} catch {
		
		let nsError = error as NSError
		print("💥 Fetching node for core data DisplayConfigEntity failed: \(nsError)")
	}
}

func upsertLoRaConfigPacket(config: Config, nodeNum: Int64, context: NSManagedObjectContext) {
	
	let logString = String.localizedStringWithFormat(NSLocalizedString("mesh.log.lora.config %@", comment: "LoRa config received: %@"), String(nodeNum))
	MeshLogger.log("📻 \(logString)")
	
	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", nodeNum)
	
	do {
		
		let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
		// Found a node, save LoRa Config
		if fetchedNode.count > 0 {
			if fetchedNode[0].loRaConfig == nil {
				// No lora config for node, save a new lora config
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

func upsertNetworkConfigPacket(config: Config, nodeNum: Int64, context: NSManagedObjectContext) {
	
	let logString = String.localizedStringWithFormat(NSLocalizedString("mesh.log.network.config %@", comment: "Network config received: %@"), String(nodeNum))
	MeshLogger.log("🌐 \(logString)")
	
	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))
	
	do {
		
		let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
		// Found a node, save WiFi Config
		if !fetchedNode.isEmpty {
			if fetchedNode[0].networkConfig == nil {
				let newNetworkConfig = NetworkConfigEntity(context: context)
				newNetworkConfig.wifiSsid = config.network.wifiSsid
				newNetworkConfig.wifiPsk = config.network.wifiPsk
				fetchedNode[0].networkConfig = newNetworkConfig
			} else {
				fetchedNode[0].networkConfig?.wifiSsid = config.network.wifiSsid
				fetchedNode[0].networkConfig?.wifiPsk = config.network.wifiPsk
			}
			
			do {
				try context.save()
				print("💾 Updated Network Config for node number: \(String(nodeNum))")
				
			} catch {
				context.rollback()
				let nsError = error as NSError
				print("💥 Error Updating Core Data WiFiConfigEntity: \(nsError)")
			}
		} else {
			print("💥 No Nodes found in local database matching node number \(nodeNum) unable to save Network Config")
		}
	} catch {
		let nsError = error as NSError
		print("💥 Fetching node for core data NetworkConfigEntity failed: \(nsError)")
	}
}

func upsertPositionConfigPacket(config: Config, nodeNum: Int64, context: NSManagedObjectContext) {
	
	let logString = String.localizedStringWithFormat(NSLocalizedString("mesh.log.position.config %@", comment: "Positon config received: %@"), String(nodeNum))
	MeshLogger.log("🗺️ \(logString)")
	
	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))
	
	do {
		
		let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
		// Found a node, save LoRa Config
		if !fetchedNode.isEmpty {
			if fetchedNode[0].positionConfig == nil {
				let newPositionConfig = PositionConfigEntity(context: context)
				newPositionConfig.smartPositionEnabled = config.position.positionBroadcastSmartEnabled
				newPositionConfig.deviceGpsEnabled = config.position.gpsEnabled
				newPositionConfig.fixedPosition = config.position.fixedPosition
				newPositionConfig.gpsUpdateInterval = Int32(config.position.gpsUpdateInterval)
				newPositionConfig.gpsAttemptTime = Int32(config.position.gpsAttemptTime)
				newPositionConfig.positionBroadcastSeconds = Int32(config.position.positionBroadcastSecs)
				newPositionConfig.positionFlags = Int32(config.position.positionFlags)
				fetchedNode[0].positionConfig = newPositionConfig
			} else {
				fetchedNode[0].positionConfig?.smartPositionEnabled = config.position.positionBroadcastSmartEnabled
				fetchedNode[0].positionConfig?.deviceGpsEnabled = config.position.gpsEnabled
				fetchedNode[0].positionConfig?.fixedPosition = config.position.fixedPosition
				fetchedNode[0].positionConfig?.gpsUpdateInterval = Int32(config.position.gpsUpdateInterval)
				fetchedNode[0].positionConfig?.gpsAttemptTime = Int32(config.position.gpsAttemptTime)
				fetchedNode[0].positionConfig?.positionBroadcastSeconds = Int32(config.position.positionBroadcastSecs)
				fetchedNode[0].positionConfig?.positionFlags = Int32(config.position.positionFlags)
			}
			do {
				try context.save()
				print("💾 Updated Position Config for node number: \(String(nodeNum))")
			} catch {
				context.rollback()
				let nsError = error as NSError
				print("💥 Error Updating Core Data PositionConfigEntity: \(nsError)")
			}
		} else {
			print("💥 No Nodes found in local database matching node number \(nodeNum) unable to save Position Config")
		}
	} catch {
		let nsError = error as NSError
		print("💥 Fetching node for core data PositionConfigEntity failed: \(nsError)")
	}
}
