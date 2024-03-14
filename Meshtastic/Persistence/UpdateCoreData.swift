//
//  UpdateCoreData.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/3/22.

import CoreData

public func clearPax(destNum: Int64, context: NSManagedObjectContext) -> Bool {

	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(destNum))

	do {
		guard let fetchedNode = try context.fetch(fetchNodeInfoRequest) as? [NodeInfoEntity] else {
			return false
		}
		let newPax = [PaxCounterLog]()
		fetchedNode[0].pax? = NSOrderedSet(array: newPax)
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

public func clearPositions(destNum: Int64, context: NSManagedObjectContext) -> Bool {

	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(destNum))

	do {
		guard let fetchedNode = try context.fetch(fetchNodeInfoRequest) as? [NodeInfoEntity] else {
			return false
		}
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
		guard let fetchedNode = try context.fetch(fetchNodeInfoRequest) as? [NodeInfoEntity] else {
			return false
		}
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
		let objects = channel.allPrivateMessages
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
		let objects = user.messageList
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

func upsertNodeInfoPacket (packet: MeshPacket, context: NSManagedObjectContext) {

	let logString = String.localizedStringWithFormat("mesh.log.nodeinfo.received %@".localized, String(packet.from))
	MeshLogger.log("📟 \(logString)")

	guard packet.from > 0 else { return }

	let fetchNodeInfoAppRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoAppRequest.predicate = NSPredicate(format: "num == %lld", Int64(packet.from))

	do {

		let fetchedNode = try context.fetch(fetchNodeInfoAppRequest) as? [NodeInfoEntity] ?? []
		if fetchedNode.count == 0 {
			// Not Found Insert
			let newNode = NodeInfoEntity(context: context)
			newNode.id = Int64(packet.from)
			newNode.num = Int64(packet.from)
			newNode.lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(packet.rxTime)))
			newNode.snr = packet.rxSnr
			newNode.rssi = packet.rxRssi
			newNode.viaMqtt = packet.viaMqtt
			newNode.channel = Int32(packet.channel)
			if let nodeInfoMessage = try? NodeInfo(serializedData: packet.decoded.payload) {
				newNode.channel = Int32(nodeInfoMessage.channel)
				newNode.hopsAway = Int32(truncatingIfNeeded: nodeInfoMessage.hopsAway)
			}
			if let newUserMessage = try? User(serializedData: packet.decoded.payload) {
				
				if newUserMessage.id.isEmpty {
					let newUser = UserEntity(context: context)
					newUser.num = Int64(packet.from)
					let userId = String(format:"%2X", packet.from)
					newUser.userId = "!\(userId)"
					let last4 = String(userId.suffix(4))
					newUser.longName = "Meshtastic \(last4)"
					newUser.shortName = last4
					newUser.hwModel = "UNSET"
					newNode.user = newUser
					
				} else {
					
					let newUser = UserEntity(context: context)
					newUser.userId = newUserMessage.id
					newUser.num = Int64(packet.from)
					newUser.longName = newUserMessage.longName
					newUser.shortName = newUserMessage.shortName
					newUser.role = Int32(newUserMessage.role.rawValue)
					newUser.hwModel = String(describing: newUserMessage.hwModel).uppercased()
					newNode.user = newUser
				}
			} else {
				let newUser = UserEntity(context: context)
				newUser.num = Int64(packet.from)
				let userId = String(format:"%2X", packet.from)
				newUser.userId = "!\(userId)"
				let last4 = String(userId.suffix(4))
				newUser.longName = "Meshtastic \(last4)"
				newUser.shortName = last4
				newUser.hwModel = "UNSET"
				newNode.user = newUser
			}
			
			if newNode.user == nil {
				print("Nil User on nodeinfo")
			}

			let myInfoEntity = MyInfoEntity(context: context)
			myInfoEntity.myNodeNum = Int64(packet.from)
			myInfoEntity.rebootCount = 0
			do {
				try context.save()
				print("💾 Saved a new myInfo for node number: \(String(packet.from))")
			} catch {
				context.rollback()
				let nsError = error as NSError
				print("💥 Error Inserting New Core Data MyInfoEntity: \(nsError)")
			}
			newNode.myInfo = myInfoEntity
			
		} else {
			// Update an existing node
			fetchedNode[0].id = Int64(packet.from)
			fetchedNode[0].num = Int64(packet.from)
			if packet.rxTime > 0 {
				fetchedNode[0].lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(packet.rxTime)))
			}
			fetchedNode[0].snr = packet.rxSnr
			fetchedNode[0].rssi = packet.rxRssi
			fetchedNode[0].viaMqtt = packet.viaMqtt
			fetchedNode[0].channel = Int32(packet.channel)

			if let nodeInfoMessage = try? NodeInfo(serializedData: packet.decoded.payload) {
				fetchedNode[0].channel = Int32(nodeInfoMessage.channel)
				fetchedNode[0].hopsAway = Int32(truncatingIfNeeded: nodeInfoMessage.hopsAway)
				if nodeInfoMessage.hasDeviceMetrics {
					let telemetry = TelemetryEntity(context: context)
					telemetry.batteryLevel = Int32(nodeInfoMessage.deviceMetrics.batteryLevel)
					telemetry.voltage = nodeInfoMessage.deviceMetrics.voltage
					telemetry.channelUtilization = nodeInfoMessage.deviceMetrics.channelUtilization
					telemetry.airUtilTx = nodeInfoMessage.deviceMetrics.airUtilTx
					var newTelemetries = [TelemetryEntity]()
					newTelemetries.append(telemetry)
					fetchedNode[0].telemetries? = NSOrderedSet(array: newTelemetries)
				}
				if nodeInfoMessage.hasUser {
					/// Seeing Some crashes here ?
					fetchedNode[0].user!.userId = nodeInfoMessage.user.id
					fetchedNode[0].user!.num = Int64(nodeInfoMessage.num)
					fetchedNode[0].user!.longName = nodeInfoMessage.user.longName
					fetchedNode[0].user!.shortName = nodeInfoMessage.user.shortName
					fetchedNode[0].user!.role = Int32(nodeInfoMessage.user.role.rawValue)
					fetchedNode[0].user!.hwModel = String(describing: nodeInfoMessage.user.hwModel).uppercased()
				}
			}
			if (fetchedNode[0].user == nil) {
				let newUser = UserEntity(context: context)
				newUser.num = Int64(packet.from)
				let userId = String(format:"%2X", packet.from)
				newUser.userId = "!\(userId)"
				let last4 = String(userId.suffix(4))
				newUser.longName = "Meshtastic \(last4)"
				newUser.shortName = last4
				newUser.hwModel = "UNSET"
				fetchedNode[0].user! = newUser
			}
			do {
				try context.save()
				print("💾 Updated NodeInfo from Node Info App Packet For: \(fetchedNode[0].num)")
			} catch {
				context.rollback()
				let nsError = error as NSError
				print("💥 Error Saving NodeInfoEntity from NODEINFO_APP \(nsError)")
			}
		}
	} catch {
		print("💥 Error Fetching NodeInfoEntity for NODEINFO_APP")
	}
}

