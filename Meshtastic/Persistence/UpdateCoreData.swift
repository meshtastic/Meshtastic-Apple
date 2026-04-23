//
//  UpdateCoreData.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/3/22.

import SwiftData
import MeshtasticProtobufs
import OSLog

extension MeshPackets {
	public func clearStaleNodes(nodeExpireDays: Int) -> Bool {
		var nodeExpireTime: TimeInterval {
			return TimeInterval(-nodeExpireDays * 86400)
		}
		var nodePKIExpireTime: TimeInterval {
			return TimeInterval((nodeExpireDays < 7 ? -7 : -nodeExpireDays) * 86400)
		}
		
		if nodeExpireDays == 0 {
			Logger.data.info("💾 [NodeInfoEntity] Skip clearing stale nodes")
			return false
		}
		let expireDate = Date(timeIntervalSinceNow: nodeExpireTime)
		let pkiExpireDate = Date(timeIntervalSinceNow: nodePKIExpireTime)
		let descriptor = FetchDescriptor<NodeInfoEntity>(
			predicate: #Predicate<NodeInfoEntity> { node in
				node.favorite == false && node.ignored == false && node.lastHeard != nil
			}
		)
		do {
			Logger.data.info("💾 [NodeInfoEntity] Clearing nodes older than \(nodeExpireDays) days")
			let candidates = try modelContext.fetch(descriptor)
			let staleNodes = candidates.filter { node in
				guard let lastHeard = node.lastHeard else { return false }
				if node.user?.pkiEncrypted == true {
					return lastHeard < pkiExpireDate
				} else {
					return lastHeard < expireDate
				}
			}
			let deletedNodes = staleNodes.count
			for node in staleNodes {
				modelContext.delete(node)
			}
			try modelContext.save()
			Logger.data.info("💾 [NodeInfoEntity] Cleared \(deletedNodes) stale nodes")
			return deletedNodes > 0
		} catch {
			Logger.data.error("💥 [NodeInfoEntity] Error deleting stale nodes")
		}
		return false
	}
	
	func clearPax(destNum: Int64) -> Bool {
		let num = destNum
		var descriptor = FetchDescriptor<NodeInfoEntity>(
			predicate: #Predicate<NodeInfoEntity> { $0.num == num }
		)
		descriptor.fetchLimit = 1
		do {
			if let node = try modelContext.fetch(descriptor).first {
				node.pax = []
				try modelContext.save()
				return true
			}
		} catch {
			Logger.data.error("💥 [NodeInfoEntity] fetch data error")
		}
		return false
	}
	
	public func clearPositions(destNum: Int64) -> Bool {
		let num = destNum
		var descriptor = FetchDescriptor<NodeInfoEntity>(
			predicate: #Predicate<NodeInfoEntity> { $0.num == num }
		)
		descriptor.fetchLimit = 1
		do {
			if let node = try modelContext.fetch(descriptor).first {
				node.positions = []
				try modelContext.save()
				return true
			}
		} catch {
			Logger.data.error("💥 [NodeInfoEntity] fetch data error")
		}
		return false
	}
	
	public func clearTelemetry(destNum: Int64, metricsType: Int32) -> Bool {
		let num = destNum
		var descriptor = FetchDescriptor<NodeInfoEntity>(
			predicate: #Predicate<NodeInfoEntity> { $0.num == num }
		)
		descriptor.fetchLimit = 1
		do {
			if let node = try modelContext.fetch(descriptor).first {
				let toDelete = node.telemetries.filter { $0.metricsType == metricsType }
				for entity in toDelete {
					modelContext.delete(entity)
				}
				try modelContext.save()
				return true
			}
		} catch {
			Logger.data.error("💥 [NodeInfoEntity] fetch data error")
		}
		return false
	}
	
	public func deleteChannelMessages(channel: ChannelEntity) {
		let channelIndex = channel.index
		let descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> { msg in
				msg.channel == channelIndex && msg.toUser == nil && msg.isEmoji == false
			}
		)
		do {
			let objects = try modelContext.fetch(descriptor)
			for object in objects {
				modelContext.delete(object)
			}
			try modelContext.save()
		} catch {
			Logger.data.error("\(error.localizedDescription, privacy: .public)")
		}
	}
	
	public func deleteUserMessages(user: UserEntity) {
		let messages = (user.sentMessages ?? []) + (user.receivedMessages ?? [])
		let filtered = messages.filter { msg in
			msg.toUser != nil && msg.fromUser != nil && !msg.isEmoji && !msg.admin && msg.portNum != 10
		}
		for object in filtered {
			modelContext.delete(object)
		}
		do {
			try modelContext.save()
		} catch {
			Logger.data.error("\(error.localizedDescription, privacy: .public)")
		}
	}
	
	public func clearDatabase(includeRoutes: Bool) {
		let allModels: [any PersistentModel.Type] = MeshtasticSchema.allModels
		for modelType in allModels {
			let typeName = String(describing: modelType)
			if !includeRoutes && (typeName.contains("Route") || typeName.contains("Location")) {
				continue
			}
			do {
				try modelContext.delete(model: modelType)
			} catch {
				Logger.data.error("\(error.localizedDescription, privacy: .public)")
			}
		}
		do {
			try modelContext.save()
		} catch {
			Logger.data.error("Failed to save after clearing database: \(error.localizedDescription, privacy: .public)")
		}
	}
	
	func updateAnyPacketFrom (packet: MeshPacket, activeDeviceNum: Int64) {
		// Update NodeInfoEntity for any packet received. This mirrors the firmware's NodeDB::updateFrom, which sniffs ALL received packets and updates the radio's nodeDB with packet.from's:
		// - last_heard (from rxTime)
		// - snr
		// - via_mqtt
		// - hops_away
		
		guard packet.from > 0 else { return }
		guard packet.from != activeDeviceNum else { return }
		
		let num = Int64(packet.from)
		var descriptor = FetchDescriptor<NodeInfoEntity>(
			predicate: #Predicate<NodeInfoEntity> { $0.num == num }
		)
		descriptor.fetchLimit = 1
		
		do {
			if let node = try modelContext.fetch(descriptor).first {
				node.id = Int64(packet.from)
				node.num = Int64(packet.from)
				
				if packet.rxTime > 0 {
					node.lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(packet.rxTime)))
					Logger.data.info("💾 [updateAnyPacketFrom] Updating node \(packet.from.toHex(), privacy: .public) lastHeard from rxTime=\(packet.rxTime)")
				} else {
					node.lastHeard = Date()
					Logger.data.info("💾 [updateAnyPacketFrom] Updating node \(packet.from.toHex(), privacy: .public) lastHeard to now (rxTime==0)")
				}
				
				node.snr = packet.rxSnr
				node.rssi = packet.rxRssi
				node.viaMqtt = packet.viaMqtt
				
				if packet.hopStart != 0 && packet.hopLimit <= packet.hopStart {
					node.hopsAway = Int32(packet.hopStart - packet.hopLimit)
					Logger.data.info("💾 [updateAnyPacketFrom] Updating node \(packet.from.toHex(), privacy: .public) hopsAway=\(node.hopsAway)")
				}
				
				do {
					try modelContext.save()
					Logger.data.info("💾 [updateAnyPacketFrom] Updating node \(node.num.toHex(), privacy: .public) snr=\(node.snr), rssi=\(node.rssi) from packet \(packet.id.toHex(), privacy: .public)")
				} catch {
					let nsError = error as NSError
					Logger.data.error("💥 [updateAnyPacketFrom] Error Saving node \(node.num.toHex(), privacy: .public) from packet \(packet.id.toHex(), privacy: .public)  \(nsError, privacy: .public)")
				}
			}
		} catch {
			Logger.data.error("💥 [updateAnyPacketFrom] fetch data error")
		}
	}
	
	func upsertNodeInfoPacket (packet: MeshPacket, favorite: Bool = false) {
		
		let logString = String.localizedStringWithFormat("[NodeInfo] received for: %@".localized, packet.from.toHex())
		Logger.mesh.info("📟 \(logString, privacy: .public)")
		
		guard packet.from > 0 else { return }
		
		let fetchNum = Int64(packet.from)
		var fetchNodeInfoAppRequest = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate<NodeInfoEntity> { $0.num == fetchNum })
		fetchNodeInfoAppRequest.fetchLimit = 1
		
		do {
			
			let fetchedNode = try modelContext.fetch(fetchNodeInfoAppRequest)
			if fetchedNode.count == 0 {
				// Not Found Insert
				let newNode = NodeInfoEntity()
				modelContext.insert(newNode)
				newNode.id = Int64(packet.from)
				newNode.num = Int64(packet.from)
				newNode.favorite = favorite
				if packet.rxTime > 0 {
					newNode.firstHeard = Date(timeIntervalSince1970: TimeInterval(Int64(packet.rxTime)))
					newNode.lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(packet.rxTime)))
				} else {
					newNode.firstHeard = Date()
					newNode.lastHeard = Date()
				}
				newNode.snr = packet.rxSnr
				newNode.rssi = packet.rxRssi
				newNode.viaMqtt = packet.viaMqtt
				
				if packet.to == Constants.maximumNodeNum || packet.to == UserDefaults.preferredPeripheralNum {
					newNode.channel = Int32(packet.channel)
				}
				if let nodeInfoMessage = try? NodeInfo(serializedBytes: packet.decoded.payload) {
					if nodeInfoMessage.hasHopsAway {
						newNode.hopsAway = Int32(nodeInfoMessage.hopsAway)
					}
					newNode.favorite = nodeInfoMessage.isFavorite
				}
				
				if let newUserMessage = try? User(serializedBytes: packet.decoded.payload) {
					
					if newUserMessage.id.isEmpty {
						if packet.from > Constants.minimumNodeNum {
							do {
								let newUser = try createUser(num: Int64(truncatingIfNeeded: packet.from), context: modelContext)
								newNode.user = newUser
							} catch CoreDataError.invalidInput(let message) {
								Logger.data.error("Error Creating a new Core Data UserEntity (Invalid Input) from node number: \(packet.from, privacy: .public) Error:  \(message, privacy: .public)")
							} catch {
								Logger.data.error("Error Creating a new Core Data UserEntity from node number: \(packet.from, privacy: .public) Error:  \(error.localizedDescription, privacy: .public)")
							}
						}
					} else {
						
						let newUser = UserEntity()
						modelContext.insert(newUser)
						newUser.userId = newNode.num.toHex()
						newUser.num = Int64(packet.from)
						newUser.longName = newUserMessage.longName
						newUser.shortName = newUserMessage.shortName
						newUser.role = Int32(newUserMessage.role.rawValue)
						newUser.hwModel = String(describing: newUserMessage.hwModel).uppercased()
						newUser.hwModelId = Int32(newUserMessage.hwModel.rawValue)
						/// For nodes that have the optional isUnmessagable boolean use that, otherwise excluded roles that are unmessagable by default
						if newUserMessage.hasIsUnmessagable {
							newUser.unmessagable = newUserMessage.isUnmessagable
						} else {
							let roles = [2, 4, 5, 6, 7, 10, 11]
							let containsRole = roles.contains(Int(newUser.role))
							if containsRole {
								newUser.unmessagable = true
							} else {
								newUser.unmessagable = false
							}
						}
						if !newUserMessage.publicKey.isEmpty {
							newUser.pkiEncrypted = true
							newUser.publicKey = newUserMessage.publicKey
						}
						
						let fetchHwModel1 = Int64(newUser.hwModelId)
						let hwDescriptor1 = FetchDescriptor<DeviceHardwareEntity>(
							predicate: #Predicate { $0.hwModel == fetchHwModel1 }
						)
						if let hardwareEntity = try? modelContext.fetch(hwDescriptor1).first {
							newUser.hwDisplayName = hardwareEntity.displayName
						}
						newNode.user = newUser
						
						if UserDefaults.newNodeNotifications {
							Task { @MainActor in
								let manager = LocalNotificationManager()
								manager.notifications = [
									Notification(
										id: (UUID().uuidString),
										title: "New Node".localized,
										subtitle: "\(newUser.longName ?? "Unknown".localized)",
										content: "New Node has been discovered".localized,
										target: "nodes",
										path: "meshtastic:///nodes?nodenum=\(newUser.num)"
									)
								]
								manager.schedule()
							}
						}
					}
				} else {
					if packet.from > Constants.minimumNodeNum {
						do {
							let newUser = try createUser(num: Int64(truncatingIfNeeded: packet.from), context: modelContext)
							if !packet.publicKey.isEmpty {
								newNode.user?.pkiEncrypted = true
								newNode.user?.publicKey = packet.publicKey
							}
							newNode.user = newUser
						} catch CoreDataError.invalidInput(let message) {
							Logger.data.error("Error Creating a new Core Data UserEntity (Invalid Input) from node number: \(packet.from, privacy: .public) Error:  \(message, privacy: .public)")
						} catch {
							Logger.data.error("Error Creating a new Core Data UserEntity from node number: \(packet.from, privacy: .public) Error:  \(error.localizedDescription, privacy: .public)")
						}
					}
				}
				// User is messed up and has failed to create at least once, if this fails bail out
				if newNode.user == nil && packet.from > Constants.minimumNodeNum {
					do {
						let newUser = try createUser(num: Int64(packet.from), context: modelContext)
						newNode.user = newUser
					} catch CoreDataError.invalidInput(let message) {
						Logger.data.error("Error Creating a new Core Data UserEntity (Invalid Input) from node number: \(packet.from, privacy: .public) Error:  \(message, privacy: .public)")
						return
					} catch {
						Logger.data.error("Error Creating a new Core Data UserEntity from node number: \(packet.from, privacy: .public) Error:  \(error.localizedDescription, privacy: .public)")
						return
					}
				}
				
				do {
					try modelContext.save()
					Logger.data.info("💾 [NodeInfo] Saved a NodeInfo for node number: \(packet.from.toHex(), privacy: .public)")
				} catch {
					let nsError = error as NSError
					Logger.data.error("💥 [NodeInfoEntity] Error Inserting New Core Data: \(nsError, privacy: .public)")
				}
				
			} else {
				// Update an existing node
				if packet.to == Constants.maximumNodeNum || packet.to == UserDefaults.preferredPeripheralNum {
					fetchedNode[0].channel = Int32(packet.channel)
				}
				
				if let nodeInfoMessage = try? NodeInfo(serializedBytes: packet.decoded.payload) {
					
					fetchedNode[0].hopsAway = Int32(nodeInfoMessage.hopsAway)
					fetchedNode[0].favorite = nodeInfoMessage.isFavorite
					if nodeInfoMessage.hasDeviceMetrics {
						let telemetry = TelemetryEntity()
						modelContext.insert(telemetry)
						telemetry.batteryLevel = Int32(nodeInfoMessage.deviceMetrics.batteryLevel)
						telemetry.voltage = nodeInfoMessage.deviceMetrics.voltage
						telemetry.channelUtilization = nodeInfoMessage.deviceMetrics.channelUtilization
						telemetry.airUtilTx = nodeInfoMessage.deviceMetrics.airUtilTx
						fetchedNode[0].telemetries.append(telemetry)
					}
					if nodeInfoMessage.hasUser {
						fetchedNode[0].user?.userId = nodeInfoMessage.num.toHex()
						fetchedNode[0].user?.num = Int64(nodeInfoMessage.num)
						fetchedNode[0].user?.longName = nodeInfoMessage.user.longName
						fetchedNode[0].user?.shortName = nodeInfoMessage.user.shortName
						fetchedNode[0].user?.role = Int32(nodeInfoMessage.user.role.rawValue)
						fetchedNode[0].user?.hwModel = String(describing: nodeInfoMessage.user.hwModel).uppercased()
						fetchedNode[0].user?.hwModelId = Int32(nodeInfoMessage.user.hwModel.rawValue)
						/// For nodes that have the optional isUnmessagable boolean use that, otherwise excluded roles that are unmessagable by default
						if nodeInfoMessage.user.hasIsUnmessagable {
							fetchedNode[0].user?.unmessagable = nodeInfoMessage.user.isUnmessagable
						} else {
							let roles = [-1, 2, 4, 5, 6, 7, 10, 11]
							let containsRole = roles.contains(Int(fetchedNode[0].user?.role ?? -1))
							if containsRole {
								fetchedNode[0].user?.unmessagable = true
							} else {
								fetchedNode[0].user?.unmessagable = false
							}
						}
						if !nodeInfoMessage.user.publicKey.isEmpty {
							fetchedNode[0].user?.pkiEncrypted = true
							fetchedNode[0].user?.publicKey = nodeInfoMessage.user.publicKey
						}
						if let user = fetchedNode.first?.user {
							let fetchHwModel2 = Int64(user.hwModelId)
							let hwDescriptor2 = FetchDescriptor<DeviceHardwareEntity>(
								predicate: #Predicate { $0.hwModel == fetchHwModel2 }
							)
							if let hardwareEntity = try? modelContext.fetch(hwDescriptor2).first {
								user.hwDisplayName = hardwareEntity.displayName
							}
						}
					}
				} else if let userMessage = try? User(serializedBytes: packet.decoded.payload), !userMessage.id.isEmpty {
					// Mesh broadcast sends a User protobuf (not wrapped in NodeInfo)
					if fetchedNode[0].user == nil {
						let newUser = UserEntity()
						modelContext.insert(newUser)
						fetchedNode[0].user = newUser
					}
					fetchedNode[0].user?.userId = packet.from.toHex()
					fetchedNode[0].user?.num = Int64(packet.from)
					fetchedNode[0].user?.longName = userMessage.longName
					fetchedNode[0].user?.shortName = userMessage.shortName
					fetchedNode[0].user?.role = Int32(userMessage.role.rawValue)
					fetchedNode[0].user?.hwModel = String(describing: userMessage.hwModel).uppercased()
					fetchedNode[0].user?.hwModelId = Int32(userMessage.hwModel.rawValue)
					if userMessage.hasIsUnmessagable {
						fetchedNode[0].user?.unmessagable = userMessage.isUnmessagable
					} else {
						let roles = [-1, 2, 4, 5, 6, 7, 10, 11]
						let containsRole = roles.contains(Int(fetchedNode[0].user?.role ?? -1))
						fetchedNode[0].user?.unmessagable = containsRole
					}
					if !userMessage.publicKey.isEmpty {
						fetchedNode[0].user?.pkiEncrypted = true
						fetchedNode[0].user?.publicKey = userMessage.publicKey
					}
					if packet.hopStart != 0 && packet.hopLimit <= packet.hopStart {
						fetchedNode[0].hopsAway = Int32(packet.hopStart - packet.hopLimit)
					}

				} else if packet.hopStart != 0 && packet.hopLimit <= packet.hopStart {
					fetchedNode[0].hopsAway = Int32(packet.hopStart - packet.hopLimit)
				}
				if fetchedNode[0].user == nil {
					do {
						let newUser = try createUser(num: Int64(truncatingIfNeeded: packet.from), context: modelContext)
						fetchedNode[0].user = newUser
					} catch CoreDataError.invalidInput(let message) {
						Logger.data.error("Error Creating a new Core Data UserEntity on an existing node (Invalid Input) from node number: \(packet.from, privacy: .public) Error:  \(message, privacy: .public)")
					} catch {
						Logger.data.error("Error Creating a new Core Data UserEntity on an existing node from node number: \(packet.from, privacy: .public) Error:  \(error.localizedDescription, privacy: .public)")
					}
				}
				do {
					try modelContext.save()
					Logger.data.info("💾 [NodeInfoEntity] Updated from Node Info App Packet For: \(fetchedNode[0].num.toHex(), privacy: .public)")
				} catch {
					let nsError = error as NSError
					Logger.data.error("💥 [NodeInfoEntity] Error Saving from NODEINFO_APP \(nsError, privacy: .public)")
				}
			}
		} catch {
			Logger.data.error("💥 [NodeInfoEntity] fetch data error for NODEINFO_APP")
		}
	}
	
	func upsertPositionPacket (packet: MeshPacket) {
		
		let logString = String.localizedStringWithFormat("[Position] received from node: %@".localized, String(packet.from))
		Logger.mesh.info("📍 \(logString, privacy: .public)")
		
		let fetchNum = Int64(packet.from)
			var fetchNodePositionRequest = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate<NodeInfoEntity> { $0.num == fetchNum })
			fetchNodePositionRequest.fetchLimit = 1
		do {
			
			if let positionMessage = try? Position(serializedBytes: packet.decoded.payload) {
				
				/// Don't save empty position packets from null island or apple park
				if (positionMessage.longitudeI != 0 && positionMessage.latitudeI != 0) && (positionMessage.latitudeI != 373346000 && positionMessage.longitudeI != -1220090000) {
					let fetchedNode = try modelContext.fetch(fetchNodePositionRequest)
					if fetchedNode.count == 1 {
						
						// Unset the current latest position for this node
						let posNum = Int64(packet.from)
											let fetchCurrentLatestPositionsRequest = FetchDescriptor<PositionEntity>(predicate: #Predicate<PositionEntity> { $0.nodePosition?.num == posNum && $0.latest == true })
						let fetchedPositions = try modelContext.fetch(fetchCurrentLatestPositionsRequest)
						if fetchedPositions.count > 0 {
							for position in fetchedPositions {
								position.latest = false
							}
						}
						let position = PositionEntity()
						modelContext.insert(position)
						position.latest = true
						position.snr = packet.rxSnr
						position.rssi = packet.rxRssi
						position.seqNo = Int32(positionMessage.seqNumber)
						position.latitudeI = positionMessage.latitudeI
						position.longitudeI = positionMessage.longitudeI
						position.altitude = positionMessage.altitude
						position.satsInView = Int32(positionMessage.satsInView)
						position.speed = Int32(positionMessage.groundSpeed)
						let heading = Int32(positionMessage.groundTrack)
						// Throw out bad haeadings from the device
						if heading >= 0 && heading <= 360 {
							position.heading = Int32(positionMessage.groundTrack)
						}
						position.precisionBits = Int32(positionMessage.precisionBits)
						if positionMessage.timestamp != 0 {
							position.time = Date(timeIntervalSince1970: TimeInterval(Int64(positionMessage.timestamp)))
						} else {
							position.time = Date(timeIntervalSince1970: TimeInterval(Int64(positionMessage.time)))
						}
						var mutablePositions = fetchedNode[0].positions
						/// Don't save nearly the same position over and over. If the next position is less than 10 meters from the new position, delete the previous position and save the new one.
						if mutablePositions.count > 0 && (position.precisionBits == 32 || position.precisionBits == 0) {
							if let mostRecentCoord = mutablePositions.last?.nodeCoordinate,
							   let positionCoord = position.nodeCoordinate,
							   mostRecentCoord.distance(from: positionCoord) < 9.0 {
								mutablePositions.removeLast()
							}
						} else if mutablePositions.count > 0 {
							/// Don't store any history for reduced accuracy positions, we will just show a circle
							mutablePositions.removeAll()
						}
						mutablePositions.append(position)
						
						fetchedNode[0].channel = Int32(packet.channel)
						fetchedNode[0].positions = mutablePositions
						
						do {
							try modelContext.save()
							Logger.data.info("💾 [Position] Saved from Position App Packet For: \(fetchedNode[0].num.toHex(), privacy: .public)")
						} catch {
							let nsError = error as NSError
							Logger.data.error("💥 Error Saving NodeInfoEntity from POSITION_APP \(nsError, privacy: .public)")
						}
					}
				} else {
					Logger.data.error("💥 Empty POSITION_APP Packet: \((try? packet.jsonString()) ?? "JSON Decode Failure", privacy: .public)")
				}
			}
		} catch {
			Logger.data.error("💥 Error Deserializing POSITION_APP packet.")
		}
	}
	
	func upsertBluetoothConfigPacket(config: Config.BluetoothConfig, nodeNum: Int64, sessionPasskey: Data? = Data()) {
		
		let logString = String.localizedStringWithFormat("Bluetooth config received: %@".localized, String(nodeNum))
		Logger.mesh.info("📶 \(logString, privacy: .public)")
		
		let fetchNum = Int64(nodeNum)
			var fetchNodeInfoRequest = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate<NodeInfoEntity> { $0.num == fetchNum })
			fetchNodeInfoRequest.fetchLimit = 1
		do {
			let fetchedNode = try modelContext.fetch(fetchNodeInfoRequest)
			// Found a node, save Device Config
			if !fetchedNode.isEmpty {
				if fetchedNode[0].bluetoothConfig == nil {
					let newBluetoothConfig = BluetoothConfigEntity()
					modelContext.insert(newBluetoothConfig)
					newBluetoothConfig.enabled = config.enabled
					newBluetoothConfig.mode = Int32(config.mode.rawValue)
					newBluetoothConfig.fixedPin = Int32(config.fixedPin)
					fetchedNode[0].bluetoothConfig = newBluetoothConfig
				} else {
					fetchedNode[0].bluetoothConfig?.enabled = config.enabled
					fetchedNode[0].bluetoothConfig?.mode = Int32(config.mode.rawValue)
					fetchedNode[0].bluetoothConfig?.fixedPin = Int32(config.fixedPin)
				}
				if sessionPasskey != nil {
					fetchedNode[0].sessionPasskey = sessionPasskey
					fetchedNode[0].sessionExpiration = Date().addingTimeInterval(300)
				}
				do {
					try modelContext.save()
					Logger.data.info("💾 [BluetoothConfigEntity] Updated for node: \(nodeNum.toHex(), privacy: .public)")
				} catch {
					let nsError = error as NSError
					Logger.data.error("💥 [BluetoothConfigEntity] Error Updating Core Data: \(nsError, privacy: .public)")
				}
			} else {
				Logger.data.error("💥 [BluetoothConfigEntity] No Nodes found in local database matching node \(nodeNum.toHex(), privacy: .public) unable to save Bluetooth Config")
			}
		} catch {
			let nsError = error as NSError
			Logger.data.error("💥 [BluetoothConfigEntity] Fetching node for core data failed: \(nsError, privacy: .public)")
		}
	}
	
	func upsertDeviceConfigPacket(config: Config.DeviceConfig, nodeNum: Int64, sessionPasskey: Data? = Data()) {
		
		let logString = String.localizedStringWithFormat("Device config received: %@".localized, String(nodeNum))
		Logger.mesh.info("📟 \(logString, privacy: .public)")
		let fetchNum = Int64(nodeNum)
			var fetchNodeInfoRequest = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate<NodeInfoEntity> { $0.num == fetchNum })
			fetchNodeInfoRequest.fetchLimit = 1
		do {
			let fetchedNode = try modelContext.fetch(fetchNodeInfoRequest)
			// Found a node, save Device Config
			if !fetchedNode.isEmpty {
				if fetchedNode[0].deviceConfig == nil {
					let newDeviceConfig = DeviceConfigEntity()
					modelContext.insert(newDeviceConfig)
					newDeviceConfig.role = Int32(config.role.rawValue)
					newDeviceConfig.buttonGpio = Int32(config.buttonGpio)
					newDeviceConfig.buzzerGpio =  Int32(config.buzzerGpio)
					newDeviceConfig.rebroadcastMode = Int32(config.rebroadcastMode.rawValue)
					newDeviceConfig.nodeInfoBroadcastSecs = Int32(truncating: config.nodeInfoBroadcastSecs as NSNumber)
					newDeviceConfig.doubleTapAsButtonPress = config.doubleTapAsButtonPress
					newDeviceConfig.tripleClickAsAdHocPing = !config.disableTripleClick
					newDeviceConfig.ledHeartbeatEnabled = !config.ledHeartbeatDisabled
					newDeviceConfig.isManaged = config.isManaged
					newDeviceConfig.tzdef = config.tzdef
					fetchedNode[0].deviceConfig = newDeviceConfig
				} else {
					fetchedNode[0].deviceConfig?.role = Int32(config.role.rawValue)
					fetchedNode[0].deviceConfig?.buttonGpio = Int32(config.buttonGpio)
					fetchedNode[0].deviceConfig?.buzzerGpio = Int32(config.buzzerGpio)
					fetchedNode[0].deviceConfig?.rebroadcastMode = Int32(config.rebroadcastMode.rawValue)
					fetchedNode[0].deviceConfig?.nodeInfoBroadcastSecs = Int32(truncating: config.nodeInfoBroadcastSecs as NSNumber)
					fetchedNode[0].deviceConfig?.doubleTapAsButtonPress = config.doubleTapAsButtonPress
					fetchedNode[0].deviceConfig?.tripleClickAsAdHocPing = !config.disableTripleClick
					fetchedNode[0].deviceConfig?.ledHeartbeatEnabled = !config.ledHeartbeatDisabled
					fetchedNode[0].deviceConfig?.isManaged = config.isManaged
					fetchedNode[0].deviceConfig?.tzdef = config.tzdef
				}
				if sessionPasskey != nil {
					fetchedNode[0].sessionPasskey = sessionPasskey
					fetchedNode[0].sessionExpiration = Date().addingTimeInterval(300)
				}
				do {
					try modelContext.save()
					Logger.data.info("💾 [DeviceConfigEntity] Updated Device Config for node number: \(nodeNum.toHex(), privacy: .public)")
				} catch {
					let nsError = error as NSError
					Logger.data.error("💥 [DeviceConfigEntity] Error Updating Core Data: \(nsError, privacy: .public)")
				}
			}
		} catch {
			let nsError = error as NSError
			Logger.data.error("💥 [DeviceConfigEntity] Fetching node for core data failed: \(nsError, privacy: .public)")
		}
	}
	
	func upsertDisplayConfigPacket(config: Config.DisplayConfig, nodeNum: Int64, sessionPasskey: Data? = Data()) {
		
		let logString = String.localizedStringWithFormat("Display config received: %@".localized, nodeNum.toHex())
		Logger.data.info("🖥️ \(logString, privacy: .public)")
		
		let fetchNum = Int64(nodeNum)
			var fetchNodeInfoRequest = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate<NodeInfoEntity> { $0.num == fetchNum })
			fetchNodeInfoRequest.fetchLimit = 1
		do {
			let fetchedNode = try modelContext.fetch(fetchNodeInfoRequest)
			// Found a node, save Device Config
			if !fetchedNode.isEmpty {
				
				if fetchedNode[0].displayConfig == nil {
					
					let newDisplayConfig = DisplayConfigEntity()
					modelContext.insert(newDisplayConfig)
					newDisplayConfig.screenOnSeconds = Int32(truncatingIfNeeded: config.screenOnSecs)
					newDisplayConfig.screenCarouselInterval = Int32(truncatingIfNeeded: config.autoScreenCarouselSecs)
					newDisplayConfig.compassNorthTop = config.compassNorthTop
					newDisplayConfig.flipScreen = config.flipScreen
					newDisplayConfig.oledType = Int32(config.oled.rawValue)
					newDisplayConfig.displayMode = Int32(config.displaymode.rawValue)
					newDisplayConfig.units = Int32(config.units.rawValue)
					newDisplayConfig.headingBold = config.headingBold
					newDisplayConfig.use12HClock = config.use12HClock
					fetchedNode[0].displayConfig = newDisplayConfig
				} else {
					fetchedNode[0].displayConfig?.screenOnSeconds = Int32(truncatingIfNeeded: config.screenOnSecs)
					fetchedNode[0].displayConfig?.screenCarouselInterval = Int32(truncatingIfNeeded: config.autoScreenCarouselSecs)
					fetchedNode[0].displayConfig?.compassNorthTop = config.compassNorthTop
					fetchedNode[0].displayConfig?.flipScreen = config.flipScreen
					fetchedNode[0].displayConfig?.oledType = Int32(config.oled.rawValue)
					fetchedNode[0].displayConfig?.displayMode = Int32(config.displaymode.rawValue)
					fetchedNode[0].displayConfig?.units = Int32(config.units.rawValue)
					fetchedNode[0].displayConfig?.headingBold = config.headingBold
					fetchedNode[0].displayConfig?.use12HClock = config.use12HClock
				}
				if sessionPasskey != nil {
					fetchedNode[0].sessionPasskey = sessionPasskey
					fetchedNode[0].sessionExpiration = Date().addingTimeInterval(300)
				}
				do {
					
					try modelContext.save()
					Logger.data.info("💾 [DisplayConfigEntity] Updated for node: \(nodeNum.toHex(), privacy: .public)")
					
				} catch {
					let nsError = error as NSError
					Logger.data.error("💥 [DisplayConfigEntity] Error Updating Core Data: \(nsError, privacy: .public)")
				}
			} else {
				Logger.data.error("💥 [DisplayConfigEntity] No Nodes found in local database matching node \(nodeNum.toHex(), privacy: .public) unable to save Display Config")
			}
			
		} catch {
			let nsError = error as NSError
			Logger.data.error("💥 [DisplayConfigEntity] Fetching node for core data failed: \(nsError, privacy: .public)")
		}
	}
	
	func upsertLoRaConfigPacket(config: Config.LoRaConfig, nodeNum: Int64, sessionPasskey: Data? = Data()) {
		
		let logString = String.localizedStringWithFormat("LoRa config received: %@".localized, nodeNum.toHex())
		Logger.data.info("📻 \(logString, privacy: .public)")
		
		let fetchNum = nodeNum
			var fetchNodeInfoRequest = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate<NodeInfoEntity> { $0.num == fetchNum })
			fetchNodeInfoRequest.fetchLimit = 1
		do {
			let fetchedNode = try modelContext.fetch(fetchNodeInfoRequest)
			// Found a node, save LoRa Config
			if fetchedNode.count > 0 {
				if fetchedNode[0].loRaConfig == nil {
					// No lora config for node, save a new lora config
					let newLoRaConfig = LoRaConfigEntity()
					modelContext.insert(newLoRaConfig)
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
					newLoRaConfig.okToMqtt = config.configOkToMqtt
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
					fetchedNode[0].loRaConfig?.okToMqtt = config.configOkToMqtt
					fetchedNode[0].loRaConfig?.sx126xRxBoostedGain = config.sx126XRxBoostedGain
				}
				if sessionPasskey != nil {
					fetchedNode[0].sessionPasskey = sessionPasskey
					fetchedNode[0].sessionExpiration = Date().addingTimeInterval(300)
				}
				do {
					try modelContext.save()
					Logger.data.info("💾 [LoRaConfigEntity] Updated for node: \(nodeNum.toHex(), privacy: .public)")
				} catch {
					let nsError = error as NSError
					Logger.data.error("💥 [LoRaConfigEntity] Error Updating Core Data: \(nsError, privacy: .public)")
				}
			} else {
				Logger.data.error("💥 [LoRaConfigEntity] No Nodes found in local database matching node \(nodeNum.toHex(), privacy: .public) unable to save Lora Config")
			}
		} catch {
			let nsError = error as NSError
			Logger.data.error("💥 [LoRaConfigEntity] Fetching node for core data failed: \(nsError, privacy: .public)")
		}
	}
	
	func upsertNetworkConfigPacket(config: Config.NetworkConfig, nodeNum: Int64, sessionPasskey: Data? = Data()) {
		
		let logString = String.localizedStringWithFormat("Network config received: %@".localized, String(nodeNum))
		Logger.data.info("🌐 \(logString, privacy: .public)")
		
		let fetchNum = Int64(nodeNum)
			var fetchNodeInfoRequest = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate<NodeInfoEntity> { $0.num == fetchNum })
			fetchNodeInfoRequest.fetchLimit = 1
		do {
			let fetchedNode = try modelContext.fetch(fetchNodeInfoRequest)
			// Found a node, save WiFi Config
			if !fetchedNode.isEmpty {
				if fetchedNode[0].networkConfig == nil {
					let newNetworkConfig = NetworkConfigEntity()
					modelContext.insert(newNetworkConfig)
					newNetworkConfig.wifiEnabled = config.wifiEnabled
					newNetworkConfig.wifiSsid = config.wifiSsid
					newNetworkConfig.wifiPsk = config.wifiPsk
					newNetworkConfig.ethEnabled = config.ethEnabled
					newNetworkConfig.enabledProtocols = Int32(config.enabledProtocols)
					fetchedNode[0].networkConfig = newNetworkConfig
				} else {
					fetchedNode[0].networkConfig?.ethEnabled = config.ethEnabled
					fetchedNode[0].networkConfig?.wifiEnabled = config.wifiEnabled
					fetchedNode[0].networkConfig?.wifiSsid = config.wifiSsid
					fetchedNode[0].networkConfig?.wifiPsk = config.wifiPsk
					fetchedNode[0].networkConfig?.enabledProtocols = Int32(config.enabledProtocols)
				}
				if sessionPasskey != nil {
					fetchedNode[0].sessionPasskey = sessionPasskey
					fetchedNode[0].sessionExpiration = Date().addingTimeInterval(300)
				}
				do {
					try modelContext.save()
					Logger.data.info("💾 [NetworkConfigEntity] Updated Network Config for node: \(nodeNum.toHex(), privacy: .public)")
					
				} catch {
					let nsError = error as NSError
					Logger.data.error("💥 [NetworkConfigEntity] Error Updating Core Data: \(nsError, privacy: .public)")
				}
			} else {
				Logger.data.error("💥 [NetworkConfigEntity] No Nodes found in local database matching node \(nodeNum.toHex(), privacy: .public) unable to save Network Config")
			}
		} catch {
			let nsError = error as NSError
			Logger.data.error("💥 [NetworkConfigEntity] Fetching node for core data failed: \(nsError, privacy: .public)")
		}
	}
	
	func upsertPositionConfigPacket(config: Config.PositionConfig, nodeNum: Int64, sessionPasskey: Data? = Data()) {
		
		let logString = String.localizedStringWithFormat("Position config received: %@".localized, String(nodeNum))
		Logger.data.info("🗺️ \(logString, privacy: .public)")
		
		let fetchNum = Int64(nodeNum)
			var fetchNodeInfoRequest = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate<NodeInfoEntity> { $0.num == fetchNum })
			fetchNodeInfoRequest.fetchLimit = 1
		do {
			let fetchedNode = try modelContext.fetch(fetchNodeInfoRequest)
			// Found a node, save LoRa Config
			if !fetchedNode.isEmpty {
				if fetchedNode[0].positionConfig == nil {
					let newPositionConfig = PositionConfigEntity()
					modelContext.insert(newPositionConfig)
					newPositionConfig.smartPositionEnabled = config.positionBroadcastSmartEnabled
					newPositionConfig.deviceGpsEnabled = config.gpsEnabled
					newPositionConfig.gpsMode = Int32(truncatingIfNeeded: config.gpsMode.rawValue)
					newPositionConfig.rxGpio = Int32(truncatingIfNeeded: config.rxGpio)
					newPositionConfig.txGpio = Int32(truncatingIfNeeded: config.txGpio)
					newPositionConfig.gpsEnGpio = Int32(truncatingIfNeeded: config.gpsEnGpio)
					newPositionConfig.fixedPosition = config.fixedPosition
					newPositionConfig.positionBroadcastSeconds = Int32(truncatingIfNeeded: config.positionBroadcastSecs)
					newPositionConfig.broadcastSmartMinimumIntervalSecs = Int32(truncatingIfNeeded: config.broadcastSmartMinimumIntervalSecs)
					newPositionConfig.broadcastSmartMinimumDistance = Int32(truncatingIfNeeded: config.broadcastSmartMinimumDistance)
					newPositionConfig.positionFlags = Int32(truncatingIfNeeded: config.positionFlags)
					newPositionConfig.gpsAttemptTime = 900
					newPositionConfig.gpsUpdateInterval = Int32(truncatingIfNeeded: config.gpsUpdateInterval)
					fetchedNode[0].positionConfig = newPositionConfig
				} else {
					fetchedNode[0].positionConfig?.smartPositionEnabled = config.positionBroadcastSmartEnabled
					fetchedNode[0].positionConfig?.deviceGpsEnabled = config.gpsEnabled
					fetchedNode[0].positionConfig?.gpsMode = Int32(truncatingIfNeeded: config.gpsMode.rawValue)
					fetchedNode[0].positionConfig?.rxGpio = Int32(truncatingIfNeeded: config.rxGpio)
					fetchedNode[0].positionConfig?.txGpio = Int32(truncatingIfNeeded: config.txGpio)
					fetchedNode[0].positionConfig?.gpsEnGpio = Int32(truncatingIfNeeded: config.gpsEnGpio)
					fetchedNode[0].positionConfig?.fixedPosition = config.fixedPosition
					fetchedNode[0].positionConfig?.positionBroadcastSeconds = Int32(truncatingIfNeeded: config.positionBroadcastSecs)
					fetchedNode[0].positionConfig?.broadcastSmartMinimumIntervalSecs = Int32(truncatingIfNeeded: config.broadcastSmartMinimumIntervalSecs)
					fetchedNode[0].positionConfig?.broadcastSmartMinimumDistance = Int32(truncatingIfNeeded: config.broadcastSmartMinimumDistance)
					fetchedNode[0].positionConfig?.gpsAttemptTime = 900
					fetchedNode[0].positionConfig?.gpsUpdateInterval = Int32(truncatingIfNeeded: config.gpsUpdateInterval)
					fetchedNode[0].positionConfig?.positionFlags = Int32(truncatingIfNeeded: config.positionFlags)
				}
				if sessionPasskey != nil {
					fetchedNode[0].sessionPasskey = sessionPasskey
					fetchedNode[0].sessionExpiration = Date().addingTimeInterval(300)
				}
				do {
					try modelContext.save()
					Logger.data.info("💾 [PositionConfigEntity] Updated for node: \(nodeNum.toHex(), privacy: .public)")
				} catch {
					let nsError = error as NSError
					Logger.data.error("💥 [PositionConfigEntity] Error Updating Core Data: \(nsError, privacy: .public)")
				}
			} else {
				Logger.data.error("💥 [PositionConfigEntity] No Nodes found in local database matching node \(nodeNum.toHex(), privacy: .public) unable to save Position Config")
			}
		} catch {
			let nsError = error as NSError
			Logger.data.error("💥 [PositionConfigEntity] Fetching node for core data failed: \(nsError, privacy: .public)")
		}
	}
	
	func upsertPowerConfigPacket(config: Config.PowerConfig, nodeNum: Int64, sessionPasskey: Data? = Data()) {
		let logString = String.localizedStringWithFormat("Power config received: %@".localized, String(nodeNum))
		Logger.data.info("🗺️ \(logString, privacy: .public)")
		
		let fetchNum = Int64(nodeNum)
			var fetchNodeInfoRequest = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate<NodeInfoEntity> { $0.num == fetchNum })
			fetchNodeInfoRequest.fetchLimit = 1
		do {
			let fetchedNode = try modelContext.fetch(fetchNodeInfoRequest)
			// Found a node, save Power Config
			if !fetchedNode.isEmpty {
				if fetchedNode[0].powerConfig == nil {
					let newPowerConfig = PowerConfigEntity()
					modelContext.insert(newPowerConfig)
					newPowerConfig.adcMultiplierOverride = config.adcMultiplierOverride
					newPowerConfig.deviceBatteryInaAddress = Int32(config.deviceBatteryInaAddress)
					newPowerConfig.isPowerSaving = config.isPowerSaving
					newPowerConfig.lsSecs = Int32(truncatingIfNeeded: config.lsSecs)
					newPowerConfig.minWakeSecs = Int32(truncatingIfNeeded: config.minWakeSecs)
					newPowerConfig.onBatteryShutdownAfterSecs = Int32(truncatingIfNeeded: config.onBatteryShutdownAfterSecs)
					newPowerConfig.waitBluetoothSecs = Int32(truncatingIfNeeded: config.waitBluetoothSecs)
					fetchedNode[0].powerConfig = newPowerConfig
				} else {
					fetchedNode[0].powerConfig?.adcMultiplierOverride = config.adcMultiplierOverride
					fetchedNode[0].powerConfig?.deviceBatteryInaAddress = Int32(config.deviceBatteryInaAddress)
					fetchedNode[0].powerConfig?.isPowerSaving = config.isPowerSaving
					fetchedNode[0].powerConfig?.lsSecs = Int32(truncatingIfNeeded: config.lsSecs)
					fetchedNode[0].powerConfig?.minWakeSecs = Int32(truncatingIfNeeded: config.minWakeSecs)
					fetchedNode[0].powerConfig?.onBatteryShutdownAfterSecs = Int32(truncatingIfNeeded: config.onBatteryShutdownAfterSecs)
					fetchedNode[0].powerConfig?.waitBluetoothSecs = Int32(truncatingIfNeeded: config.waitBluetoothSecs)
				}
				if sessionPasskey != nil {
					fetchedNode[0].sessionPasskey = sessionPasskey
					fetchedNode[0].sessionExpiration = Date().addingTimeInterval(300)
				}
				do {
					try modelContext.save()
					Logger.data.info("💾 [PowerConfigEntity] Updated Power Config for node: \(nodeNum.toHex(), privacy: .public)")
				} catch {
					let nsError = error as NSError
					Logger.data.error("💥 [PowerConfigEntity] Error Updating Core Data PowerConfigEntity: \(nsError, privacy: .public)")
				}
			} else {
				Logger.data.error("💥 [PowerConfigEntity] No Nodes found in local database matching node \(nodeNum.toHex(), privacy: .public) unable to save Power Config")
			}
		} catch {
			let nsError = error as NSError
			Logger.data.error("💥 [PowerConfigEntity] Fetching node for core data failed: \(nsError, privacy: .public)")
		}
	}
	
	func upsertSecurityConfigPacket(config: Config.SecurityConfig, nodeNum: Int64, sessionPasskey: Data? = Data()) {
		
		let logString = String.localizedStringWithFormat("mesh.log.security.config %@".localized, String(nodeNum))
		Logger.data.info("🛡️ \(logString, privacy: .public)")
		
		let fetchNum = Int64(nodeNum)
			var fetchNodeInfoRequest = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate<NodeInfoEntity> { $0.num == fetchNum })
			fetchNodeInfoRequest.fetchLimit = 1
		do {
			let fetchedNode = try modelContext.fetch(fetchNodeInfoRequest)
			// Found a node, save Security Config
			if !fetchedNode.isEmpty {
				if fetchedNode[0].securityConfig == nil {
					let newSecurityConfig = SecurityConfigEntity()
					modelContext.insert(newSecurityConfig)
					newSecurityConfig.publicKey = config.publicKey
					newSecurityConfig.privateKey = config.privateKey
					if config.adminKey.count > 0 {
						newSecurityConfig.adminKey = config.adminKey[0]
					}
					newSecurityConfig.isManaged = config.isManaged
					newSecurityConfig.serialEnabled = config.serialEnabled
					newSecurityConfig.debugLogApiEnabled = config.debugLogApiEnabled
					newSecurityConfig.adminChannelEnabled = config.adminChannelEnabled
					fetchedNode[0].securityConfig = newSecurityConfig
				} else {
					fetchedNode[0].securityConfig?.publicKey = config.publicKey
					fetchedNode[0].securityConfig?.privateKey = config.privateKey
					if config.adminKey.count > 0 {
						fetchedNode[0].securityConfig?.adminKey = config.adminKey[0]
						if config.adminKey.count > 1 {
							fetchedNode[0].securityConfig?.adminKey2 = config.adminKey[1]
						}
						if config.adminKey.count > 2 {
							fetchedNode[0].securityConfig?.adminKey3 = config.adminKey[2]
						}
					}
					fetchedNode[0].securityConfig?.isManaged = config.isManaged
					fetchedNode[0].securityConfig?.serialEnabled = config.serialEnabled
					fetchedNode[0].securityConfig?.debugLogApiEnabled = config.debugLogApiEnabled
					fetchedNode[0].securityConfig?.adminChannelEnabled = config.adminChannelEnabled
				}
				if sessionPasskey?.count != 0 {
					fetchedNode[0].sessionPasskey = sessionPasskey
					fetchedNode[0].sessionExpiration = Date().addingTimeInterval(300)
				}
				do {
					try modelContext.save()
					Logger.data.info("💾 [SecurityConfigEntity] Updated Security Config for node: \(nodeNum.toHex(), privacy: .public)")
					
				} catch {
					let nsError = error as NSError
					Logger.data.error("💥 [SecurityConfigEntity] Error Updating Core Data: \(nsError, privacy: .public)")
				}
			} else {
				Logger.data.error("💥 [SecurityConfigEntity] No Nodes found in local database matching node \(nodeNum.toHex(), privacy: .public) unable to save Security Config")
			}
		} catch {
			let nsError = error as NSError
			Logger.data.error("💥 [SecurityConfigEntity] Fetching node for core data failed: \(nsError, privacy: .public)")
		}
	}
	
	func upsertAmbientLightingModuleConfigPacket(config: ModuleConfig.AmbientLightingConfig, nodeNum: Int64, sessionPasskey: Data? = Data()) {
		
		let logString = String.localizedStringWithFormat("Ambient Lighting module config received: %@".localized, String(nodeNum))
		Logger.data.info("🏮 \(logString, privacy: .public)")
		
		let fetchNum = Int64(nodeNum)
			var fetchNodeInfoRequest = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate<NodeInfoEntity> { $0.num == fetchNum })
			fetchNodeInfoRequest.fetchLimit = 1
		do {
			let fetchedNode = try modelContext.fetch(fetchNodeInfoRequest)
			// Found a node, save Ambient Lighting Config
			if !fetchedNode.isEmpty {
				
				if fetchedNode[0].cannedMessageConfig == nil {
					let newAmbientLightingConfig = AmbientLightingConfigEntity()
					modelContext.insert(newAmbientLightingConfig)
					newAmbientLightingConfig.ledState = config.ledState
					newAmbientLightingConfig.current = Int32(config.current)
					newAmbientLightingConfig.red = Int32(config.red)
					newAmbientLightingConfig.green = Int32(config.green)
					newAmbientLightingConfig.blue = Int32(config.blue)
					fetchedNode[0].ambientLightingConfig = newAmbientLightingConfig
				} else {
					
					if fetchedNode[0].ambientLightingConfig == nil {
						let newAmbientLighting = AmbientLightingConfigEntity()
						modelContext.insert(newAmbientLighting)
						fetchedNode[0].ambientLightingConfig = newAmbientLighting
					}
					fetchedNode[0].ambientLightingConfig?.ledState = config.ledState
					fetchedNode[0].ambientLightingConfig?.current = Int32(config.current)
					fetchedNode[0].ambientLightingConfig?.red = Int32(config.red)
					fetchedNode[0].ambientLightingConfig?.green = Int32(config.green)
					fetchedNode[0].ambientLightingConfig?.blue = Int32(config.blue)
				}
				if sessionPasskey != nil {
					fetchedNode[0].sessionPasskey = sessionPasskey
					fetchedNode[0].sessionExpiration = Date().addingTimeInterval(300)
				}
				do {
					try modelContext.save()
					Logger.data.info("💾 [AmbientLightingConfigEntity] Updated for node: \(nodeNum.toHex(), privacy: .public)")
				} catch {
					let nsError = error as NSError
					Logger.data.error("💥 [AmbientLightingConfigEntity] Error Updating Core Data: \(nsError, privacy: .public)")
				}
			} else {
				Logger.data.error("💥 [AmbientLightingConfigEntity] No Nodes found in local database matching node \(nodeNum.toHex(), privacy: .public) unable to save Ambient Lighting Module Config")
			}
		} catch {
			let nsError = error as NSError
			Logger.data.error("💥 [AmbientLightingConfigEntity] Fetching node for core data failed: \(nsError, privacy: .public)")
		}
	}
	
	func upsertCannedMessagesModuleConfigPacket(config: ModuleConfig.CannedMessageConfig, nodeNum: Int64, sessionPasskey: Data? = Data()) {
		
		let logString = String.localizedStringWithFormat("Canned Message module config received: %@".localized, String(nodeNum))
		Logger.data.info("🥫 \(logString, privacy: .public)")
		
		let fetchNum = Int64(nodeNum)
			var fetchNodeInfoRequest = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate<NodeInfoEntity> { $0.num == fetchNum })
			fetchNodeInfoRequest.fetchLimit = 1
		do {
			let fetchedNode = try modelContext.fetch(fetchNodeInfoRequest)
			// Found a node, save Canned Message Config
			if !fetchedNode.isEmpty {
				
				if fetchedNode[0].cannedMessageConfig == nil {
					let newCannedMessageConfig = CannedMessageConfigEntity()
					modelContext.insert(newCannedMessageConfig)
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
				if sessionPasskey != nil {
					fetchedNode[0].sessionPasskey = sessionPasskey
					fetchedNode[0].sessionExpiration = Date().addingTimeInterval(300)
				}
				do {
					try modelContext.save()
					Logger.data.info("💾 [CannedMessageConfigEntity] Updated for node: \(nodeNum.toHex(), privacy: .public)")
				} catch {
					let nsError = error as NSError
					Logger.data.error("💥 [CannedMessageConfigEntity] Error Updating Core Data: \(nsError, privacy: .public)")
				}
			} else {
				Logger.data.error("💥 [CannedMessageConfigEntity] No Nodes found in local database matching node \(nodeNum.toHex(), privacy: .public) unable to save Canned Message Module Config")
			}
		} catch {
			let nsError = error as NSError
			Logger.data.error("💥 [CannedMessageConfigEntity] Fetching node for core data failed: \(nsError, privacy: .public)")
		}
	}

	func upsertDetectionSensorModuleConfigPacket(config: ModuleConfig.DetectionSensorConfig, nodeNum: Int64, sessionPasskey: Data? = Data()) {
		
		let logString = String.localizedStringWithFormat("Detection Sensor module config received: %@".localized, String(nodeNum))
		Logger.data.info("🕵️ \(logString, privacy: .public)")
		
		let fetchNum = Int64(nodeNum)
			var fetchNodeInfoRequest = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate<NodeInfoEntity> { $0.num == fetchNum })
			fetchNodeInfoRequest.fetchLimit = 1
		do {
			let fetchedNode = try modelContext.fetch(fetchNodeInfoRequest)
			// Found a node, save Detection Sensor Config
			if !fetchedNode.isEmpty {
				if fetchedNode[0].detectionSensorConfig == nil {
					let newConfig = DetectionSensorConfigEntity()
					modelContext.insert(newConfig)
					newConfig.enabled = config.enabled
					newConfig.sendBell = config.sendBell
					newConfig.name = config.name
					newConfig.monitorPin = Int32(config.monitorPin)
					newConfig.triggerType = Int32(config.detectionTriggerType.rawValue)
					newConfig.usePullup = config.usePullup
					newConfig.minimumBroadcastSecs = Int32(truncatingIfNeeded: config.minimumBroadcastSecs)
					newConfig.stateBroadcastSecs = Int32(truncatingIfNeeded: config.stateBroadcastSecs)
					fetchedNode[0].detectionSensorConfig = newConfig
				} else {
					fetchedNode[0].detectionSensorConfig?.enabled = config.enabled
					fetchedNode[0].detectionSensorConfig?.sendBell = config.sendBell
					fetchedNode[0].detectionSensorConfig?.name = config.name
					fetchedNode[0].detectionSensorConfig?.monitorPin = Int32(config.monitorPin)
					fetchedNode[0].detectionSensorConfig?.usePullup = config.usePullup
					fetchedNode[0].detectionSensorConfig?.triggerType = Int32(config.detectionTriggerType.rawValue)
					fetchedNode[0].detectionSensorConfig?.minimumBroadcastSecs = Int32(truncatingIfNeeded: config.minimumBroadcastSecs)
					fetchedNode[0].detectionSensorConfig?.stateBroadcastSecs = Int32(truncatingIfNeeded: config.stateBroadcastSecs)
				}
				if sessionPasskey != nil {
					fetchedNode[0].sessionPasskey = sessionPasskey
					fetchedNode[0].sessionExpiration = Date().addingTimeInterval(300)
				}
				do {
					try modelContext.save()
					Logger.data.info("💾 [DetectionSensorConfigEntity] Updated for node: \(nodeNum.toHex(), privacy: .public)")
					
				} catch {
					let nsError = error as NSError
					Logger.data.error("💥 [DetectionSensorConfigEntity] Error Updating Core Data : \(nsError, privacy: .public)")
				}
				
			} else {
				Logger.data.error("💥 [DetectionSensorConfigEntity] No Nodes found in local database matching node \(nodeNum.toHex(), privacy: .public) unable to save Detection Sensor Module Config")
			}
			
		} catch {
			let nsError = error as NSError
			Logger.data.error("💥 [DetectionSensorConfigEntity] Fetching node for core data failed: \(nsError, privacy: .public)")
		}
	}

	func upsertExternalNotificationModuleConfigPacket(config: ModuleConfig.ExternalNotificationConfig, nodeNum: Int64, sessionPasskey: Data? = Data()) {
		
		let logString = String.localizedStringWithFormat("External Notification module config received: %@".localized, String(nodeNum))
		Logger.data.info("📣 \(logString, privacy: .public)")
		
		let fetchNum = Int64(nodeNum)
			var fetchNodeInfoRequest = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate<NodeInfoEntity> { $0.num == fetchNum })
			fetchNodeInfoRequest.fetchLimit = 1
		do {
			let fetchedNode = try modelContext.fetch(fetchNodeInfoRequest)
			// Found a node, save External Notificaitone Config
			if !fetchedNode.isEmpty {
				
				if fetchedNode[0].externalNotificationConfig == nil {
					let newExternalNotificationConfig = ExternalNotificationConfigEntity()
					modelContext.insert(newExternalNotificationConfig)
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
				if sessionPasskey != nil {
					fetchedNode[0].sessionPasskey = sessionPasskey
					fetchedNode[0].sessionExpiration = Date().addingTimeInterval(300)
				}
				do {
					try modelContext.save()
					Logger.data.info("💾 [ExternalNotificationConfigEntity] Updated for node: \(nodeNum.toHex(), privacy: .public)")
				} catch {
					let nsError = error as NSError
					Logger.data.error("💥 [ExternalNotificationConfigEntity] Error Updating Core Data : \(nsError, privacy: .public)")
				}
			} else {
				Logger.data.error("💥 [ExternalNotificationConfigEntity] No Nodes found in local database matching node \(nodeNum.toHex(), privacy: .public) unable to save External Notification Module Config")
			}
		} catch {
			let nsError = error as NSError
			Logger.data.error("💥 [ExternalNotificationConfigEntity] Fetching node for core data failed: \(nsError, privacy: .public)")
		}
	}
	
	func upsertPaxCounterModuleConfigPacket(config: ModuleConfig.PaxcounterConfig, nodeNum: Int64, sessionPasskey: Data? = Data()) {
		
		let logString = String.localizedStringWithFormat("PAX Counter config received: %@".localized, String(nodeNum))
		Logger.data.info("🧑‍🤝‍🧑 \(logString, privacy: .public)")
		
		let fetchNum = Int64(nodeNum)
			var fetchNodeInfoRequest = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate<NodeInfoEntity> { $0.num == fetchNum })
			fetchNodeInfoRequest.fetchLimit = 1
		do {
			let fetchedNode = try modelContext.fetch(fetchNodeInfoRequest)
			// Found a node, save PAX Counter Config
			if !fetchedNode.isEmpty {
				if fetchedNode[0].paxCounterConfig == nil {
					let newPaxCounterConfig = PaxCounterConfigEntity()
					modelContext.insert(newPaxCounterConfig)
					newPaxCounterConfig.enabled = config.enabled
					newPaxCounterConfig.updateInterval = Int32(config.paxcounterUpdateInterval)
					fetchedNode[0].paxCounterConfig = newPaxCounterConfig
				} else {
					fetchedNode[0].paxCounterConfig?.enabled = config.enabled
					fetchedNode[0].paxCounterConfig?.updateInterval = Int32(config.paxcounterUpdateInterval)
				}
				if sessionPasskey != nil {
					fetchedNode[0].sessionPasskey = sessionPasskey
					fetchedNode[0].sessionExpiration = Date().addingTimeInterval(300)
				}
				do {
					try modelContext.save()
					Logger.data.info("💾 [PaxCounterConfigEntity] Updated for node number: \(nodeNum.toHex(), privacy: .public)")
				} catch {
					let nsError = error as NSError
					Logger.data.error("💥 [PaxCounterConfigEntity] Error Updating Core Data: \(nsError, privacy: .public)")
				}
			} else {
				Logger.data.error("💥 [PaxCounterConfigEntity] No Nodes found in local database matching node number \(nodeNum.toHex(), privacy: .public) unable to save PAX Counter Module Config")
			}
		} catch {
			let nsError = error as NSError
			Logger.data.error("💥 [PaxCounterConfigEntity] Fetching node for core data failed: \(nsError, privacy: .public)")
		}
	}

	func upsertRtttlConfigPacket(ringtone: String, nodeNum: Int64, sessionPasskey: Data? = Data()) {
		
		let logString = String.localizedStringWithFormat("RTTTL Ringtone config received: %@".localized, String(nodeNum))
		Logger.data.info("⛰️ \(logString, privacy: .public)")
		
		let fetchNum = Int64(nodeNum)
			var fetchNodeInfoRequest = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate<NodeInfoEntity> { $0.num == fetchNum })
			fetchNodeInfoRequest.fetchLimit = 1
		do {
			let fetchedNode = try modelContext.fetch(fetchNodeInfoRequest)
			// Found a node, save RTTTL Config
			if !fetchedNode.isEmpty {
				if fetchedNode[0].rtttlConfig == nil {
					let newRtttlConfig = RTTTLConfigEntity()
					modelContext.insert(newRtttlConfig)
					newRtttlConfig.ringtone = ringtone
					fetchedNode[0].rtttlConfig = newRtttlConfig
				} else {
					fetchedNode[0].rtttlConfig?.ringtone = ringtone
				}
				if sessionPasskey != nil {
					fetchedNode[0].sessionPasskey = sessionPasskey
					fetchedNode[0].sessionExpiration = Date().addingTimeInterval(300)
				}
				do {
					try modelContext.save()
					Logger.data.info("💾 [RtttlConfigEntity] Updated for node: \(nodeNum.toHex(), privacy: .public)")
				} catch {
					let nsError = error as NSError
					Logger.data.error("💥 [RtttlConfigEntity] Error Updating Core Data: \(nsError, privacy: .public)")
				}
			} else {
				Logger.data.error("💥 [RtttlConfigEntity] No nodes found in local database matching node \(nodeNum.toHex(), privacy: .public) unable to save RTTTL Ringtone Config")
			}
		} catch {
			let nsError = error as NSError
			Logger.data.error("💥 [RtttlConfigEntity] Fetching node for core data failed: \(nsError, privacy: .public)")
		}
	}

	func upsertMqttModuleConfigPacket(config: ModuleConfig.MQTTConfig, nodeNum: Int64, sessionPasskey: Data? = Data()) {
		
		let logString = String.localizedStringWithFormat("MQTT module config received: %@".localized, String(nodeNum))
		Logger.data.info("🌉 \(logString, privacy: .public)")
		
		let fetchNum = Int64(nodeNum)
			var fetchNodeInfoRequest = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate<NodeInfoEntity> { $0.num == fetchNum })
			fetchNodeInfoRequest.fetchLimit = 1
		do {
			let fetchedNode = try modelContext.fetch(fetchNodeInfoRequest)
			// Found a node, save MQTT Config
			if !fetchedNode.isEmpty {
				if fetchedNode[0].mqttConfig == nil {
					let newMQTTConfig = MQTTConfigEntity()
					modelContext.insert(newMQTTConfig)
					newMQTTConfig.enabled = config.enabled
					newMQTTConfig.proxyToClientEnabled = config.proxyToClientEnabled
					newMQTTConfig.address = config.address
					newMQTTConfig.username = config.username
					newMQTTConfig.password = config.password
					newMQTTConfig.root = config.root
					newMQTTConfig.encryptionEnabled = config.encryptionEnabled
					newMQTTConfig.jsonEnabled = config.jsonEnabled
					newMQTTConfig.tlsEnabled = config.tlsEnabled
					newMQTTConfig.mapReportingEnabled = config.mapReportingEnabled
					newMQTTConfig.mapReportingShouldReportLocation = config.mapReportSettings.shouldReportLocation
					newMQTTConfig.mapPositionPrecision = Int32(config.mapReportSettings.positionPrecision)
					newMQTTConfig.mapPublishIntervalSecs = Int32(config.mapReportSettings.publishIntervalSecs)
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
					fetchedNode[0].mqttConfig?.mapReportingEnabled = config.mapReportingEnabled
					fetchedNode[0].mqttConfig?.mapPositionPrecision = Int32(config.mapReportSettings.positionPrecision)
					fetchedNode[0].mqttConfig?.mapPublishIntervalSecs = Int32(config.mapReportSettings.publishIntervalSecs)
				}
				if sessionPasskey != nil {
					fetchedNode[0].sessionPasskey = sessionPasskey
					fetchedNode[0].sessionExpiration = Date().addingTimeInterval(300)
				}
				do {
					try modelContext.save()
					Logger.data.info("💾 [MQTTConfigEntity] Updated for node number: \(nodeNum.toHex(), privacy: .public)")
				} catch {
					let nsError = error as NSError
					Logger.data.error("💥 [MQTTConfigEntity] Error Updating Core Data: \(nsError, privacy: .public)")
				}
			} else {
				Logger.data.error("💥 [MQTTConfigEntity] No Nodes found in local database matching node \(nodeNum.toHex(), privacy: .public) unable to save MQTT Module Config")
			}
		} catch {
			let nsError = error as NSError
			Logger.data.error("💥 [MQTTConfigEntity] Fetching node for core data failed: \(nsError, privacy: .public)")
		}
	}

	func upsertRangeTestModuleConfigPacket(config: ModuleConfig.RangeTestConfig, nodeNum: Int64, sessionPasskey: Data? = Data()) {
		
		let logString = String.localizedStringWithFormat("Range Test module config received: %@".localized, String(nodeNum))
		Logger.data.info("⛰️ \(logString, privacy: .public)")
		
		let fetchNum = Int64(nodeNum)
			var fetchNodeInfoRequest = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate<NodeInfoEntity> { $0.num == fetchNum })
			fetchNodeInfoRequest.fetchLimit = 1
		do {
			let fetchedNode = try modelContext.fetch(fetchNodeInfoRequest)
			// Found a node, save Device Config
			if !fetchedNode.isEmpty {
				if fetchedNode[0].rangeTestConfig == nil {
					let newRangeTestConfig = RangeTestConfigEntity()
					modelContext.insert(newRangeTestConfig)
					newRangeTestConfig.sender = Int32(config.sender)
					newRangeTestConfig.enabled = config.enabled
					newRangeTestConfig.save = config.save
					fetchedNode[0].rangeTestConfig = newRangeTestConfig
				} else {
					fetchedNode[0].rangeTestConfig?.sender = Int32(config.sender)
					fetchedNode[0].rangeTestConfig?.enabled = config.enabled
					fetchedNode[0].rangeTestConfig?.save = config.save
				}
				if sessionPasskey != nil {
					fetchedNode[0].sessionPasskey = sessionPasskey
					fetchedNode[0].sessionExpiration = Date().addingTimeInterval(300)
				}
				do {
					try modelContext.save()
					Logger.data.info("💾 [RangeTestConfigEntity] Updated for node: \(nodeNum.toHex(), privacy: .public)")
				} catch {
					let nsError = error as NSError
					Logger.data.error("💥 [RangeTestConfigEntity] Error Updating Core Data: \(nsError, privacy: .public)")
				}
			} else {
				Logger.data.error("💥 [RangeTestConfigEntity] No Nodes found in local database matching node \(nodeNum.toHex(), privacy: .public) unable to save Range Test Module Config")
			}
		} catch {
			let nsError = error as NSError
			Logger.data.error("💥 [RangeTestConfigEntity] Fetching node for core data failed: \(nsError, privacy: .public)")
		}
	}

	func upsertSerialModuleConfigPacket(config: ModuleConfig.SerialConfig, nodeNum: Int64, sessionPasskey: Data? = Data()) {
		
		let logString = String.localizedStringWithFormat("Serial module config received: %@".localized, String(nodeNum))
		Logger.data.info("🤖 \(logString, privacy: .public)")
		
		let fetchNum = Int64(nodeNum)
			var fetchNodeInfoRequest = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate<NodeInfoEntity> { $0.num == fetchNum })
			fetchNodeInfoRequest.fetchLimit = 1
		do {
			let fetchedNode = try modelContext.fetch(fetchNodeInfoRequest)
			// Found a node, save Device Config
			if !fetchedNode.isEmpty {
				if fetchedNode[0].serialConfig == nil {
					let newSerialConfig = SerialConfigEntity()
					modelContext.insert(newSerialConfig)
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
				if sessionPasskey != nil {
					fetchedNode[0].sessionPasskey = sessionPasskey
					fetchedNode[0].sessionExpiration = Date().addingTimeInterval(300)
				}
				do {
					try modelContext.save()
					Logger.data.info("💾 [SerialConfigEntity]Updated Serial Module Config for node: \(nodeNum.toHex(), privacy: .public)")
				} catch {
					
					
					let nsError = error as NSError
					Logger.data.error("💥 [SerialConfigEntity] Error Updating Core Data: \(nsError, privacy: .public)")
				}
			} else {
				Logger.data.error("💥 [SerialConfigEntity] No Nodes found in local database matching node \(nodeNum.toHex(), privacy: .public) unable to save Serial Module Config")
			}
		} catch {
			
			let nsError = error as NSError
			Logger.data.error("💥 [SerialConfigEntity] Fetching node for core data failed: \(nsError, privacy: .public)")
		}
	}

	func upsertStoreForwardModuleConfigPacket(config: ModuleConfig.StoreForwardConfig, nodeNum: Int64, sessionPasskey: Data? = Data()) {
		
		let logString = String.localizedStringWithFormat("Store & Forward module config received: %@".localized, String(nodeNum))
		Logger.data.info("📬 \(logString, privacy: .public)")
		
		let fetchNum = Int64(nodeNum)
			var fetchNodeInfoRequest = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate<NodeInfoEntity> { $0.num == fetchNum })
			fetchNodeInfoRequest.fetchLimit = 1
		do {
			let fetchedNode = try modelContext.fetch(fetchNodeInfoRequest)
			// Found a node, save Store & Forward Sensor Config
			if !fetchedNode.isEmpty {
				if fetchedNode[0].storeForwardConfig == nil {
					let newConfig = StoreForwardConfigEntity()
					modelContext.insert(newConfig)
					newConfig.enabled = config.enabled
					newConfig.heartbeat = config.heartbeat
					newConfig.records = Int32(config.records)
					newConfig.historyReturnMax = Int32(config.historyReturnMax)
					newConfig.historyReturnWindow = Int32(config.historyReturnWindow)
					newConfig.isRouter = config.isServer
					fetchedNode[0].storeForwardConfig = newConfig
				} else {
					fetchedNode[0].storeForwardConfig?.enabled = config.enabled
					fetchedNode[0].storeForwardConfig?.heartbeat = config.heartbeat
					fetchedNode[0].storeForwardConfig?.records = Int32(config.records)
					fetchedNode[0].storeForwardConfig?.historyReturnMax = Int32(config.historyReturnMax)
					fetchedNode[0].storeForwardConfig?.historyReturnWindow = Int32(config.historyReturnWindow)
				}
				if sessionPasskey != nil {
					fetchedNode[0].sessionPasskey = sessionPasskey
					fetchedNode[0].sessionExpiration = Date().addingTimeInterval(300)
				}
				do {
					try modelContext.save()
					Logger.data.info("💾 [StoreForwardConfigEntity] Updated for node: \(nodeNum.toHex(), privacy: .public)")
				} catch {
					let nsError = error as NSError
					Logger.data.error("💥 [StoreForwardConfigEntity] Error Updating Core Data: \(nsError, privacy: .public)")
				}
			} else {
				Logger.data.error("💥 [StoreForwardConfigEntity] No Nodes found in local database matching node \(nodeNum.toHex(), privacy: .public) unable to save Store & Forward Module Config")
			}
		} catch {
			let nsError = error as NSError
			Logger.data.error("💥 [StoreForwardConfigEntity] Fetching node for core data failed: \(nsError, privacy: .public)")
		}
	}

	func upsertTelemetryModuleConfigPacket(config: ModuleConfig.TelemetryConfig, nodeNum: Int64, sessionPasskey: Data? = Data()) {
		
		let logString = String.localizedStringWithFormat("Telemetry module config received: %@".localized, String(nodeNum))
		Logger.data.info("📈 \(logString, privacy: .public)")
		
		let fetchNum = Int64(nodeNum)
			var fetchNodeInfoRequest = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate<NodeInfoEntity> { $0.num == fetchNum })
			fetchNodeInfoRequest.fetchLimit = 1
		do {
			let fetchedNode = try modelContext.fetch(fetchNodeInfoRequest)
			// Found a node, save Telemetry Config
			if !fetchedNode.isEmpty {
				if fetchedNode[0].telemetryConfig == nil {
					let newTelemetryConfig = TelemetryConfigEntity()
					modelContext.insert(newTelemetryConfig)
					newTelemetryConfig.deviceUpdateInterval = Int32(truncatingIfNeeded: config.deviceUpdateInterval)
					newTelemetryConfig.deviceTelemetryEnabled = config.deviceTelemetryEnabled
					newTelemetryConfig.environmentUpdateInterval = Int32(truncatingIfNeeded: config.environmentUpdateInterval)
					newTelemetryConfig.environmentMeasurementEnabled = config.environmentMeasurementEnabled
					newTelemetryConfig.environmentScreenEnabled = config.environmentScreenEnabled
					newTelemetryConfig.environmentDisplayFahrenheit = config.environmentDisplayFahrenheit
					newTelemetryConfig.powerMeasurementEnabled = config.powerMeasurementEnabled
					newTelemetryConfig.powerUpdateInterval = Int32(truncatingIfNeeded: config.powerUpdateInterval)
					newTelemetryConfig.powerScreenEnabled = config.powerScreenEnabled
					fetchedNode[0].telemetryConfig = newTelemetryConfig
				} else {
					fetchedNode[0].telemetryConfig?.deviceUpdateInterval = Int32(truncatingIfNeeded: config.deviceUpdateInterval)
					fetchedNode[0].telemetryConfig?.deviceTelemetryEnabled = config.deviceTelemetryEnabled
					fetchedNode[0].telemetryConfig?.environmentUpdateInterval = Int32(truncatingIfNeeded: config.environmentUpdateInterval)
					fetchedNode[0].telemetryConfig?.environmentMeasurementEnabled = config.environmentMeasurementEnabled
					fetchedNode[0].telemetryConfig?.environmentScreenEnabled = config.environmentScreenEnabled
					fetchedNode[0].telemetryConfig?.environmentDisplayFahrenheit = config.environmentDisplayFahrenheit
					fetchedNode[0].telemetryConfig?.powerMeasurementEnabled = config.powerMeasurementEnabled
					fetchedNode[0].telemetryConfig?.powerUpdateInterval = Int32(truncatingIfNeeded: config.powerUpdateInterval)
					fetchedNode[0].telemetryConfig?.powerScreenEnabled = config.powerScreenEnabled
				}
				if sessionPasskey != nil {
					fetchedNode[0].sessionPasskey = sessionPasskey
					fetchedNode[0].sessionExpiration = Date().addingTimeInterval(300)
				}
				do {
					try modelContext.save()
					Logger.data.info("💾 [TelemetryConfigEntity] Updated Telemetry Module Config for node: \(nodeNum.toHex(), privacy: .public)")
					
				} catch {
					let nsError = error as NSError
					Logger.data.error("💥 [TelemetryConfigEntity] Error Updating Core Data: \(nsError, privacy: .public)")
				}
				
			} else {
				Logger.data.error("💥 [TelemetryConfigEntity] No Nodes found in local database matching node \(nodeNum.toHex(), privacy: .public) unable to save Telemetry Module Config")
			}
			
		} catch {
			let nsError = error as NSError
			Logger.data.error("💥 [TelemetryConfigEntity] Fetching node for core data TelemetryConfigEntity failed: \(nsError, privacy: .public)")
		}
	}

	func upsertTAKModuleConfigPacket(config: ModuleConfig.TAKConfig, nodeNum: Int64, sessionPasskey: Data? = Data()) {

		let logString = String.localizedStringWithFormat("TAK module config received: %@".localized, String(nodeNum))
		Logger.data.info("🎯 \(logString, privacy: .public)")

		let fetchNum = Int64(nodeNum)
			var fetchNodeInfoRequest = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate<NodeInfoEntity> { $0.num == fetchNum })
			fetchNodeInfoRequest.fetchLimit = 1
		do {
			let fetchedNode = try modelContext.fetch(fetchNodeInfoRequest)
			if !fetchedNode.isEmpty {
				if fetchedNode[0].takConfig == nil {
					let newTAKConfig = TAKConfigEntity()
					modelContext.insert(newTAKConfig)
					newTAKConfig.team = Int32(config.team.rawValue)
					newTAKConfig.role = Int32(config.role.rawValue)
					fetchedNode[0].takConfig = newTAKConfig
				} else {
					fetchedNode[0].takConfig?.team = Int32(config.team.rawValue)
					fetchedNode[0].takConfig?.role = Int32(config.role.rawValue)
				}
				if sessionPasskey != nil {
					fetchedNode[0].sessionPasskey = sessionPasskey
					fetchedNode[0].sessionExpiration = Date().addingTimeInterval(300)
				}
				do {
					try modelContext.save()
					Logger.data.info("💾 [TAKConfigEntity] Updated TAK Module Config for node: \(nodeNum.toHex(), privacy: .public)")
				} catch {
					let nsError = error as NSError
					Logger.data.error("💥 [TAKConfigEntity] Error Updating Core Data: \(nsError, privacy: .public)")
				}
			} else {
				Logger.data.error("💥 [TAKConfigEntity] No Nodes found in local database matching node \(nodeNum.toHex(), privacy: .public) unable to save TAK Module Config")
			}
		} catch {
			let nsError = error as NSError
			Logger.data.error("💥 [TAKConfigEntity] Fetching node for core data failed: \(nsError, privacy: .public)")
		}
	}
}
