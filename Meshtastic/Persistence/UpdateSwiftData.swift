//
//  UpdateSwiftData.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/3/22.

@preconcurrency import SwiftData
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
			guard !staleNodes.isEmpty else {
				Logger.data.info("💾 [NodeInfoEntity] No stale nodes to clear")
				return false
			}
			let deletedNodes = staleNodes.count
			for node in staleNodes {
				modelContext.delete(node)
			}
			try modelContext.save()
			Logger.data.info("💾 [NodeInfoEntity] Cleared \(deletedNodes) stale nodes")
			return true
		} catch {
			Logger.data.error("💥 [NodeInfoEntity] Error deleting stale nodes: \(error.localizedDescription, privacy: .public)")
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
			Logger.data.error("💥 [NodeInfoEntity] Error clearing pax: \(error.localizedDescription, privacy: .public)")
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
			Logger.data.error("💥 [NodeInfoEntity] Error clearing positions: \(error.localizedDescription, privacy: .public)")
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
			Logger.data.error("💥 [NodeInfoEntity] Error clearing telemetry: \(error.localizedDescription, privacy: .public)")
		}
		return false
	}
	
	public func deleteChannelMessages(channel: ChannelEntity) {
		let channelIndex = channel.index
		let descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> { msg in
				msg.channel == channelIndex && msg.isEmoji == false
			}
		)
		do {
			let objects = try modelContext.fetch(descriptor)
			for object in objects where object.toUser == nil {
				modelContext.delete(object)
			}
			try modelContext.save()
		} catch {
			Logger.data.error("💥 [MessageEntity] Error deleting channel messages: \(error.localizedDescription, privacy: .public)")
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
			Logger.data.error("💥 [MessageEntity] Error deleting user messages: \(error.localizedDescription, privacy: .public)")
		}
	}
	
	public func clearDatabase(includeRoutes: Bool, preserveFavorites: Bool = false) {
		// Delete entities that are on the inverse side of many-to-many
		// relationships first to avoid constraint trigger violations.
		do {
			try modelContext.delete(model: DeviceHardwareTagEntity.self)
			try modelContext.delete(model: DeviceHardwareImageEntity.self)
		} catch {
			Logger.data.error("\(error.localizedDescription, privacy: .public)")
		}

		// Collect favorite node IDs before the delete loop so we can
		// skip related entities that belong to preserved nodes.
		var favoriteNodeNums: Set<Int64> = []
		if preserveFavorites {
			let favDescriptor = FetchDescriptor<NodeInfoEntity>(
				predicate: #Predicate<NodeInfoEntity> { $0.favorite == true }
			)
			favoriteNodeNums = Set((try? modelContext.fetch(favDescriptor))?.map(\.num) ?? [])
		}

		let allModels: [any PersistentModel.Type] = MeshtasticSchema.allModels
		for modelType in allModels {
			if !includeRoutes && (modelType == RouteEntity.self || modelType == LocationEntity.self) {
				continue
			}
			if modelType == DeviceHardwareTagEntity.self || modelType == DeviceHardwareImageEntity.self {
				continue // already deleted above
			}
			if preserveFavorites && modelType == NodeInfoEntity.self {
				// Keep favorited nodes so the device and app stay in sync when the
				// firmware is told to preserve favorites (nodedbReset = true).
				let descriptor = FetchDescriptor<NodeInfoEntity>(
					predicate: #Predicate<NodeInfoEntity> { node in
						node.favorite == false
					}
				)
				do {
					let nonFavorites = try modelContext.fetch(descriptor)
					for node in nonFavorites {
						modelContext.delete(node)
					}
				} catch {
					Logger.data.error("\(error.localizedDescription, privacy: .public)")
				}
				continue
			}
			if preserveFavorites && modelType == UserEntity.self {
				// Only delete users not belonging to favorite nodes.
				do {
					let allUsers = try modelContext.fetch(FetchDescriptor<UserEntity>())
					for user in allUsers {
						if let userNodeNum = user.userNode?.num, favoriteNodeNums.contains(userNodeNum) {
							continue
						}
						modelContext.delete(user)
					}
				} catch {
					Logger.data.error("\(error.localizedDescription, privacy: .public)")
				}
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
			Logger.data.error("💥 Failed to save after clearing database: \(error.localizedDescription, privacy: .public)")
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
		
		// Skip routing packets with no rxTime — these are locally-generated implicit ACKs
		// that don't represent actual RF contact with the remote node.
		let isImplicitAck = packet.decoded.portnum == .routingApp && packet.rxTime == 0
		
		let num = Int64(packet.from)
		var descriptor = FetchDescriptor<NodeInfoEntity>(
			predicate: #Predicate<NodeInfoEntity> { $0.num == num }
		)
		descriptor.fetchLimit = 1
		
		do {
			if let node = try modelContext.fetch(descriptor).first {
				node.id = Int64(packet.from)
				node.num = Int64(packet.from)
				
				// Single source of truth for lastHeard on received packets: this runs for
				// every packet (mirroring firmware NodeDB::updateFrom), so the per-packet
				// handlers no longer touch lastHeard for remote nodes.
				if !isImplicitAck {
					if packet.rxTime > 0 {
						node.lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(packet.rxTime)))
					} else {
						node.lastHeard = Date()
					}
				}
				
				node.snr = packet.rxSnr
				node.rssi = packet.rxRssi
				node.viaMqtt = packet.viaMqtt
				
				if packet.hopStart != 0 && packet.hopLimit <= packet.hopStart {
					node.hopsAway = Int32(packet.hopStart - packet.hopLimit)
					Logger.data.debug("💾 [updateAnyPacketFrom] Updating node \(packet.from.toHex(), privacy: .public) hopsAway=\(node.hopsAway)")
				}
				
				// Changes are saved by the subsequent packet handler's save call
				Logger.data.debug("💾 [updateAnyPacketFrom] Updated node \(node.num.toHex(), privacy: .public) snr=\(node.snr), rssi=\(node.rssi) from packet \(packet.id.toHex(), privacy: .public)")
			}
		} catch {
			Logger.data.error("💥 [updateAnyPacketFrom] fetch data error")
		}
	}

	/// Compact, human-readable summary of a NodeInfo packet's `User` payload, appended to the mesh
	/// log line so the Packet Stream shows the decoded protobuf at a glance (not raw JSON), e.g.
	/// " — 🔐 Long Name (SHRT) client TBEAM". Returns "" when there's no usable identity.
	private func nodeInfoLogDetails(from packet: MeshPacket) -> String {
		guard let user = try? User(serializedBytes: packet.decoded.payload), !user.id.isEmpty else {
			return ""
		}
		var parts: [String] = []
		let long = user.longName.trimmingCharacters(in: .whitespacesAndNewlines)
		let short = user.shortName.trimmingCharacters(in: .whitespacesAndNewlines)
		switch (long.isEmpty, short.isEmpty) {
		case (false, false): parts.append("\(long) (\(short))")
		case (false, true):  parts.append(long)
		case (true, false):  parts.append(short)
		case (true, true):   break
		}
		parts.append(String(describing: user.role))
		let hw = String(describing: user.hwModel).uppercased()
		if hw != "UNSET" { parts.append(hw) }
		if user.isLicensed { parts.append("licensed") }
		if user.hasIsUnmessagable && user.isUnmessagable { parts.append("unmessagable") }
		// Lock leads the line so PKI-encrypted nodes are obvious at a glance.
		if !user.publicKey.isEmpty { parts.insert("🔐", at: 0) }
		return parts.isEmpty ? "" : " — " + parts.joined(separator: " ")
	}

	/// - Parameter overTheMesh: true when this NodeInfo arrived as an over-the-air packet from a
	///   remote node — logged on .mesh so it appears in the Packet Stream. false for local updates
	///   (e.g. the favorite action), which did not cross the mesh and log on .data.
	func upsertNodeInfoPacket (packet: MeshPacket, favorite: Bool = false, overTheMesh: Bool = true) {

		let details = nodeInfoLogDetails(from: packet)
		if overTheMesh {
			Logger.mesh.info("📟 [Node Info] packet received from \(packet.from.toHex(), privacy: .public)\(details, privacy: .public)")
		} else {
			Logger.data.info("📟 [Node Info] packet received from \(packet.from.toHex(), privacy: .public)\(details, privacy: .public)")
		}

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
					newNode.favorite = nodeInfoMessage.isFavorite
				}
				if packet.hopStart != 0 && packet.hopLimit <= packet.hopStart {
					newNode.hopsAway = Int32(packet.hopStart - packet.hopLimit)
				}
				
				if let newUserMessage = try? User(serializedBytes: packet.decoded.payload) {
					
					if newUserMessage.id.isEmpty {
						if packet.from > Constants.minimumNodeNum {
							do {
								let newUser = try createUser(num: Int64(truncatingIfNeeded: packet.from), context: modelContext)
								newNode.user = newUser
							} catch PersistenceError.invalidInput(let message) {
								Logger.data.error("Error Creating a new UserEntity (Invalid Input) from node number: \(packet.from, privacy: .public) Error:  \(message, privacy: .public)")
							} catch {
								Logger.data.error("Error Creating a new UserEntity from node number: \(packet.from, privacy: .public) Error:  \(error.localizedDescription, privacy: .public)")
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
						} catch PersistenceError.invalidInput(let message) {
							Logger.data.error("Error Creating a new UserEntity (Invalid Input) from node number: \(packet.from, privacy: .public) Error:  \(message, privacy: .public)")
						} catch {
							Logger.data.error("Error Creating a new UserEntity from node number: \(packet.from, privacy: .public) Error:  \(error.localizedDescription, privacy: .public)")
						}
					}
				}
				// User is messed up and has failed to create at least once, if this fails bail out
				if newNode.user == nil && packet.from > Constants.minimumNodeNum {
					do {
						let newUser = try createUser(num: Int64(packet.from), context: modelContext)
						newNode.user = newUser
					} catch PersistenceError.invalidInput(let message) {
						Logger.data.error("Error Creating a new UserEntity (Invalid Input) from node number: \(packet.from, privacy: .public) Error:  \(message, privacy: .public)")
						return
					} catch {
						Logger.data.error("Error Creating a new UserEntity from node number: \(packet.from, privacy: .public) Error:  \(error.localizedDescription, privacy: .public)")
						return
					}
				}
				
				// Over-the-mesh ingestion is high-frequency, so debounce; local actions
				// (e.g. adding a contact / favoriting) persist immediately for snappy UI.
				if overTheMesh { scheduleDebouncedSave() } else { savePendingChanges() }
				Logger.data.debug("💾 [Node Info] Buffered a Node Info for node number: \(packet.from.toHex(), privacy: .public)")
				
			} else {
				// Update an existing node
				if packet.to == Constants.maximumNodeNum || packet.to == UserDefaults.preferredPeripheralNum {
					fetchedNode[0].channel = Int32(packet.channel)
				}
				
				if let nodeInfoMessage = try? NodeInfo(serializedBytes: packet.decoded.payload) {

					fetchedNode[0].favorite = nodeInfoMessage.isFavorite
					if nodeInfoMessage.hasDeviceMetrics {
						let telemetry = TelemetryEntity()
						modelContext.insert(telemetry)
						telemetry.batteryLevel = Int32(nodeInfoMessage.deviceMetrics.batteryLevel)
						telemetry.voltage = nodeInfoMessage.deviceMetrics.voltage
						telemetry.channelUtilization = nodeInfoMessage.deviceMetrics.channelUtilization
						telemetry.airUtilTx = nodeInfoMessage.deviceMetrics.airUtilTx
						telemetry.nodeTelemetry = fetchedNode[0]
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
					} catch PersistenceError.invalidInput(let message) {
						Logger.data.error("Error Creating a new UserEntity on an existing node (Invalid Input) from node number: \(packet.from, privacy: .public) Error:  \(message, privacy: .public)")
					} catch {
						Logger.data.error("Error Creating a new UserEntity on an existing node from node number: \(packet.from, privacy: .public) Error:  \(error.localizedDescription, privacy: .public)")
					}
				}
				if overTheMesh { scheduleDebouncedSave() } else { savePendingChanges() }
				Logger.data.debug("💾 [NodeInfoEntity] Buffered update from Node Info App Packet For: \(fetchedNode[0].num.toHex(), privacy: .public)")
			}
		} catch {
			Logger.data.error("💥 [NodeInfoEntity] fetch data error for NODEINFO_APP")
		}
	}
	
	/// Compact, human-readable summary of a Position packet's payload for the mesh log line, e.g.
	/// " — 40.78661,-119.20650 1234m 8 sats 14-bit". Returns "" for empty/null-island positions.
	private func positionLogDetails(from packet: MeshPacket) -> String {
		guard let pos = try? Position(serializedBytes: packet.decoded.payload),
			  pos.latitudeI != 0 || pos.longitudeI != 0 else {
			return ""
		}
		var parts: [String] = []
		parts.append(String(format: "%.5f,%.5f", Double(pos.latitudeI) / 1e7, Double(pos.longitudeI) / 1e7))
		if pos.altitude != 0 { parts.append("\(pos.altitude)m") }
		if pos.satsInView > 0 { parts.append("\(pos.satsInView) sats") }
		if pos.precisionBits > 0 && pos.precisionBits < 32 { parts.append("\(pos.precisionBits)-bit") }
		return parts.isEmpty ? "" : " — " + parts.joined(separator: " ")
	}

	func upsertPositionPacket (packet: MeshPacket) {

		Logger.mesh.info("📍 [Position] packet received from \(packet.from.toHex(), privacy: .public)\(self.positionLogDetails(from: packet), privacy: .public)")
		
		let fetchNum = Int64(packet.from)
			var fetchNodePositionRequest = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate<NodeInfoEntity> { $0.num == fetchNum })
			fetchNodePositionRequest.fetchLimit = 1
		do {
			
			if let positionMessage = try? Position(serializedBytes: packet.decoded.payload) {
				
				/// Don't save placeholder position packets from null island (0, 0) or Apple Park.
				if positionMessage.hasValidCoordinates {
					var fetchedNode = try modelContext.fetch(fetchNodePositionRequest)
					// Create a stub node if one doesn't exist yet — it will be updated when the NodeInfo packet arrives
					if fetchedNode.isEmpty {
						let newNode = createNodeInfo(num: Int64(packet.from), context: modelContext)
						newNode.lastHeard = Date()
						fetchedNode = [newNode]
						Logger.data.debug("📍 [Position] created stub node for: \(packet.from.toHex(), privacy: .public)")
					}
					if fetchedNode.count == 1 {
						
						let posNum = Int64(packet.from)
						// Previous latest is tracked directly on the node — no PositionEntity table scan.
						let previousLatest = fetchedNode[0].latestPosition
						previousLatest?.latest = false

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

						// Assign to the node and record as the new latest — O(1), no table scan.
						position.nodePosition = fetchedNode[0]
						fetchedNode[0].latestPositionCache = position

						if position.precisionBits == 32 || position.precisionBits == 0 {
							// Full precision: drop a near-duplicate of the previous latest (within 9m).
							if let previousLatest,
								let prevCoord = previousLatest.nodeCoordinate,
								let positionCoord = position.nodeCoordinate,
								prevCoord.distance(from: positionCoord) < 9.0 {
								modelContext.delete(previousLatest)
							}
						} else {
							// Reduced accuracy: keep no history. Delete this node's older positions via its own
							// relationship (small for reduced-accuracy nodes) instead of a global table scan.
							for old in fetchedNode[0].positions where !old.latest {
								modelContext.delete(old)
							}
						}

						// Keep the history cap as a soft cap during packet bursts; the
						// count/sort/delete prune pass is expensive with large node stores.
						if shouldPrunePositionHistory(for: posNum) {
							let countDescriptor = FetchDescriptor<PositionEntity>(
								predicate: #Predicate<PositionEntity> { $0.nodePosition?.num == posNum }
							)
							let totalCount = try modelContext.fetchCount(countDescriptor)
							if totalCount > MeshPackets.maxPositionHistoryPerNode {
								let excess = totalCount - MeshPackets.maxPositionHistoryPerNode
								var pruneDescriptor = FetchDescriptor<PositionEntity>(
									predicate: #Predicate<PositionEntity> { $0.nodePosition?.num == posNum && $0.latest == false },
									sortBy: [SortDescriptor(\PositionEntity.time, order: .forward)]
								)
								pruneDescriptor.fetchLimit = excess
								let toDelete = try modelContext.fetch(pruneDescriptor)
								for old in toDelete {
									modelContext.delete(old)
								}
							}
						}

						fetchedNode[0].channel = Int32(packet.channel)
						
						scheduleDebouncedSave()
						Logger.data.debug("📍 [Position] buffered for Node: \(fetchedNode[0].num.toHex(), privacy: .public)")
					}
				} else {
					// Valid POSITION_APP packet that carries no usable coordinates (e.g. a node with no
					// GPS fix sending only a timestamp, or a null-island/Apple-Park placeholder). This is
					// expected — there's simply nothing to plot — so log it as debug rather than an error.
					Logger.data.debug("📍 [Position] packet without coordinates from \(packet.from.toHex(), privacy: .public) — nothing to plot")
				}
			}
		} catch {
			Logger.data.error("💥 Error Deserializing POSITION_APP packet.")
		}
	}
	
	func upsertBluetoothConfigPacket(config: Config.BluetoothConfig, nodeNum: Int64, sessionPasskey: Data? = Data()) {
		
		let logString = String.localizedStringWithFormat("Bluetooth config received: %@".localized, String(nodeNum))
		Logger.admin.info("📶 \(logString, privacy: .public)")
		
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
				savePendingChanges()
					Logger.data.info("💾 [BluetoothConfigEntity] Updated for node: \(nodeNum.toHex(), privacy: .public)")
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
		Logger.admin.info("📟 \(logString, privacy: .public)")
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
				savePendingChanges()
					Logger.data.info("💾 [DeviceConfigEntity] Updated Device Config for node number: \(nodeNum.toHex(), privacy: .public)")
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
					newDisplayConfig.compassOrientation = Int32(config.compassOrientation.rawValue)
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
					fetchedNode[0].displayConfig?.compassOrientation = Int32(config.compassOrientation.rawValue)
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
				savePendingChanges()
				Logger.data.info("💾 [DisplayConfigEntity] Updated for node: \(nodeNum.toHex(), privacy: .public)")
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
				savePendingChanges()
					Logger.data.info("💾 [LoRaConfigEntity] Updated for node: \(nodeNum.toHex(), privacy: .public)")
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
					newNetworkConfig.ntpServer = config.ntpServer
					newNetworkConfig.ethEnabled = config.ethEnabled
					newNetworkConfig.enabledProtocols = Int32(config.enabledProtocols)
					newNetworkConfig.addressMode = Int32(config.addressMode.rawValue)
					newNetworkConfig.rsyslogServer = config.rsyslogServer
					newNetworkConfig.ip = Int32(bitPattern: config.ipv4Config.ip)
					newNetworkConfig.gateway = Int32(bitPattern: config.ipv4Config.gateway)
					newNetworkConfig.subnet = Int32(bitPattern: config.ipv4Config.subnet)
					newNetworkConfig.dns = Int32(bitPattern: config.ipv4Config.dns)
					fetchedNode[0].networkConfig = newNetworkConfig
				} else {
					fetchedNode[0].networkConfig?.ethEnabled = config.ethEnabled
					fetchedNode[0].networkConfig?.wifiEnabled = config.wifiEnabled
					fetchedNode[0].networkConfig?.wifiSsid = config.wifiSsid
					fetchedNode[0].networkConfig?.wifiPsk = config.wifiPsk
					fetchedNode[0].networkConfig?.ntpServer = config.ntpServer
					fetchedNode[0].networkConfig?.enabledProtocols = Int32(config.enabledProtocols)
					fetchedNode[0].networkConfig?.addressMode = Int32(config.addressMode.rawValue)
					fetchedNode[0].networkConfig?.rsyslogServer = config.rsyslogServer
					fetchedNode[0].networkConfig?.ip = Int32(bitPattern: config.ipv4Config.ip)
					fetchedNode[0].networkConfig?.gateway = Int32(bitPattern: config.ipv4Config.gateway)
					fetchedNode[0].networkConfig?.subnet = Int32(bitPattern: config.ipv4Config.subnet)
					fetchedNode[0].networkConfig?.dns = Int32(bitPattern: config.ipv4Config.dns)
				}
				if sessionPasskey != nil {
					fetchedNode[0].sessionPasskey = sessionPasskey
					fetchedNode[0].sessionExpiration = Date().addingTimeInterval(300)
				}
				savePendingChanges()
				Logger.data.info("💾 [NetworkConfigEntity] Updated Network Config for node: \(nodeNum.toHex(), privacy: .public)")
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
				savePendingChanges()
					Logger.data.info("💾 [PositionConfigEntity] Updated for node: \(nodeNum.toHex(), privacy: .public)")
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
				savePendingChanges()
					Logger.data.info("💾 [PowerConfigEntity] Updated Power Config for node: \(nodeNum.toHex(), privacy: .public)")
			} else {
				Logger.data.error("💥 [PowerConfigEntity] No Nodes found in local database matching node \(nodeNum.toHex(), privacy: .public) unable to save Power Config")
			}
		} catch {
			let nsError = error as NSError
			Logger.data.error("💥 [PowerConfigEntity] Fetching node for core data failed: \(nsError, privacy: .public)")
		}
	}
	
	func upsertSecurityConfigPacket(config: Config.SecurityConfig, nodeNum: Int64, sessionPasskey: Data? = Data()) {
		
		let logString = String.localizedStringWithFormat("Security config received: @".localized, String(nodeNum))
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
						if config.adminKey.count > 1 {
							newSecurityConfig.adminKey2 = config.adminKey[1]
						}
						if config.adminKey.count > 2 {
							newSecurityConfig.adminKey3 = config.adminKey[2]
						}
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
				savePendingChanges()
				Logger.data.info("💾 [SecurityConfigEntity] Updated Security Config for node: \(nodeNum.toHex(), privacy: .public)")
			} else {
				Logger.data.error("💥 [SecurityConfigEntity] No Nodes found in local database matching node \(nodeNum.toHex(), privacy: .public) unable to save Security Config")
			}
		} catch {
			let nsError = error as NSError
			Logger.data.error("💥 [SecurityConfigEntity] Fetching node for core data failed: \(nsError, privacy: .public)")
		}
	}
	
	func upsertAudioModuleConfigPacket(config: ModuleConfig.AudioConfig, nodeNum: Int64, sessionPasskey: Data? = Data()) {

		let logString = String.localizedStringWithFormat("Audio module config received: %@".localized, String(nodeNum))
		Logger.data.info("🔊 \(logString, privacy: .public)")

		let fetchNum = Int64(nodeNum)
			var fetchNodeInfoRequest = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate<NodeInfoEntity> { $0.num == fetchNum })
			fetchNodeInfoRequest.fetchLimit = 1
		do {
			let fetchedNode = try modelContext.fetch(fetchNodeInfoRequest)
			if !fetchedNode.isEmpty {
				if fetchedNode[0].audioConfig == nil {
					let newAudioConfig = AudioConfigEntity()
					modelContext.insert(newAudioConfig)
					newAudioConfig.codec2Enabled = config.codec2Enabled
					newAudioConfig.pttPin = Int32(config.pttPin)
					newAudioConfig.bitrate = Int32(config.bitrate.rawValue)
					newAudioConfig.i2sWs = Int32(config.i2SWs)
					newAudioConfig.i2sSd = Int32(config.i2SSd)
					newAudioConfig.i2sDin = Int32(config.i2SDin)
					newAudioConfig.i2sSck = Int32(config.i2SSck)
					fetchedNode[0].audioConfig = newAudioConfig
				} else {
					fetchedNode[0].audioConfig?.codec2Enabled = config.codec2Enabled
					fetchedNode[0].audioConfig?.pttPin = Int32(config.pttPin)
					fetchedNode[0].audioConfig?.bitrate = Int32(config.bitrate.rawValue)
					fetchedNode[0].audioConfig?.i2sWs = Int32(config.i2SWs)
					fetchedNode[0].audioConfig?.i2sSd = Int32(config.i2SSd)
					fetchedNode[0].audioConfig?.i2sDin = Int32(config.i2SDin)
					fetchedNode[0].audioConfig?.i2sSck = Int32(config.i2SSck)
				}
				if sessionPasskey != nil {
					fetchedNode[0].sessionPasskey = sessionPasskey
					fetchedNode[0].sessionExpiration = Date().addingTimeInterval(300)
				}
				savePendingChanges()
					Logger.data.info("💾 [AudioConfigEntity] Updated for node: \(nodeNum.toHex(), privacy: .public)")
			} else {
				Logger.data.error("💥 [AudioConfigEntity] No Nodes found in local database matching node \(nodeNum.toHex(), privacy: .public) unable to save Audio Module Config")
			}
		} catch {
			let nsError = error as NSError
			Logger.data.error("💥 [AudioConfigEntity] Fetching node for core data failed: \(nsError, privacy: .public)")
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
				savePendingChanges()
					Logger.data.info("💾 [AmbientLightingConfigEntity] Updated for node: \(nodeNum.toHex(), privacy: .public)")
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
				savePendingChanges()
					Logger.data.info("💾 [CannedMessageConfigEntity] Updated for node: \(nodeNum.toHex(), privacy: .public)")
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
				savePendingChanges()
				Logger.data.info("💾 [DetectionSensorConfigEntity] Updated for node: \(nodeNum.toHex(), privacy: .public)")
				
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
				savePendingChanges()
					Logger.data.info("💾 [ExternalNotificationConfigEntity] Updated for node: \(nodeNum.toHex(), privacy: .public)")
			} else {
				Logger.data.error("💥 [ExternalNotificationConfigEntity] No Nodes found in local database matching node \(nodeNum.toHex(), privacy: .public) unable to save External Notification Module Config")
			}
		} catch {
			let nsError = error as NSError
			Logger.data.error("💥 [ExternalNotificationConfigEntity] Fetching node for core data failed: \(nsError, privacy: .public)")
		}
	}
	
	func upsertNeighborInfoModuleConfigPacket(config: ModuleConfig.NeighborInfoConfig, nodeNum: Int64, sessionPasskey: Data? = Data()) {

		let logString = String.localizedStringWithFormat("Neighbor Info config received: %@".localized, String(nodeNum))
		Logger.data.info("🏘️ \(logString, privacy: .public)")

		let fetchNum = Int64(nodeNum)
			var fetchNodeInfoRequest = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate<NodeInfoEntity> { $0.num == fetchNum })
			fetchNodeInfoRequest.fetchLimit = 1
		do {
			let fetchedNode = try modelContext.fetch(fetchNodeInfoRequest)
			if !fetchedNode.isEmpty {
				if fetchedNode[0].neighborInfoConfig == nil {
					let newConfig = NeighborInfoConfigEntity()
					modelContext.insert(newConfig)
					newConfig.enabled = config.enabled
					newConfig.updateInterval = Int32(config.updateInterval)
					newConfig.transmitOverLora = config.transmitOverLora
					fetchedNode[0].neighborInfoConfig = newConfig
				} else {
					fetchedNode[0].neighborInfoConfig?.enabled = config.enabled
					fetchedNode[0].neighborInfoConfig?.updateInterval = Int32(config.updateInterval)
					fetchedNode[0].neighborInfoConfig?.transmitOverLora = config.transmitOverLora
				}
				if sessionPasskey != nil {
					fetchedNode[0].sessionPasskey = sessionPasskey
					fetchedNode[0].sessionExpiration = Date().addingTimeInterval(300)
				}
				savePendingChanges()
					Logger.data.info("💾 [NeighborInfoConfigEntity] Updated for node number: \(nodeNum.toHex(), privacy: .public)")
			} else {
				Logger.data.error("💥 [NeighborInfoConfigEntity] No Nodes found in local database matching node number \(nodeNum.toHex(), privacy: .public) unable to save Neighbor Info Module Config")
			}
		} catch {
			let nsError = error as NSError
			Logger.data.error("💥 [NeighborInfoConfigEntity] Fetching node for core data failed: \(nsError, privacy: .public)")
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
					newPaxCounterConfig.wifiThreshold = config.wifiThreshold
					newPaxCounterConfig.bleThreshold = config.bleThreshold
					fetchedNode[0].paxCounterConfig = newPaxCounterConfig
				} else {
					fetchedNode[0].paxCounterConfig?.enabled = config.enabled
					fetchedNode[0].paxCounterConfig?.updateInterval = Int32(config.paxcounterUpdateInterval)
					fetchedNode[0].paxCounterConfig?.wifiThreshold = config.wifiThreshold
					fetchedNode[0].paxCounterConfig?.bleThreshold = config.bleThreshold
				}
				if sessionPasskey != nil {
					fetchedNode[0].sessionPasskey = sessionPasskey
					fetchedNode[0].sessionExpiration = Date().addingTimeInterval(300)
				}
				savePendingChanges()
					Logger.data.info("💾 [PaxCounterConfigEntity] Updated for node number: \(nodeNum.toHex(), privacy: .public)")
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
				savePendingChanges()
					Logger.data.info("💾 [RtttlConfigEntity] Updated for node: \(nodeNum.toHex(), privacy: .public)")
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
				savePendingChanges()
					Logger.data.info("💾 [MQTTConfigEntity] Updated for node number: \(nodeNum.toHex(), privacy: .public)")
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
				savePendingChanges()
					Logger.data.info("💾 [RangeTestConfigEntity] Updated for node: \(nodeNum.toHex(), privacy: .public)")
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
				savePendingChanges()
				Logger.data.info("💾 [SerialConfigEntity]Updated Serial Module Config for node: \(nodeNum.toHex(), privacy: .public)")
			} else {
				Logger.data.error("💥 [SerialConfigEntity] No Nodes found in local database matching node \(nodeNum.toHex(), privacy: .public) unable to save Serial Module Config")
			}
		} catch {
			
			let nsError = error as NSError
			Logger.data.error("💥 [SerialConfigEntity] Fetching node for core data failed: \(nsError, privacy: .public)")
		}
	}

	func upsertStatusMessageModuleConfigPacket(config: ModuleConfig.StatusMessageConfig, nodeNum: Int64, sessionPasskey: Data? = Data()) {

		let logString = String.localizedStringWithFormat("Status Message module config received: %@".localized, String(nodeNum))
		Logger.data.info("📬 \(logString, privacy: .public)")

		let fetchNum = Int64(nodeNum)
			var fetchNodeInfoRequest = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate<NodeInfoEntity> { $0.num == fetchNum })
			fetchNodeInfoRequest.fetchLimit = 1
		do {
			let fetchedNode = try modelContext.fetch(fetchNodeInfoRequest)
			if !fetchedNode.isEmpty {
				if fetchedNode[0].statusMessageConfig == nil {
					let newConfig = StatusMessageConfigEntity()
					modelContext.insert(newConfig)
					newConfig.nodeStatus = config.nodeStatus
					fetchedNode[0].statusMessageConfig = newConfig
				} else {
					fetchedNode[0].statusMessageConfig?.nodeStatus = config.nodeStatus
				}
				if sessionPasskey != nil {
					fetchedNode[0].sessionPasskey = sessionPasskey
					fetchedNode[0].sessionExpiration = Date().addingTimeInterval(300)
				}
				savePendingChanges()
					Logger.data.info("💾 [StatusMessageConfigEntity] Updated for node: \(nodeNum.toHex(), privacy: .public)")
			} else {
				Logger.data.error("💥 [StatusMessageConfigEntity] No Nodes found in local database matching node \(nodeNum.toHex(), privacy: .public) unable to save Status Message Module Config")
			}
		} catch {
			let nsError = error as NSError
			Logger.data.error("💥 [StatusMessageConfigEntity] Fetching node for core data failed: \(nsError, privacy: .public)")
		}
	}

	/// Stores the live status message a node broadcasts over NODE_STATUS_APP. This is the
	/// node's currently advertised status (shown in the node list), separate from the
	/// configured value retrieved via admin (`statusMessageConfig`). Mirrors Android's
	/// `handleReceivedNodeStatus`: an empty status clears the stored value.
	func upsertNodeStatusPacket(packet: MeshPacket) {
		let fetchNum = Int64(packet.from)
		guard let statusMessage = try? StatusMessage(serializedBytes: packet.decoded.payload) else {
			Logger.data.error("💥 [NodeStatus] Failed to decode StatusMessage from \(fetchNum.toHex(), privacy: .public)")
			return
		}

		let logString = String.localizedStringWithFormat("Node status received: %@".localized, String(fetchNum))
		Logger.data.info("📬 \(logString, privacy: .public)")

		var fetchNodeInfoRequest = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate<NodeInfoEntity> { $0.num == fetchNum })
		fetchNodeInfoRequest.fetchLimit = 1
		do {
			let fetchedNode = try modelContext.fetch(fetchNodeInfoRequest)
			guard !fetchedNode.isEmpty else {
				Logger.data.error("💥 [NodeStatus] No node found matching \(fetchNum.toHex(), privacy: .public) unable to save node status")
				return
			}
			fetchedNode[0].nodeStatus = statusMessage.status.isEmpty ? nil : statusMessage.status
			savePendingChanges()
			Logger.data.info("💾 [NodeStatus] Updated for node: \(fetchNum.toHex(), privacy: .public)")
		} catch {
			let nsError = error as NSError
			Logger.data.error("💥 [NodeStatus] Fetching node for core data failed: \(nsError, privacy: .public)")
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
				savePendingChanges()
					Logger.data.info("💾 [StoreForwardConfigEntity] Updated for node: \(nodeNum.toHex(), privacy: .public)")
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
					newTelemetryConfig.airQualityEnabled = config.airQualityEnabled
					newTelemetryConfig.airQualityInterval = Int32(truncatingIfNeeded: config.airQualityInterval)
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
					fetchedNode[0].telemetryConfig?.airQualityEnabled = config.airQualityEnabled
					fetchedNode[0].telemetryConfig?.airQualityInterval = Int32(truncatingIfNeeded: config.airQualityInterval)
					fetchedNode[0].telemetryConfig?.powerMeasurementEnabled = config.powerMeasurementEnabled
					fetchedNode[0].telemetryConfig?.powerUpdateInterval = Int32(truncatingIfNeeded: config.powerUpdateInterval)
					fetchedNode[0].telemetryConfig?.powerScreenEnabled = config.powerScreenEnabled
				}
				if sessionPasskey != nil {
					fetchedNode[0].sessionPasskey = sessionPasskey
					fetchedNode[0].sessionExpiration = Date().addingTimeInterval(300)
				}
				savePendingChanges()
				Logger.data.info("💾 [TelemetryConfigEntity] Updated Telemetry Module Config for node: \(nodeNum.toHex(), privacy: .public)")
				
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
				savePendingChanges()
					Logger.data.info("💾 [TAKConfigEntity] Updated TAK Module Config for node: \(nodeNum.toHex(), privacy: .public)")
			} else {
				Logger.data.error("💥 [TAKConfigEntity] No Nodes found in local database matching node \(nodeNum.toHex(), privacy: .public) unable to save TAK Module Config")
			}
		} catch {
			let nsError = error as NSError
			Logger.data.error("💥 [TAKConfigEntity] Fetching node for core data failed: \(nsError, privacy: .public)")
		}
	}

	func upsertTrafficManagementModuleConfigPacket(config: ModuleConfig.TrafficManagementConfig, nodeNum: Int64, sessionPasskey: Data? = Data()) {

		let logString = String.localizedStringWithFormat("Traffic Management module config received: %@".localized, String(nodeNum))
		Logger.data.info("🚦 \(logString, privacy: .public)")

		let fetchNum = Int64(nodeNum)
		var fetchNodeInfoRequest = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate<NodeInfoEntity> { $0.num == fetchNum })
		fetchNodeInfoRequest.fetchLimit = 1
		do {
			let fetchedNode = try modelContext.fetch(fetchNodeInfoRequest)
			if !fetchedNode.isEmpty {
				if fetchedNode[0].trafficManagementConfig == nil {
					let newConfig = TrafficManagementConfigEntity()
					modelContext.insert(newConfig)
					newConfig.enabled = config.enabled
					newConfig.positionDedupEnabled = config.positionDedupEnabled
					newConfig.positionPrecisionBits = Int32(config.positionPrecisionBits)
					newConfig.positionMinIntervalSecs = Int32(config.positionMinIntervalSecs)
					newConfig.nodeinfoDirectResponse = config.nodeinfoDirectResponse
					newConfig.nodeinfoDirectResponseMaxHops = Int32(config.nodeinfoDirectResponseMaxHops)
					newConfig.rateLimitEnabled = config.rateLimitEnabled
					newConfig.rateLimitWindowSecs = Int32(config.rateLimitWindowSecs)
					newConfig.rateLimitMaxPackets = Int32(config.rateLimitMaxPackets)
					newConfig.dropUnknownEnabled = config.dropUnknownEnabled
					newConfig.unknownPacketThreshold = Int32(config.unknownPacketThreshold)
					newConfig.exhaustHopTelemetry = config.exhaustHopTelemetry
					newConfig.exhaustHopPosition = config.exhaustHopPosition
					newConfig.routerPreserveHops = config.routerPreserveHops
					fetchedNode[0].trafficManagementConfig = newConfig
				} else {
					fetchedNode[0].trafficManagementConfig?.enabled = config.enabled
					fetchedNode[0].trafficManagementConfig?.positionDedupEnabled = config.positionDedupEnabled
					fetchedNode[0].trafficManagementConfig?.positionPrecisionBits = Int32(config.positionPrecisionBits)
					fetchedNode[0].trafficManagementConfig?.positionMinIntervalSecs = Int32(config.positionMinIntervalSecs)
					fetchedNode[0].trafficManagementConfig?.nodeinfoDirectResponse = config.nodeinfoDirectResponse
					fetchedNode[0].trafficManagementConfig?.nodeinfoDirectResponseMaxHops = Int32(config.nodeinfoDirectResponseMaxHops)
					fetchedNode[0].trafficManagementConfig?.rateLimitEnabled = config.rateLimitEnabled
					fetchedNode[0].trafficManagementConfig?.rateLimitWindowSecs = Int32(config.rateLimitWindowSecs)
					fetchedNode[0].trafficManagementConfig?.rateLimitMaxPackets = Int32(config.rateLimitMaxPackets)
					fetchedNode[0].trafficManagementConfig?.dropUnknownEnabled = config.dropUnknownEnabled
					fetchedNode[0].trafficManagementConfig?.unknownPacketThreshold = Int32(config.unknownPacketThreshold)
					fetchedNode[0].trafficManagementConfig?.exhaustHopTelemetry = config.exhaustHopTelemetry
					fetchedNode[0].trafficManagementConfig?.exhaustHopPosition = config.exhaustHopPosition
					fetchedNode[0].trafficManagementConfig?.routerPreserveHops = config.routerPreserveHops
				}
				if sessionPasskey != nil {
					fetchedNode[0].sessionPasskey = sessionPasskey
					fetchedNode[0].sessionExpiration = Date().addingTimeInterval(300)
				}
				savePendingChanges()
				Logger.data.info("💾 [TrafficManagementConfigEntity] Updated for node: \(nodeNum.toHex(), privacy: .public)")
			} else {
				Logger.data.error("💥 [TrafficManagementConfigEntity] No Nodes found in local database matching node \(nodeNum.toHex(), privacy: .public) unable to save Traffic Management Module Config")
			}
		} catch {
			let nsError = error as NSError
			Logger.data.error("💥 [TrafficManagementConfigEntity] Fetching node for core data failed: \(nsError, privacy: .public)")
		}
	}
}