func upsertPositionPacket (packet: MeshPacket, context: NSManagedObjectContext) {

	let logString = String.localizedStringWithFormat("mesh.log.position.received %@".localized, String(packet.from))
	MeshLogger.log("📍 \(logString)")

	let fetchNodePositionRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodePositionRequest.predicate = NSPredicate(format: "num == %lld", Int64(packet.from))

	do {

		if let positionMessage = try? Position(serializedData: packet.decoded.payload) {

			/// Don't save empty position packets from null island or apple park
			if (positionMessage.longitudeI != 0 && positionMessage.latitudeI != 0) && (positionMessage.latitudeI != 373346000 && positionMessage.longitudeI != -1220090000) {
				guard let fetchedNode = try context.fetch(fetchNodePositionRequest) as? [NodeInfoEntity] else {
					return
				}
				if fetchedNode.count == 1 {

					// Unset the current latest position for this node
					let fetchCurrentLatestPositionsRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "PositionEntity")
					fetchCurrentLatestPositionsRequest.predicate = NSPredicate(format: "nodePosition.num == %lld && latest = true", Int64(packet.from))

					guard let fetchedPositions = try context.fetch(fetchCurrentLatestPositionsRequest) as? [PositionEntity] else {
						return
					}
					if fetchedPositions.count > 0 {
						for position in fetchedPositions {
							position.latest = false
						}
					}
					let position = PositionEntity(context: context)
					position.latest = true
					position.snr = packet.rxSnr
					position.rssi = packet.rxRssi
					position.seqNo = Int32(positionMessage.seqNumber)
					position.latitudeI = positionMessage.latitudeI
					position.longitudeI = positionMessage.longitudeI
					position.altitude = positionMessage.altitude
					position.satsInView = Int32(positionMessage.satsInView)
					position.speed = Int32(positionMessage.groundSpeed * UInt32(3.6))
					position.heading = Int32(positionMessage.groundTrack)
					position.precisionBits = Int32(positionMessage.precisionBits)
					if positionMessage.timestamp != 0 {
						position.time = Date(timeIntervalSince1970: TimeInterval(Int64(positionMessage.timestamp)))
					} else {
						position.time = Date(timeIntervalSince1970: TimeInterval(Int64(positionMessage.time)))
					}
					guard let mutablePositions = fetchedNode[0].positions!.mutableCopy() as? NSMutableOrderedSet else {
						return
					}
					/// Don't save nearly the same position over and over. If the next position is less than 10 meters from the new position, delete the previous position and save the new one.
					if mutablePositions.count > 0 && position.precisionBits == 32 {
						let mostRecent = mutablePositions.lastObject as! PositionEntity
						if  mostRecent.coordinate.distance(from: position.coordinate) < 15 {
							mutablePositions.remove(mostRecent)
						}
					} else if mutablePositions.count > 0 && 11...16 ~= position.precisionBits {
						/// Don't store any history for reduced accuracy positions, we will just show a circle
						mutablePositions.removeAllObjects()
					}
					mutablePositions.add(position)
					fetchedNode[0].id = Int64(packet.from)
					fetchedNode[0].num = Int64(packet.from)
					if positionMessage.time > 0 {
						fetchedNode[0].lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(positionMessage.time)))
					} else if packet.rxTime > 0 {
						fetchedNode[0].lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(packet.rxTime)))
					}
					fetchedNode[0].snr = packet.rxSnr
					fetchedNode[0].rssi = packet.rxRssi
					fetchedNode[0].viaMqtt = packet.viaMqtt
					fetchedNode[0].channel = Int32(packet.channel)
					fetchedNode[0].positions = mutablePositions.copy() as? NSOrderedSet

					do {
						try context.save()
						print("💾 Updated Node Position Coordinates, SNR and Time from Position App Packet For: \(fetchedNode[0].num)")
					} catch {
						context.rollback()
						let nsError = error as NSError
						print("💥 Error Saving NodeInfoEntity from POSITION_APP \(nsError)")
					}
				}
			} else {

				if (try? NodeInfo(serializedData: packet.decoded.payload)) != nil {
					upsertNodeInfoPacket(packet: packet, context: context)
				} else {
					print("💥 Empty POSITION_APP Packet")
					print((try? packet.jsonString()) ?? "JSON Decode Failure")
				}
			}
		}
	} catch {
		print("💥 Error Deserializing POSITION_APP packet.")
	}
}

func upsertBluetoothConfigPacket(config: Meshtastic.Config.BluetoothConfig, nodeNum: Int64, context: NSManagedObjectContext) {

	let logString = String.localizedStringWithFormat("mesh.log.bluetooth.config %@".localized, String(nodeNum))
	MeshLogger.log("📶 \(logString)")

	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))

	do {
		guard let fetchedNode = try context.fetch(fetchNodeInfoRequest) as? [NodeInfoEntity] else {
			return
		}
		// Found a node, save Device Config
		if !fetchedNode.isEmpty {
			if fetchedNode[0].bluetoothConfig == nil {
				let newBluetoothConfig = BluetoothConfigEntity(context: context)
				newBluetoothConfig.enabled = config.enabled
				newBluetoothConfig.mode = Int32(config.mode.rawValue)
				newBluetoothConfig.fixedPin = Int32(config.fixedPin)
				fetchedNode[0].bluetoothConfig = newBluetoothConfig
			} else {
				fetchedNode[0].bluetoothConfig?.enabled = config.enabled
				fetchedNode[0].bluetoothConfig?.mode = Int32(config.mode.rawValue)
				fetchedNode[0].bluetoothConfig?.fixedPin = Int32(config.fixedPin)
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

func upsertDeviceConfigPacket(config: Meshtastic.Config.DeviceConfig, nodeNum: Int64, context: NSManagedObjectContext) {

	let logString = String.localizedStringWithFormat("mesh.log.device.config %@".localized, String(nodeNum))
	MeshLogger.log("📟 \(logString)")
	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))

	do {
		guard let fetchedNode = try context.fetch(fetchNodeInfoRequest) as? [NodeInfoEntity] else {
			return
		}
		// Found a node, save Device Config
		if !fetchedNode.isEmpty {
			if fetchedNode[0].deviceConfig == nil {
				let newDeviceConfig = DeviceConfigEntity(context: context)
				newDeviceConfig.role = Int32(config.role.rawValue)
				newDeviceConfig.serialEnabled = config.serialEnabled
				newDeviceConfig.debugLogEnabled = config.debugLogEnabled
				newDeviceConfig.buttonGpio = Int32(config.buttonGpio)
				newDeviceConfig.buzzerGpio =  Int32(config.buzzerGpio)
				newDeviceConfig.rebroadcastMode = Int32(config.rebroadcastMode.rawValue)
				newDeviceConfig.nodeInfoBroadcastSecs = Int32(truncating: config.nodeInfoBroadcastSecs as NSNumber)
				newDeviceConfig.doubleTapAsButtonPress = config.doubleTapAsButtonPress
				newDeviceConfig.isManaged = config.isManaged
				fetchedNode[0].deviceConfig = newDeviceConfig
			} else {
				fetchedNode[0].deviceConfig?.role = Int32(config.role.rawValue)
				fetchedNode[0].deviceConfig?.serialEnabled = config.serialEnabled
				fetchedNode[0].deviceConfig?.debugLogEnabled = config.debugLogEnabled
				fetchedNode[0].deviceConfig?.buttonGpio = Int32(config.buttonGpio)
				fetchedNode[0].deviceConfig?.buzzerGpio = Int32(config.buzzerGpio)
				fetchedNode[0].deviceConfig?.rebroadcastMode = Int32(config.rebroadcastMode.rawValue)
				fetchedNode[0].deviceConfig?.nodeInfoBroadcastSecs = Int32(truncating: config.nodeInfoBroadcastSecs as NSNumber)
				fetchedNode[0].deviceConfig?.doubleTapAsButtonPress = config.doubleTapAsButtonPress
				fetchedNode[0].deviceConfig?.isManaged = config.isManaged
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

func upsertDisplayConfigPacket(config: Meshtastic.Config.DisplayConfig, nodeNum: Int64, context: NSManagedObjectContext) {

	let logString = String.localizedStringWithFormat("mesh.log.display.config %@".localized, String(nodeNum))
	MeshLogger.log("🖥️ \(logString)")

	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))

	do {
		guard let fetchedNode = try context.fetch(fetchNodeInfoRequest) as? [NodeInfoEntity] else {
			return
		}
		// Found a node, save Device Config
		if !fetchedNode.isEmpty {

			if fetchedNode[0].displayConfig == nil {

				let newDisplayConfig = DisplayConfigEntity(context: context)
				newDisplayConfig.gpsFormat = Int32(config.gpsFormat.rawValue)
				newDisplayConfig.screenOnSeconds = Int32(config.screenOnSecs)
				newDisplayConfig.screenCarouselInterval = Int32(config.autoScreenCarouselSecs)
				newDisplayConfig.compassNorthTop = config.compassNorthTop
				newDisplayConfig.flipScreen = config.flipScreen
				newDisplayConfig.oledType = Int32(config.oled.rawValue)
				newDisplayConfig.displayMode = Int32(config.displaymode.rawValue)
				newDisplayConfig.units = Int32(config.units.rawValue)
				newDisplayConfig.headingBold = config.headingBold
				fetchedNode[0].displayConfig = newDisplayConfig

			} else {

				fetchedNode[0].displayConfig?.gpsFormat = Int32(config.gpsFormat.rawValue)
				fetchedNode[0].displayConfig?.screenOnSeconds = Int32(config.screenOnSecs)
				fetchedNode[0].displayConfig?.screenCarouselInterval = Int32(config.autoScreenCarouselSecs)
				fetchedNode[0].displayConfig?.compassNorthTop = config.compassNorthTop
				fetchedNode[0].displayConfig?.flipScreen = config.flipScreen
				fetchedNode[0].displayConfig?.oledType = Int32(config.oled.rawValue)
				fetchedNode[0].displayConfig?.displayMode = Int32(config.displaymode.rawValue)
				fetchedNode[0].displayConfig?.units = Int32(config.units.rawValue)
				fetchedNode[0].displayConfig?.headingBold = config.headingBold
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

func upsertLoRaConfigPacket(config: Meshtastic.Config.LoRaConfig, nodeNum: Int64, context: NSManagedObjectContext) {

	let logString = String.localizedStringWithFormat("mesh.log.lora.config %@".localized, String(nodeNum))
	MeshLogger.log("📻 \(logString)")

	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", nodeNum)
	do {
		guard let fetchedNode = try context.fetch(fetchNodeInfoRequest) as? [NodeInfoEntity] else {
			return
		}
		// Found a node, save LoRa Config
		if fetchedNode.count > 0 {
			if fetchedNode[0].loRaConfig == nil {
				// No lora config for node, save a new lora config
				let newLoRaConfig = LoRaConfigEntity(context: context)
				newLoRaConfig.regionCode = Int32(config.region.rawValue)
				newLoRaConfig.usePreset = config.usePreset
				newLoRaConfig.modemPreset = Int32(config.modemPreset.rawValue)
				newLoRaConfig.bandwidth = Int32(config.bandwidth)
				newLoRaConfig.spreadFactor = Int32(config.spreadFactor)
				newLoRaConfig.codingRate = Int32(config.codingRate)
				newLoRaConfig.frequencyOffset = config.frequencyOffset
				newLoRaConfig.overrideFrequency = config.overrideFrequency
				newLoRaConfig.overrideDutyCycle = config.overrideDutyCycle
				newLoRaConfig.hopLimit = Int32(config.hopLimit)
				newLoRaConfig.txPower = Int32(config.txPower)
				newLoRaConfig.txEnabled = config.txEnabled
				newLoRaConfig.channelNum = Int32(config.channelNum)
				newLoRaConfig.sx126xRxBoostedGain = config.sx126XRxBoostedGain
				newLoRaConfig.ignoreMqtt = config.ignoreMqtt
				fetchedNode[0].loRaConfig = newLoRaConfig
			} else {
				fetchedNode[0].loRaConfig?.regionCode = Int32(config.region.rawValue)
				fetchedNode[0].loRaConfig?.usePreset = config.usePreset
				fetchedNode[0].loRaConfig?.modemPreset = Int32(config.modemPreset.rawValue)
				fetchedNode[0].loRaConfig?.bandwidth = Int32(config.bandwidth)
				fetchedNode[0].loRaConfig?.spreadFactor = Int32(config.spreadFactor)
				fetchedNode[0].loRaConfig?.codingRate = Int32(config.codingRate)
				fetchedNode[0].loRaConfig?.frequencyOffset = config.frequencyOffset
				fetchedNode[0].loRaConfig?.overrideFrequency = config.overrideFrequency
				fetchedNode[0].loRaConfig?.overrideDutyCycle = config.overrideDutyCycle
				fetchedNode[0].loRaConfig?.hopLimit = Int32(config.hopLimit)
				fetchedNode[0].loRaConfig?.txPower = Int32(config.txPower)
				fetchedNode[0].loRaConfig?.txEnabled = config.txEnabled
				fetchedNode[0].loRaConfig?.channelNum = Int32(config.channelNum)
				fetchedNode[0].loRaConfig?.sx126xRxBoostedGain = config.sx126XRxBoostedGain
				fetchedNode[0].loRaConfig?.ignoreMqtt = config.ignoreMqtt
				fetchedNode[0].loRaConfig?.sx126xRxBoostedGain = config.sx126XRxBoostedGain
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

func upsertNetworkConfigPacket(config: Meshtastic.Config.NetworkConfig, nodeNum: Int64, context: NSManagedObjectContext) {

	let logString = String.localizedStringWithFormat("mesh.log.network.config %@".localized, String(nodeNum))
	MeshLogger.log("🌐 \(logString)")

	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))

	do {

		guard let fetchedNode = try context.fetch(fetchNodeInfoRequest) as? [NodeInfoEntity] else {
			return
		}
		// Found a node, save WiFi Config
		if !fetchedNode.isEmpty {
			if fetchedNode[0].networkConfig == nil {
				let newNetworkConfig = NetworkConfigEntity(context: context)
				newNetworkConfig.wifiEnabled = config.wifiEnabled
				newNetworkConfig.wifiSsid = config.wifiSsid
				newNetworkConfig.wifiPsk = config.wifiPsk
				newNetworkConfig.ethEnabled = config.ethEnabled
				fetchedNode[0].networkConfig = newNetworkConfig
			} else {
				fetchedNode[0].networkConfig?.ethEnabled = config.ethEnabled
				fetchedNode[0].networkConfig?.wifiEnabled = config.wifiEnabled
				fetchedNode[0].networkConfig?.wifiSsid = config.wifiSsid
				fetchedNode[0].networkConfig?.wifiPsk = config.wifiPsk
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

func upsertPositionConfigPacket(config: Meshtastic.Config.PositionConfig, nodeNum: Int64, context: NSManagedObjectContext) {

	let logString = String.localizedStringWithFormat("mesh.log.position.config %@".localized, String(nodeNum))
	MeshLogger.log("🗺️ \(logString)")

	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))

	do {

		guard let fetchedNode = try context.fetch(fetchNodeInfoRequest) as? [NodeInfoEntity] else {
			return
		}
		// Found a node, save LoRa Config
		if !fetchedNode.isEmpty {
			if fetchedNode[0].positionConfig == nil {
				let newPositionConfig = PositionConfigEntity(context: context)
				newPositionConfig.smartPositionEnabled = config.positionBroadcastSmartEnabled
				newPositionConfig.deviceGpsEnabled = config.gpsEnabled
				newPositionConfig.gpsMode = Int32(config.gpsMode.rawValue)
				newPositionConfig.rxGpio = Int32(config.rxGpio)
				newPositionConfig.txGpio = Int32(config.txGpio)
				newPositionConfig.gpsEnGpio = Int32(config.gpsEnGpio)
				newPositionConfig.fixedPosition = config.fixedPosition
				newPositionConfig.positionBroadcastSeconds = Int32(truncatingIfNeeded: config.positionBroadcastSecs)
				newPositionConfig.broadcastSmartMinimumIntervalSecs = Int32(config.broadcastSmartMinimumIntervalSecs)
				newPositionConfig.broadcastSmartMinimumDistance = Int32(config.broadcastSmartMinimumDistance)
				newPositionConfig.positionFlags = Int32(config.positionFlags)
				newPositionConfig.gpsAttemptTime = 900
				newPositionConfig.gpsUpdateInterval = Int32(config.gpsUpdateInterval)
				fetchedNode[0].positionConfig = newPositionConfig
			} else {
				fetchedNode[0].positionConfig?.smartPositionEnabled = config.positionBroadcastSmartEnabled
				fetchedNode[0].positionConfig?.deviceGpsEnabled = config.gpsEnabled
				fetchedNode[0].positionConfig?.gpsMode = Int32(config.gpsMode.rawValue)
				fetchedNode[0].positionConfig?.rxGpio = Int32(config.rxGpio)
				fetchedNode[0].positionConfig?.txGpio = Int32(config.txGpio)
				fetchedNode[0].positionConfig?.gpsEnGpio = Int32(config.gpsEnGpio)
				fetchedNode[0].positionConfig?.fixedPosition = config.fixedPosition
				fetchedNode[0].positionConfig?.positionBroadcastSeconds = Int32(truncatingIfNeeded: config.positionBroadcastSecs)
				fetchedNode[0].positionConfig?.broadcastSmartMinimumIntervalSecs = Int32(config.broadcastSmartMinimumIntervalSecs)
				fetchedNode[0].positionConfig?.broadcastSmartMinimumDistance = Int32(config.broadcastSmartMinimumDistance)
				fetchedNode[0].positionConfig?.gpsAttemptTime = 900
				fetchedNode[0].positionConfig?.gpsUpdateInterval = Int32(config.gpsUpdateInterval)
				fetchedNode[0].positionConfig?.positionFlags = Int32(config.positionFlags)
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

func upsertPowerConfigPacket(config: Meshtastic.Config.PowerConfig, nodeNum: Int64, context: NSManagedObjectContext) {
	let logString = String.localizedStringWithFormat("mesh.log.power.config %@".localized, String(nodeNum))
	MeshLogger.log("🗺️ \(logString)")

	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))

	do {
		guard let fetchedNode = try context.fetch(fetchNodeInfoRequest) as? [NodeInfoEntity] else {
			return
		}
		// Found a node, save Power Config
		if !fetchedNode.isEmpty {
			if fetchedNode[0].powerConfig == nil {
				let newPowerConfig = PowerConfigEntity(context: context)
				newPowerConfig.adcMultiplierOverride = config.adcMultiplierOverride
				newPowerConfig.deviceBatteryInaAddress = Int32(config.deviceBatteryInaAddress)
				newPowerConfig.isPowerSaving = config.isPowerSaving
				newPowerConfig.lsSecs = Int32(config.lsSecs)
				newPowerConfig.minWakeSecs = Int32(config.minWakeSecs)
				newPowerConfig.onBatteryShutdownAfterSecs = Int32(config.onBatteryShutdownAfterSecs)
				newPowerConfig.waitBluetoothSecs = Int32(config.waitBluetoothSecs)
				fetchedNode[0].powerConfig = newPowerConfig
			} else {
				fetchedNode[0].powerConfig?.adcMultiplierOverride = config.adcMultiplierOverride
				fetchedNode[0].powerConfig?.deviceBatteryInaAddress = Int32(config.deviceBatteryInaAddress)
				fetchedNode[0].powerConfig?.isPowerSaving = config.isPowerSaving
				fetchedNode[0].powerConfig?.lsSecs = Int32(config.lsSecs)
				fetchedNode[0].powerConfig?.minWakeSecs = Int32(config.minWakeSecs)
				fetchedNode[0].powerConfig?.onBatteryShutdownAfterSecs = Int32(config.onBatteryShutdownAfterSecs)
				fetchedNode[0].powerConfig?.waitBluetoothSecs = Int32(config.waitBluetoothSecs)
			}
			do {
				try context.save()
				print("💾 Updated Power Config for node number: \(String(nodeNum))")
			} catch {
				context.rollback()
				let nsError = error as NSError
				print("💥 Error Updating Core Data PowerConfigEntity: \(nsError)")
			}
		} else {
			print("💥 No Nodes found in local database matching node number \(nodeNum) unable to save Power Config")
		}
	} catch {
		let nsError = error as NSError
		print("💥 Fetching node for core data PowerConfigEntity failed: \(nsError)")
	}
}

func upsertAmbientLightingModuleConfigPacket(config: Meshtastic.ModuleConfig.AmbientLightingConfig, nodeNum: Int64, context: NSManagedObjectContext) {

	let logString = String.localizedStringWithFormat("mesh.log.ambientlighting.config %@".localized, String(nodeNum))
	MeshLogger.log("🏮 \(logString)")

	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))

	do {

		guard let fetchedNode = try context.fetch(fetchNodeInfoRequest) as? [NodeInfoEntity] else {
			return
		}
		// Found a node, save Ambient Lighting Config
		if !fetchedNode.isEmpty {

			if fetchedNode[0].cannedMessageConfig == nil {

				let newAmbientLightingConfig = AmbientLightingConfigEntity(context: context)

				newAmbientLightingConfig.ledState = config.ledState
				newAmbientLightingConfig.current = Int32(config.current)
				newAmbientLightingConfig.red = Int32(config.red)
				newAmbientLightingConfig.green = Int32(config.green)
				newAmbientLightingConfig.blue = Int32(config.blue)
				fetchedNode[0].ambientLightingConfig = newAmbientLightingConfig

			} else {
				
				if fetchedNode[0].ambientLightingConfig == nil {
					fetchedNode[0].ambientLightingConfig = AmbientLightingConfigEntity(context: context)
				}
				fetchedNode[0].ambientLightingConfig?.ledState = config.ledState
				fetchedNode[0].ambientLightingConfig?.current = Int32(config.current)
				fetchedNode[0].ambientLightingConfig?.red = Int32(config.red)
				fetchedNode[0].ambientLightingConfig?.green = Int32(config.green)
				fetchedNode[0].ambientLightingConfig?.blue = Int32(config.blue)
			}

			do {
				try context.save()
				print("💾 Updated Ambient Lighting Module Config for node number: \(String(nodeNum))")
			} catch {
				context.rollback()
				let nsError = error as NSError
				print("💥 Error Updating Core Data AmbientLightingConfigEntity: \(nsError)")
			}
		} else {
			print("💥 No Nodes found in local database matching node number \(nodeNum) unable to save Ambient Lighting Module Config")
		}
	} catch {
		let nsError = error as NSError
		print("💥 Fetching node for core data AmbientLightingConfigEntity failed: \(nsError)")
	}
}

func upsertCannedMessagesModuleConfigPacket(config: Meshtastic.ModuleConfig.CannedMessageConfig, nodeNum: Int64, context: NSManagedObjectContext) {

	let logString = String.localizedStringWithFormat("mesh.log.cannedmessage.config %@".localized, String(nodeNum))
	MeshLogger.log("🥫 \(logString)")

	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))

	do {

		guard let fetchedNode = try context.fetch(fetchNodeInfoRequest) as? [NodeInfoEntity] else {
			return
		}
		// Found a node, save Canned Message Config
		if !fetchedNode.isEmpty {

			if fetchedNode[0].cannedMessageConfig == nil {

				let newCannedMessageConfig = CannedMessageConfigEntity(context: context)

				newCannedMessageConfig.enabled = config.enabled
				newCannedMessageConfig.sendBell = config.sendBell
				newCannedMessageConfig.rotary1Enabled = config.rotary1Enabled
				newCannedMessageConfig.updown1Enabled = config.updown1Enabled
				newCannedMessageConfig.inputbrokerPinA = Int32(config.inputbrokerPinA)
				newCannedMessageConfig.inputbrokerPinB = Int32(config.inputbrokerPinB)
				newCannedMessageConfig.inputbrokerPinPress = Int32(config.inputbrokerPinPress)
				newCannedMessageConfig.inputbrokerEventCw = Int32(config.inputbrokerEventCw.rawValue)
				newCannedMessageConfig.inputbrokerEventCcw = Int32(config.inputbrokerEventCcw.rawValue)
				newCannedMessageConfig.inputbrokerEventPress = Int32(config.inputbrokerEventPress.rawValue)

				fetchedNode[0].cannedMessageConfig = newCannedMessageConfig

			} else {

				fetchedNode[0].cannedMessageConfig?.enabled = config.enabled
				fetchedNode[0].cannedMessageConfig?.sendBell = config.sendBell
				fetchedNode[0].cannedMessageConfig?.rotary1Enabled = config.rotary1Enabled
				fetchedNode[0].cannedMessageConfig?.updown1Enabled = config.updown1Enabled
				fetchedNode[0].cannedMessageConfig?.inputbrokerPinA = Int32(config.inputbrokerPinA)
				fetchedNode[0].cannedMessageConfig?.inputbrokerPinB = Int32(config.inputbrokerPinB)
				fetchedNode[0].cannedMessageConfig?.inputbrokerPinPress = Int32(config.inputbrokerPinPress)
				fetchedNode[0].cannedMessageConfig?.inputbrokerEventCw = Int32(config.inputbrokerEventCw.rawValue)
				fetchedNode[0].cannedMessageConfig?.inputbrokerEventCcw = Int32(config.inputbrokerEventCcw.rawValue)
				fetchedNode[0].cannedMessageConfig?.inputbrokerEventPress = Int32(config.inputbrokerEventPress.rawValue)
			}

			do {
				try context.save()
				print("💾 Updated Canned Message Module Config for node number: \(String(nodeNum))")
			} catch {
				context.rollback()
				let nsError = error as NSError
				print("💥 Error Updating Core Data CannedMessageConfigEntity: \(nsError)")
			}
		} else {
			print("💥 No Nodes found in local database matching node number \(nodeNum) unable to save Canned Message Module Config")
		}
	} catch {
		let nsError = error as NSError
		print("💥 Fetching node for core data CannedMessageConfigEntity failed: \(nsError)")
	}
}

func upsertDetectionSensorModuleConfigPacket(config: Meshtastic.ModuleConfig.DetectionSensorConfig, nodeNum: Int64, context: NSManagedObjectContext) {

	let logString = String.localizedStringWithFormat("mesh.log.detectionsensor.config %@".localized, String(nodeNum))
	MeshLogger.log("🕵️ \(logString)")

	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))

	do {

		guard let fetchedNode = try context.fetch(fetchNodeInfoRequest) as? [NodeInfoEntity] else {
			return
		}
		// Found a node, save Detection Sensor Config
		if !fetchedNode.isEmpty {

			if fetchedNode[0].detectionSensorConfig == nil {

				let newConfig = DetectionSensorConfigEntity(context: context)
				newConfig.enabled = config.enabled
				newConfig.sendBell = config.sendBell
				newConfig.name = config.name

				newConfig.monitorPin = Int32(config.monitorPin)
				newConfig.detectionTriggeredHigh = config.detectionTriggeredHigh
				newConfig.usePullup = config.usePullup
				newConfig.minimumBroadcastSecs = Int32(config.minimumBroadcastSecs)
				newConfig.stateBroadcastSecs = Int32(config.stateBroadcastSecs)
				fetchedNode[0].detectionSensorConfig = newConfig

			} else {
				fetchedNode[0].detectionSensorConfig?.enabled = config.enabled
				fetchedNode[0].detectionSensorConfig?.sendBell = config.sendBell
				fetchedNode[0].detectionSensorConfig?.name = config.name
				fetchedNode[0].detectionSensorConfig?.monitorPin = Int32(config.monitorPin)
				fetchedNode[0].detectionSensorConfig?.usePullup = config.usePullup
				fetchedNode[0].detectionSensorConfig?.detectionTriggeredHigh = config.detectionTriggeredHigh
				fetchedNode[0].detectionSensorConfig?.minimumBroadcastSecs = Int32(config.minimumBroadcastSecs)
				fetchedNode[0].detectionSensorConfig?.stateBroadcastSecs = Int32(config.stateBroadcastSecs)
			}

			do {
				try context.save()
				print("💾 Updated Detection Sensor Module Config for node number: \(String(nodeNum))")

			} catch {
				context.rollback()
				let nsError = error as NSError
				print("💥 Error Updating Core Data DetectionSensorConfigEntity: \(nsError)")
			}

		} else {
			print("💥 No Nodes found in local database matching node number \(nodeNum) unable to save Detection Sensor Module Config")
		}

	} catch {
		let nsError = error as NSError
		print("💥 Fetching node for core data DetectionSensorConfigEntity failed: \(nsError)")
	}
}

func upsertExternalNotificationModuleConfigPacket(config: Meshtastic.ModuleConfig.ExternalNotificationConfig, nodeNum: Int64, context: NSManagedObjectContext) {

	let logString = String.localizedStringWithFormat("mesh.log.externalnotification.config %@".localized, String(nodeNum))
	MeshLogger.log("📣 \(logString)")

	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))

	do {

		guard let fetchedNode = try context.fetch(fetchNodeInfoRequest) as? [NodeInfoEntity] else {
			return
		}
		// Found a node, save External Notificaitone Config
		if !fetchedNode.isEmpty {

			if fetchedNode[0].externalNotificationConfig == nil {
				let newExternalNotificationConfig = ExternalNotificationConfigEntity(context: context)
				newExternalNotificationConfig.enabled = config.enabled
				newExternalNotificationConfig.usePWM = config.usePwm
				newExternalNotificationConfig.alertBell = config.alertBell
				newExternalNotificationConfig.alertBellBuzzer = config.alertBellBuzzer
				newExternalNotificationConfig.alertBellVibra = config.alertBellVibra
				newExternalNotificationConfig.alertMessage = config.alertMessage
				newExternalNotificationConfig.alertMessageBuzzer = config.alertMessageBuzzer
				newExternalNotificationConfig.alertMessageVibra = config.alertMessageVibra
				newExternalNotificationConfig.active = config.active
				newExternalNotificationConfig.output = Int32(config.output)
				newExternalNotificationConfig.outputBuzzer = Int32(config.outputBuzzer)
				newExternalNotificationConfig.outputVibra = Int32(config.outputVibra)
				newExternalNotificationConfig.outputMilliseconds = Int32(config.outputMs)
				newExternalNotificationConfig.nagTimeout = Int32(config.nagTimeout)
				newExternalNotificationConfig.useI2SAsBuzzer = config.useI2SAsBuzzer
				fetchedNode[0].externalNotificationConfig = newExternalNotificationConfig

			} else {
				fetchedNode[0].externalNotificationConfig?.enabled = config.enabled
				fetchedNode[0].externalNotificationConfig?.usePWM = config.usePwm
				fetchedNode[0].externalNotificationConfig?.alertBell = config.alertBell
				fetchedNode[0].externalNotificationConfig?.alertBellBuzzer = config.alertBellBuzzer
				fetchedNode[0].externalNotificationConfig?.alertBellVibra = config.alertBellVibra
				fetchedNode[0].externalNotificationConfig?.alertMessage = config.alertMessage
				fetchedNode[0].externalNotificationConfig?.alertMessageBuzzer = config.alertMessageBuzzer
				fetchedNode[0].externalNotificationConfig?.alertMessageVibra = config.alertMessageVibra
				fetchedNode[0].externalNotificationConfig?.active = config.active
				fetchedNode[0].externalNotificationConfig?.output = Int32(config.output)
				fetchedNode[0].externalNotificationConfig?.outputBuzzer = Int32(config.outputBuzzer)
				fetchedNode[0].externalNotificationConfig?.outputVibra = Int32(config.outputVibra)
				fetchedNode[0].externalNotificationConfig?.outputMilliseconds = Int32(config.outputMs)
				fetchedNode[0].externalNotificationConfig?.nagTimeout = Int32(config.nagTimeout)
				fetchedNode[0].externalNotificationConfig?.useI2SAsBuzzer = config.useI2SAsBuzzer
			}

			do {
				try context.save()
				print("💾 Updated External Notification Module Config for node number: \(String(nodeNum))")
			} catch {
				context.rollback()
				let nsError = error as NSError
				print("💥 Error Updating Core Data ExternalNotificationConfigEntity: \(nsError)")
			}
		} else {
			print("💥 No Nodes found in local database matching node number \(nodeNum) unable to save External Notification Module Config")
		}
	} catch {
		let nsError = error as NSError
		print("💥 Fetching node for core data ExternalNotificationConfigEntity failed: \(nsError)")
	}
}

func upsertPaxCounterModuleConfigPacket(config: Meshtastic.ModuleConfig.PaxcounterConfig, nodeNum: Int64, context: NSManagedObjectContext) {

	let logString = String.localizedStringWithFormat("mesh.log.paxcounter.config %@".localized, String(nodeNum))
	MeshLogger.log("🧑‍🤝‍🧑 \(logString)")

	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))

	do {

		guard let fetchedNode = try context.fetch(fetchNodeInfoRequest) as? [NodeInfoEntity] else {
			return
		}
		// Found a node, save PAX Counter Config
		if !fetchedNode.isEmpty {

			if fetchedNode[0].paxCounterConfig == nil {
				let newPaxCounterConfig = PaxCounterConfigEntity(context: context)
				newPaxCounterConfig.enabled = config.enabled
				newPaxCounterConfig.paxcounterUpdateInterval = Int32(config.paxcounterUpdateInterval)
				
				fetchedNode[0].paxCounterConfig = newPaxCounterConfig

			} else {
				fetchedNode[0].paxCounterConfig?.enabled = config.enabled
				fetchedNode[0].paxCounterConfig?.paxcounterUpdateInterval = Int32(config.paxcounterUpdateInterval)
			}

			do {
				try context.save()
				print("💾 Updated PAX Counter Module Config for node number: \(String(nodeNum))")
			} catch {
				context.rollback()
				let nsError = error as NSError
				print("💥 Error Updating Core Data ExternalNotificationConfigEntity: \(nsError)")
			}
		} else {
			print("💥 No Nodes found in local database matching node number \(nodeNum) unable to save PAX Counter Module Config")
		}
	} catch {
		let nsError = error as NSError
		print("💥 Fetching node for core data PaxCounterConfigEntity failed: \(nsError)")
	}
}

func upsertRtttlConfigPacket(ringtone: String, nodeNum: Int64, context: NSManagedObjectContext) {

	let logString = String.localizedStringWithFormat("mesh.log.ringtone.config %@".localized, String(nodeNum))
	MeshLogger.log("⛰️ \(logString)")

	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))

	do {

		guard let fetchedNode = try context.fetch(fetchNodeInfoRequest) as? [NodeInfoEntity] else {
			return
		}
		// Found a node, save RTTTL Config
		if !fetchedNode.isEmpty {
			if fetchedNode[0].rtttlConfig == nil {
				let newRtttlConfig = RTTTLConfigEntity(context: context)
				newRtttlConfig.ringtone = ringtone
				fetchedNode[0].rtttlConfig = newRtttlConfig
			} else {
				fetchedNode[0].rtttlConfig?.ringtone = ringtone
			}
			do {
				try context.save()
				print("💾 Updated RTTTL Ringtone Config for node number: \(String(nodeNum))")
			} catch {
				context.rollback()
				let nsError = error as NSError
				print("💥 Error Updating Core Data RtttlConfigEntity: \(nsError)")
			}
		} else {
			print("💥 No Nodes found in local database matching node number \(nodeNum) unable to save RTTTL Ringtone Config")
		}
	} catch {
		let nsError = error as NSError
		print("💥 Fetching node for core data RtttlConfigEntity failed: \(nsError)")
	}
}

func upsertMqttModuleConfigPacket(config: Meshtastic.ModuleConfig.MQTTConfig, nodeNum: Int64, context: NSManagedObjectContext) {

	let logString = String.localizedStringWithFormat("mesh.log.mqtt.config %@".localized, String(nodeNum))
	MeshLogger.log("🌉 \(logString)")

	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))

	do {

		guard let fetchedNode = try context.fetch(fetchNodeInfoRequest) as? [NodeInfoEntity] else {
			return
		}
		// Found a node, save MQTT Config
		if !fetchedNode.isEmpty {

			if fetchedNode[0].mqttConfig == nil {
				let newMQTTConfig = MQTTConfigEntity(context: context)
				newMQTTConfig.enabled = config.enabled
				newMQTTConfig.proxyToClientEnabled = config.proxyToClientEnabled
				newMQTTConfig.address = config.address
				newMQTTConfig.username = config.username
				newMQTTConfig.password = config.password
				newMQTTConfig.root = config.root
				newMQTTConfig.encryptionEnabled = config.encryptionEnabled
				newMQTTConfig.jsonEnabled = config.jsonEnabled
				newMQTTConfig.tlsEnabled = config.tlsEnabled
				fetchedNode[0].mqttConfig = newMQTTConfig
			} else {
				fetchedNode[0].mqttConfig?.enabled = config.enabled
				fetchedNode[0].mqttConfig?.proxyToClientEnabled = config.proxyToClientEnabled
				fetchedNode[0].mqttConfig?.address = config.address
				fetchedNode[0].mqttConfig?.username = config.username
				fetchedNode[0].mqttConfig?.password = config.password
				fetchedNode[0].mqttConfig?.root = config.root
				fetchedNode[0].mqttConfig?.encryptionEnabled = config.encryptionEnabled
				fetchedNode[0].mqttConfig?.jsonEnabled = config.jsonEnabled
				fetchedNode[0].mqttConfig?.tlsEnabled = config.tlsEnabled
			}
			do {
				try context.save()
				print("💾 Updated MQTT Config for node number: \(String(nodeNum))")
			} catch {
				context.rollback()
				let nsError = error as NSError
				print("💥 Error Updating Core Data MQTTConfigEntity: \(nsError)")
			}
		} else {
			print("💥 No Nodes found in local database matching node number \(nodeNum) unable to save MQTT Module Config")
		}
	} catch {
		let nsError = error as NSError
		print("💥 Fetching node for core data MQTTConfigEntity failed: \(nsError)")
	}
}

func upsertRangeTestModuleConfigPacket(config: Meshtastic.ModuleConfig.RangeTestConfig, nodeNum: Int64, context: NSManagedObjectContext) {

	let logString = String.localizedStringWithFormat("mesh.log.rangetest.config %@".localized, String(nodeNum))
	MeshLogger.log("⛰️ \(logString)")

	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))

	do {

		guard let fetchedNode = try context.fetch(fetchNodeInfoRequest) as? [NodeInfoEntity] else {
			return
		}
		// Found a node, save Device Config
		if !fetchedNode.isEmpty {
			if fetchedNode[0].rangeTestConfig == nil {
				let newRangeTestConfig = RangeTestConfigEntity(context: context)
				newRangeTestConfig.sender = Int32(config.sender)
				newRangeTestConfig.enabled = config.enabled
				newRangeTestConfig.save = config.save
				fetchedNode[0].rangeTestConfig = newRangeTestConfig
			} else {
				fetchedNode[0].rangeTestConfig?.sender = Int32(config.sender)
				fetchedNode[0].rangeTestConfig?.enabled = config.enabled
				fetchedNode[0].rangeTestConfig?.save = config.save
			}
			do {
				try context.save()
				print("💾 Updated Range Test Config for node number: \(String(nodeNum))")
			} catch {
				context.rollback()
				let nsError = error as NSError
				print("💥 Error Updating Core Data RangeTestConfigEntity: \(nsError)")
			}
		} else {
			print("💥 No Nodes found in local database matching node number \(nodeNum) unable to save Range Test Module Config")
		}
	} catch {
		let nsError = error as NSError
		print("💥 Fetching node for core data RangeTestConfigEntity failed: \(nsError)")
	}
}

func upsertSerialModuleConfigPacket(config: Meshtastic.ModuleConfig.SerialConfig, nodeNum: Int64, context: NSManagedObjectContext) {

	let logString = String.localizedStringWithFormat("mesh.log.serial.config %@".localized, String(nodeNum))
	MeshLogger.log("🤖 \(logString)")

	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))

	do {

		guard let fetchedNode = try context.fetch(fetchNodeInfoRequest) as? [NodeInfoEntity] else {
			return
		}

		// Found a node, save Device Config
		if !fetchedNode.isEmpty {

			if fetchedNode[0].serialConfig == nil {

				let newSerialConfig = SerialConfigEntity(context: context)
				newSerialConfig.enabled = config.enabled
				newSerialConfig.echo = config.echo
				newSerialConfig.rxd = Int32(config.rxd)
				newSerialConfig.txd = Int32(config.txd)
				newSerialConfig.baudRate = Int32(config.baud.rawValue)
				newSerialConfig.timeout = Int32(config.timeout)
				newSerialConfig.mode = Int32(config.mode.rawValue)
				fetchedNode[0].serialConfig = newSerialConfig

			} else {
				fetchedNode[0].serialConfig?.enabled = config.enabled
				fetchedNode[0].serialConfig?.echo = config.echo
				fetchedNode[0].serialConfig?.rxd = Int32(config.rxd)
				fetchedNode[0].serialConfig?.txd = Int32(config.txd)
				fetchedNode[0].serialConfig?.baudRate = Int32(config.baud.rawValue)
				fetchedNode[0].serialConfig?.timeout = Int32(config.timeout)
				fetchedNode[0].serialConfig?.mode = Int32(config.mode.rawValue)
			}

			do {
				try context.save()
				print("💾 Updated Serial Module Config for node number: \(String(nodeNum))")

			} catch {

				context.rollback()

				let nsError = error as NSError
				print("💥 Error Updating Core Data SerialConfigEntity: \(nsError)")
			}

		} else {

			print("💥 No Nodes found in local database matching node number \(nodeNum) unable to save Serial Module Config")
		}

	} catch {

		let nsError = error as NSError
		print("💥 Fetching node for core data SerialConfigEntity failed: \(nsError)")
	}
}

func upsertStoreForwardModuleConfigPacket(config: Meshtastic.ModuleConfig.StoreForwardConfig, nodeNum: Int64, context: NSManagedObjectContext) {

	let logString = String.localizedStringWithFormat("mesh.log.storeforward.config %@".localized, String(nodeNum))
	MeshLogger.log("📬 \(logString)")

	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))

	do {

		guard let fetchedNode = try context.fetch(fetchNodeInfoRequest) as? [NodeInfoEntity] else {
			return
		}
		// Found a node, save Store & Forward Sensor Config
		if !fetchedNode.isEmpty {

			if fetchedNode[0].storeForwardConfig == nil {

				let newConfig = StoreForwardConfigEntity(context: context)
				newConfig.enabled = config.enabled
				newConfig.heartbeat = config.heartbeat
				newConfig.records = Int32(config.records)
				newConfig.historyReturnMax = Int32(config.historyReturnMax)
				newConfig.historyReturnWindow = Int32(config.historyReturnWindow)
				fetchedNode[0].storeForwardConfig = newConfig

			} else {
				fetchedNode[0].storeForwardConfig?.enabled = config.enabled
				fetchedNode[0].storeForwardConfig?.heartbeat = config.heartbeat
				fetchedNode[0].storeForwardConfig?.records = Int32(config.records)
				fetchedNode[0].storeForwardConfig?.historyReturnMax = Int32(config.historyReturnMax)
				fetchedNode[0].storeForwardConfig?.historyReturnWindow = Int32(config.historyReturnWindow)
			}
			do {
				try context.save()
				print("💾 Updated Store & Forward Module Config for node number: \(String(nodeNum))")
			} catch {
				context.rollback()
				let nsError = error as NSError
				print("💥 Error Updating Core Data StoreForwardConfigEntity: \(nsError)")
			}
		} else {
			print("💥 No Nodes found in local database matching node number \(nodeNum) unable to save Store & Forward Module Config")
		}
	} catch {
		let nsError = error as NSError
		print("💥 Fetching node for core data DetectionSensorConfigEntity failed: \(nsError)")
	}
}

func upsertTelemetryModuleConfigPacket(config: Meshtastic.ModuleConfig.TelemetryConfig, nodeNum: Int64, context: NSManagedObjectContext) {

	let logString = String.localizedStringWithFormat("mesh.log.telemetry.config %@".localized, String(nodeNum))
	MeshLogger.log("📈 \(logString)")

	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))

	do {

		guard let fetchedNode = try context.fetch(fetchNodeInfoRequest) as? [NodeInfoEntity] else {
			return
		}
		// Found a node, save Telemetry Config
		if !fetchedNode.isEmpty {

			if fetchedNode[0].telemetryConfig == nil {

				let newTelemetryConfig = TelemetryConfigEntity(context: context)
				newTelemetryConfig.deviceUpdateInterval = Int32(config.deviceUpdateInterval)
				newTelemetryConfig.environmentUpdateInterval = Int32(config.environmentUpdateInterval)
				newTelemetryConfig.environmentMeasurementEnabled = config.environmentMeasurementEnabled
				newTelemetryConfig.environmentScreenEnabled = config.environmentScreenEnabled
				newTelemetryConfig.environmentDisplayFahrenheit = config.environmentDisplayFahrenheit
				newTelemetryConfig.powerMeasurementEnabled = config.powerMeasurementEnabled
				newTelemetryConfig.powerUpdateInterval = Int32(config.powerUpdateInterval)
				newTelemetryConfig.powerScreenEnabled = config.powerScreenEnabled
				fetchedNode[0].telemetryConfig = newTelemetryConfig

			} else {
				fetchedNode[0].telemetryConfig?.deviceUpdateInterval = Int32(config.deviceUpdateInterval)
				fetchedNode[0].telemetryConfig?.environmentUpdateInterval = Int32(config.environmentUpdateInterval)
				fetchedNode[0].telemetryConfig?.environmentMeasurementEnabled = config.environmentMeasurementEnabled
				fetchedNode[0].telemetryConfig?.environmentScreenEnabled = config.environmentScreenEnabled
				fetchedNode[0].telemetryConfig?.environmentDisplayFahrenheit = config.environmentDisplayFahrenheit
				fetchedNode[0].telemetryConfig?.powerMeasurementEnabled = config.powerMeasurementEnabled
				fetchedNode[0].telemetryConfig?.powerUpdateInterval = Int32(config.powerUpdateInterval)
				fetchedNode[0].telemetryConfig?.powerScreenEnabled = config.powerScreenEnabled
			}

			do {
				try context.save()
				print("💾 Updated Telemetry Module Config for node number: \(String(nodeNum))")

			} catch {
				context.rollback()
				let nsError = error as NSError
				print("💥 Error Updating Core Data TelemetryConfigEntity: \(nsError)")
			}

		} else {
			print("💥 No Nodes found in local database matching node number \(nodeNum) unable to save Telemetry Module Config")
		}

	} catch {
		let nsError = error as NSError
		print("💥 Fetching node for core data TelemetryConfigEntity failed: \(nsError)")
	}
}
