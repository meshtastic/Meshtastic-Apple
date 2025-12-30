//
//  AccessoryManager+ToRadio.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/18/25.
//

import Foundation
import MeshtasticProtobufs
import OSLog

extension AccessoryManager {

	public func getCannedMessageModuleMessages(destNum: Int64, wantResponse: Bool) throws {
		guard let deviceNum = self.activeConnection?.device.num else {
			Logger.services.error("Error while sending CannedMessageModule request.  No active device.")
			throw AccessoryError.ioFailed("No active device")
		}

		var adminPacket = AdminMessage()
		adminPacket.getCannedMessageModuleMessagesRequest = true

		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(destNum)
		meshPacket.from	= UInt32(deviceNum)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		meshPacket.decoded.wantResponse = wantResponse

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("Error serializing admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = wantResponse

		meshPacket.decoded = dataMessage

		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket

		let logString = String.localizedStringWithFormat("Requested Canned Messages Module Messages for node: %@".localized, String(deviceNum))
		Task {
			try await send(toRadio, debugDescription: logString)
		}
	}
	
	public func getRingtone(destNum: Int64, wantResponse: Bool) throws {
		guard let deviceNum = self.activeConnection?.device.num else {
			Logger.services.error("Error while sending RtttlConfig request.  No active device.")
			throw AccessoryError.ioFailed("No active device")
		}

		var adminPacket = AdminMessage()
		adminPacket.getRingtoneRequest = true

		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(destNum)
		meshPacket.from	= UInt32(deviceNum)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		meshPacket.decoded.wantResponse = wantResponse

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("Error serializing admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = wantResponse

		meshPacket.decoded = dataMessage

		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket

		let logString = String.localizedStringWithFormat("Requested RTTTL Config Module ringtone for node: %@".localized, String(deviceNum))
		Task {
			try await send(toRadio, debugDescription: logString)
		}
	}

	public func saveTimeZone(config: Config.DeviceConfig, user: Int64) async throws -> Int64 {
		var adminPacket = AdminMessage()
		adminPacket.setConfig.device = config
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(user)
		meshPacket.from	= UInt32(user)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("saveTimeZone: Unable to serialize Admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage

		let messageDescription = "⌚ Device Config timezone was empty set timezone to \(config.tzdef)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
		return Int64(meshPacket.id)
	}

	// Send an admin message to a radio, save a message to core data for logging
	private func sendAdminMessageToRadio(meshPacket: MeshPacket, adminDescription: String?) async throws {

		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket

		try await send(toRadio)
		if let adminDescription {
			Logger.mesh.debug("\(adminDescription, privacy: .public)")
		}
	}

	public func addContactFromURL(base64UrlString: String) async throws {
		guard let deviceNum = self.activeConnection?.device.num else {
			Logger.services.error("Error while sending CannedMessageModule request.  No active device.")
			throw AccessoryError.ioFailed("No active device")
		}

		let decodedString = base64UrlString.base64urlToBase64()
		if let decodedData = Data(base64Encoded: decodedString) {
			do {
				let contact: SharedContact = try SharedContact(serializedBytes: decodedData)
				var adminPacket = AdminMessage()
				adminPacket.addContact = contact
				var meshPacket: MeshPacket = MeshPacket()
				meshPacket.to = UInt32(deviceNum)
				meshPacket.from	= UInt32(deviceNum)
				meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
				meshPacket.priority =  MeshPacket.Priority.reliable
				meshPacket.wantAck = true
				meshPacket.channel = 0
				var dataMessage = DataMessage()
				guard let adminData: Data = try? adminPacket.serializedData() else {
					throw AccessoryError.ioFailed("addContactFromURL: Unable to serialize admin packet")
				}
				dataMessage.payload = adminData
				dataMessage.portnum = PortNum.adminApp
				meshPacket.decoded = dataMessage
				var toRadio: ToRadio!
				toRadio = ToRadio()
				toRadio.packet = meshPacket

				let logString = String.localizedStringWithFormat("Added contact %@ to device".localized, contact.user.longName)
				try await send(toRadio, debugDescription: logString)

				// Create a NodeInfo (User) packet for the newly added contact
				var dataNodeMessage = DataMessage()
				if let nodeInfoData = try? contact.user.serializedData() {
					dataNodeMessage.payload = nodeInfoData
					dataNodeMessage.portnum = PortNum.nodeinfoApp
					var nodeMeshPacket = MeshPacket()
					nodeMeshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
					nodeMeshPacket.to = UInt32.max
					nodeMeshPacket.from = UInt32(contact.nodeNum)
					nodeMeshPacket.decoded = dataNodeMessage

					// Update local database with the new node info
					// FUTURE: after https://github.com/meshtastic/firmware/pull/8495 is merged, `favorite: true` becomes `favorite: (connectedDeviceRole != DeviceRoles.clientBase)`
					upsertNodeInfoPacket(packet: nodeMeshPacket, favorite: true, context: context)
				}
			} catch {
				Logger.data.error("Failed to decode contact data: \(error.localizedDescription, privacy: .public)")
				throw AccessoryError.appError("Unable to decode contact data from QR code.")
			}
		}
	}
	
	// toConnection parameter can be used during connection process before the AccessoryManager is fully setup
	public func sendHeartbeat(toConnection: Connection? = nil) async throws {
		var heartbeatToRadio: ToRadio = ToRadio()
		var heartbeatPacket = Heartbeat()
		
		// Note: at the time of writing, there was some indication that the firmware might
		// respond to a nonce == 1 differently than other nonces.  So making this a random
		// from 2..UInt32 max.  If additional special cases are added, can increase the
		// lower bound
		heartbeatPacket.nonce = UInt32.random(in: 2...UInt32.max)
		heartbeatToRadio.payloadVariant = .heartbeat(heartbeatPacket)
		if let toConnection {
			try await toConnection.send(heartbeatToRadio)
		} else {
			try await self.send(heartbeatToRadio)
		}
		await self.heartbeatResponseTimer?.reset(delay: .seconds(5.0))
	}
	
	public func sendTime() async throws {
		guard let deviceNum = self.activeDeviceNum.map({ UInt32($0) }) else {
			Logger.mesh.error("🚫 Unable to send time, connected node is disconnected or invalid")
			return
		}
		var adminPacket = AdminMessage()
		adminPacket.setTimeOnly = UInt32(Date().timeIntervalSince1970)
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = deviceNum
		meshPacket.from = deviceNum
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		meshPacket.channel = 0
		var dataMessage = DataMessage()
		if let serializedData: Data = try? adminPacket.serializedData() {
			dataMessage.payload = serializedData
			dataMessage.portnum = PortNum.adminApp
			meshPacket.decoded = dataMessage
		} else {
			throw AccessoryError.ioFailed("sendTime: Unable to serialize admin packet")
		}
		let messageDescription = "🕛 Sent Set Time Admin Message to the connected node."
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
	}
	
	public func sendShutdown(fromUser: UserEntity, toUser: UserEntity) async throws {
		var adminPacket = AdminMessage()
		adminPacket.shutdownSeconds = 5
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		if let serializedData: Data = try? adminPacket.serializedData() {
			dataMessage.payload = serializedData
			dataMessage.portnum = PortNum.adminApp
			meshPacket.decoded = dataMessage
		} else {
			throw AccessoryError.ioFailed("sendShutdown: Unable to serialize admin packet")
		}
		let messageDescription = "🚀 Sent Shutdown Admin Message to: \(toUser.longName ?? "Unknown".localized) from: \(fromUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
	}

	public func sendReboot(fromUser: UserEntity, toUser: UserEntity) async throws {
		var adminPacket = AdminMessage()
		adminPacket.rebootSeconds = 5
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		if let serializedData: Data = try? adminPacket.serializedData() {
			dataMessage.payload = serializedData
			dataMessage.portnum = PortNum.adminApp
			meshPacket.decoded = dataMessage
		} else {
			throw AccessoryError.ioFailed("sendReboot: Unable to serialize Admin packet")
		}
		let messageDescription = "🚀 Sent Reboot Admin Message to: \(toUser.longName ?? "Unknown".localized) from: \(fromUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
	}

	public func sendMessage(message: String, toUserNum: Int64, channel: Int32, isEmoji: Bool, replyID: Int64) async throws {
		guard let fromUserNum = self.activeConnection?.device.num else {
			Logger.services.error("Error while sending CannedMessageModule request.  No active device.")
			throw AccessoryError.ioFailed("No active device")
		}

		guard message.count > 0 else {
			// Don't send an empty message
			Logger.mesh.info("🚫 Don't Send an Empty Message")
			return
		}

			let messageUsers = UserEntity.fetchRequest()
			messageUsers.predicate = NSPredicate(format: "num IN %@", [fromUserNum, Int64(toUserNum)])

			do {
				let fetchedUsers = try context.fetch(messageUsers)
				if fetchedUsers.isEmpty {

					Logger.data.error("🚫 Message Users Not Found, Fail")
					throw AccessoryError.ioFailed("🚫 Message Users Not Found, Fail")
				} else if fetchedUsers.count >= 1 {
					let newMessage = MessageEntity(context: context)
					newMessage.messageId = Int64(UInt32.random(in: UInt32(UInt8.max)..<UInt32.max))
					newMessage.messageTimestamp =  Int32(Date().timeIntervalSince1970)
					newMessage.receivedACK = false
					newMessage.read = true
					if toUserNum > 0 {
						newMessage.toUser = fetchedUsers.first(where: { $0.num == toUserNum })
						newMessage.toUser?.lastMessage = Date()
						if newMessage.toUser?.pkiEncrypted ?? false {
							newMessage.publicKey = newMessage.toUser?.publicKey
							newMessage.pkiEncrypted = true
						}
					}
					newMessage.fromUser = fetchedUsers.first(where: { $0.num == fromUserNum })
					newMessage.isEmoji = isEmoji
					newMessage.admin = false
					newMessage.channel = channel
					if replyID > 0 {
						newMessage.replyID = replyID
					}
					newMessage.messagePayload = message
					newMessage.messagePayloadMarkdown = generateMessageMarkdown(message: message)
					newMessage.read = true

					let dataType = PortNum.textMessageApp
					var messageQuotesReplaced = message.replacingOccurrences(of: "’", with: "'")
					messageQuotesReplaced = message.replacingOccurrences(of: "”", with: "\"")
					let payloadData: Data = messageQuotesReplaced.data(using: String.Encoding.utf8)!

					var dataMessage = DataMessage()
					dataMessage.payload = payloadData
					dataMessage.portnum = dataType

					var meshPacket = MeshPacket()
					if newMessage.toUser?.pkiEncrypted ?? false {
						meshPacket.pkiEncrypted = true
						meshPacket.publicKey = newMessage.toUser?.publicKey ?? Data()
						// Send a contact to the phone every time we send a dm so that any nodes that have rolled out of the db are there and we don't get a PKI Failed error
						Task { @MainActor in
							let am = AccessoryManager.shared
							if let user = newMessage.toUser {
								var contact = SharedContact()
								contact.manuallyVerified = false
								contact.nodeNum = UInt32(truncatingIfNeeded: user.num)
								user.userNode?.favorite = user.userNode?.deviceConfig?.role ?? 0 != DeviceRoles.clientBase.rawValue
								contact.user = user.toProto()
								do {
									let contactString = try contact.serializedData().base64EncodedString()
									try? await am.addContactFromURL(base64UrlString: contactString)
									try context.save()
									user.objectWillChange.send()
								} catch {
									Logger.services.error("Error inserting new contact and resending encrypted send failed message: \(error)")
								}
							}
						}
					}
					meshPacket.id = UInt32(newMessage.messageId)
					if toUserNum > 0 {
						meshPacket.to = UInt32(toUserNum)
						let hopsAway = newMessage.toUser?.userNode?.hopsAway ?? 0
						if hopsAway > Int32(truncatingIfNeeded: newMessage.fromUser?.userNode?.loRaConfig?.hopLimit ?? 0) {
							meshPacket.hopLimit = UInt32(truncatingIfNeeded: hopsAway)
						}
					} else {
						meshPacket.to = Constants.maximumNodeNum
					}
					meshPacket.channel = UInt32(channel)
					meshPacket.from	= UInt32(fromUserNum)
					meshPacket.decoded = dataMessage
					meshPacket.decoded.emoji = isEmoji ? 1 : 0
					if replyID > 0 {
						meshPacket.decoded.replyID = UInt32(replyID)
					}
					meshPacket.wantAck = true

					var toRadio: ToRadio!
					toRadio = ToRadio()
					toRadio.packet = meshPacket
					Task {
						let logString = String.localizedStringWithFormat("Sent message %@ from %@ to %@".localized, String(newMessage.messageId), fromUserNum.toHex(), toUserNum.toHex())
						try await send(toRadio, debugDescription: logString)
					}
					do {
						try context.save()
						Logger.data.info("💾 Saved a new sent message from \(self.activeDeviceNum?.toHex() ?? "0", privacy: .public) to \(toUserNum.toHex(), privacy: .public)")

					} catch {
						context.rollback()
						let nsError = error as NSError
						Logger.data.error("Unresolved Core Data error in Send Message Function your database is corrupted running a node db reset should clean up the data. Error: \(nsError, privacy: .public)")
						throw error
					}
				}
			} catch {
				Logger.data.error("💥 Send message failure \(self.activeDeviceNum?.toHex() ?? "0", privacy: .public) to \(toUserNum.toHex(), privacy: .public)")
			}

	}

	public func setFavoriteNode(node: NodeInfoEntity, connectedNodeNum: Int64) async throws {
		var adminPacket = AdminMessage()
		adminPacket.setFavoriteNode = UInt32(node.num)
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(connectedNodeNum)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("setFavoriteNode: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket

		let logString = String.localizedStringWithFormat("Set node %@ as favorite on %@".localized, node.num.toHex(), connectedNodeNum.toHex())
		try await send(toRadio, debugDescription: logString)
	}

	public func removeFavoriteNode(node: NodeInfoEntity, connectedNodeNum: Int64) async throws {
		var adminPacket = AdminMessage()
		adminPacket.removeFavoriteNode = UInt32(node.num)
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(connectedNodeNum)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("removeFavoriteNode: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket

		let logString = String.localizedStringWithFormat("Remove node %@ as favorite on %@".localized, node.num.toHex(), connectedNodeNum.toHex())
		try await send(toRadio, debugDescription: logString)
	}

	public func saveChannelSet(base64UrlString: String, addChannels: Bool = false, okToMQTT: Bool = false) async throws {
		guard let deviceNum = self.activeConnection?.device.num else {
			Logger.services.error("Error while sending saveChannelSet request.  No active device.")
			throw AccessoryError.ioFailed("No active device")
		}
		// Before we get started delete the existing channels from the myNodeInfo
		if !addChannels {
			tryClearExistingChannels()
		}

		let decodedString = base64UrlString.base64urlToBase64()
		if let decodedData = Data(base64Encoded: decodedString) {
			let channelSet: ChannelSet = try ChannelSet(serializedBytes: decodedData)

			var myInfo: MyInfoEntity!
			var i: Int32 = 0

			if addChannels {
				let fetchMyInfoRequest = MyInfoEntity.fetchRequest()
				fetchMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", Int64(deviceNum))

				let fetchedMyInfo = try context.fetch(fetchMyInfoRequest)
				if fetchedMyInfo.count != 1 {
					throw AccessoryError.appError("MyInfo not found")
				}
				
				// We are trying to add a channel so lets get the last index
				myInfo = fetchedMyInfo[0]
				i = Int32(myInfo.channels?.count ?? -1)
				
				// Bail out if the index is negative or bigger than our max of 8
				if i < 0 || i > 8 {
					throw AccessoryError.appError("Index out of range \(i)")
				}
			}

			for cs in channelSet.settings {

				if addChannels {
					guard let mutableChannels = myInfo.channels?.mutableCopy() as? NSMutableOrderedSet else {
						throw AccessoryError.appError("No channels or channel")
					}
					
					// Bail out if there are no channels or if the same channel name already exists
					if mutableChannels.first(where: { ($0 as AnyObject).name == cs.name }) is ChannelEntity {
						throw AccessoryError.appError("Channel already exists")
					}
				}

				var chan = Channel()
				chan.role = (i == 0) ? .primary : .secondary
				chan.settings = cs
				chan.index = i
				i += 1

				var adminPacket = AdminMessage()
				adminPacket.setChannel = chan

				var meshPacket = MeshPacket()
				meshPacket.to = UInt32(deviceNum)
				meshPacket.from = UInt32(deviceNum)
				meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
				meshPacket.priority = MeshPacket.Priority.reliable
				meshPacket.wantAck = true
				meshPacket.channel = 0

				guard let adminData = try? adminPacket.serializedData() else {
					throw AccessoryError.ioFailed("saveChannelSet: Unable to serialize Admin packet")
				}

				var dataMessage = DataMessage()
				dataMessage.payload = adminData
				dataMessage.portnum = PortNum.adminApp
				meshPacket.decoded = dataMessage

				var toRadio = ToRadio()
				toRadio.packet = meshPacket

				let logString = String.localizedStringWithFormat("Sent a Channel for: %@ Channel Index %d".localized, String(deviceNum), chan.index)
				try await send(toRadio, debugDescription: logString)
				channelPacket(channel: chan, fromNum: self.activeDeviceNum ?? 0, context: context)
			}
			if !addChannels {
				// Save the LoRa Config and the device will reboot
				var adminPacket = AdminMessage()
				adminPacket.setConfig.lora = channelSet.loraConfig
				adminPacket.setConfig.lora.configOkToMqtt = okToMQTT // Preserve users okToMQTT choice
				var meshPacket: MeshPacket = MeshPacket()
				meshPacket.to = UInt32(deviceNum)
				meshPacket.from	= UInt32(deviceNum)
				meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
				meshPacket.priority =  MeshPacket.Priority.reliable
				meshPacket.wantAck = true
				meshPacket.channel = 0
				var dataMessage = DataMessage()
				guard let adminData: Data = try? adminPacket.serializedData() else {
					throw AccessoryError.ioFailed("sendReboot: Unable to serialize Admin packet")
				}
				dataMessage.payload = adminData
				dataMessage.portnum = PortNum.adminApp
				meshPacket.decoded = dataMessage
				var toRadio: ToRadio!
				toRadio = ToRadio()
				toRadio.packet = meshPacket
				
				let logString = String.localizedStringWithFormat("Sent a LoRa.Config for: %@".localized, String(deviceNum))
				try await send(toRadio, debugDescription: logString)
			}
			Logger.transport.debug("[AccessoryManager] sending wantConfig for saveChannelSet")
			try await sendWantConfig()
		}
	}

	public func saveChannel(channel: Channel, fromUser: UserEntity, toUser: UserEntity) async throws -> Int64 {
		var adminPacket = AdminMessage()
		adminPacket.setChannel = channel
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("saveChannel: Unable to serialize Admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		meshPacket.decoded = dataMessage

		let messageDescription = "🛟 Saved Channel \(channel.index) for \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
		return Int64(meshPacket.id)
	}

	public func sendWaypoint(waypoint: Waypoint) async throws {
		guard let deviceNum = self.activeConnection?.device.num else {
			Logger.services.error("Error while sending sendWaypoint request.  No active device.")
			throw AccessoryError.ioFailed("No active device")
		}

		if waypoint.latitudeI == 0 && waypoint.longitudeI == 0 {
			throw AccessoryError.appError("sendWaypoint: Waypoint coordinates are invalid")
		}

		let fromNodeNum = UInt32(deviceNum)
		var meshPacket = MeshPacket()
		meshPacket.to = Constants.maximumNodeNum
		meshPacket.from	= fromNodeNum
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		do {
			dataMessage.payload = try waypoint.serializedData()
		} catch {
			throw AccessoryError.ioFailed("sendWaypoint: Unable to serialize data packet")
		}

		dataMessage.portnum = PortNum.waypointApp
		meshPacket.decoded = dataMessage
		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket

		let logString = String.localizedStringWithFormat("Sent a Waypoint Packet from: %@".localized, String(fromNodeNum))
		try await send(toRadio, debugDescription: logString)
		Logger.mesh.info("📍 \(logString, privacy: .public)")

			let wayPointEntity = getWaypoint(id: Int64(waypoint.id), context: context)
			wayPointEntity.id = Int64(waypoint.id)
			wayPointEntity.name = waypoint.name.count >= 1 ? waypoint.name : "Dropped Pin"
			wayPointEntity.longDescription = waypoint.description_p
			wayPointEntity.icon	= Int64(waypoint.icon)
			wayPointEntity.latitudeI = waypoint.latitudeI
			wayPointEntity.longitudeI = waypoint.longitudeI
			if waypoint.expire > 1 {
				wayPointEntity.expire = Date.init(timeIntervalSince1970: Double(waypoint.expire))
			} else {
				wayPointEntity.expire = nil
			}
			if waypoint.lockedTo > 0 {
				wayPointEntity.locked = Int64(waypoint.lockedTo)
			} else {
				wayPointEntity.locked = 0
			}
			if wayPointEntity.created == nil {
				wayPointEntity.created = Date()
			} else {
				wayPointEntity.lastUpdated = Date()
			}
			do {
				try context.save()
				Logger.data.info("💾 Updated Waypoint from Waypoint App Packet From: \(fromNodeNum.toHex(), privacy: .public)")
			} catch {
				context.rollback()
				let nsError = error as NSError
				Logger.data.error("Error Saving NodeInfoEntity from WAYPOINT_APP \(nsError, privacy: .public)")
			}

	}

	func sendTraceRouteRequest(destNum: Int64, wantResponse: Bool) async throws {
		guard let fromNodeNum = self.activeConnection?.device.num else {
			Logger.services.error("Error while sending traceroute request.  No active device.")
			throw AccessoryError.ioFailed("No active device")
		}

		let routePacket = RouteDiscovery()
		var meshPacket = MeshPacket()
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.to = UInt32(destNum)
		meshPacket.from	= UInt32(fromNodeNum)
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		if let serializedData: Data = try? routePacket.serializedData() {
			dataMessage.payload = serializedData
			dataMessage.portnum = PortNum.tracerouteApp
			dataMessage.wantResponse = true
			meshPacket.decoded = dataMessage
		} else {
			throw AccessoryError.ioFailed("sendTraceRouteRequest: Unable to serialize data packet")
		}
		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket

		let logString = String.localizedStringWithFormat("Sent a TraceRoute Packet from: %@ to: %@".localized, String(fromNodeNum), String(destNum))
		try await send(toRadio, debugDescription: logString)

			let traceRoute = TraceRouteEntity(context: context)
			let nodes = NodeInfoEntity.fetchRequest()
			// TODO: Not sure what's going on here. We always have a fromNodeNum
			// if let connectedNum = fromNodeNum {
			nodes.predicate = NSPredicate(format: "num IN %@", [destNum, fromNodeNum])
			// } else {
			//	nodes.predicate = NSPredicate(format: "num == %@", destNum)
			// }
			do {
				let fetchedNodes = try context.fetch(nodes)
				let receivingNode = fetchedNodes.first(where: { $0.num == destNum })
				traceRoute.id = Int64(meshPacket.id)
				traceRoute.time = Date()
				traceRoute.node = receivingNode
				do {
					try context.save()
					Logger.data.info("💾 Saved TraceRoute sent to node: \(String(receivingNode?.user?.longName ?? "Unknown".localized), privacy: .public)")
				} catch {
					context.rollback()
					let nsError = error as NSError
					Logger.data.error("Error Updating Core Data BluetoothConfigEntity: \(nsError, privacy: .public)")
				}

				let logString = String.localizedStringWithFormat("Sent a Trace Route Request to node: %@".localized, destNum.toHex())
				Logger.mesh.info("🪧 \(logString, privacy: .public)")

			} catch {

			}

	}

	public func requestStoreAndForwardClientHistory(fromUser: UserEntity, toUser: UserEntity) async throws {

		/// send a request for ClientHistory with a time period matching the heartbeat
		var sfPacket = StoreAndForward()
		sfPacket.rr = StoreAndForward.RequestResponse.clientHistory
		sfPacket.history.window = UInt32(toUser.userNode?.storeForwardConfig?.historyReturnWindow ?? 120)
		sfPacket.history.lastRequest = UInt32(toUser.userNode?.storeForwardConfig?.lastRequest ?? 0)
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let sfData: Data = try? sfPacket.serializedData() else {
			throw AccessoryError.ioFailed("requestStoreAndForwardClientHistory: Unable to serialize data packet")

		}
		dataMessage.payload = sfData
		dataMessage.portnum = PortNum.storeForwardApp
		dataMessage.wantResponse = true
		meshPacket.decoded = dataMessage

		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket
		let logString = String.localizedStringWithFormat("📮 Sent a request for a Store & Forward Client History to \(toUser.num.toHex()) for the last \(120) minutes.")
		try await send(toRadio, debugDescription: logString)
	}

	public func setIgnoredNode(node: NodeInfoEntity, connectedNodeNum: Int64) async throws {
		var adminPacket = AdminMessage()
		adminPacket.setIgnoredNode = UInt32(node.num)
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(connectedNodeNum)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("setIgnoredNode: Unable to serialize data packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket

		let logString = String.localizedStringWithFormat("📮 Sent a request to  ignore \(node.num.toHex())")
		try await send(toRadio, debugDescription: logString)
	}

	public func removeIgnoredNode(node: NodeInfoEntity, connectedNodeNum: Int64) async throws {
		var adminPacket = AdminMessage()
		adminPacket.removeIgnoredNode = UInt32(node.num)
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(connectedNodeNum)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("removeIgnoredNode: Unable to serialize data packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket

		let logString = String.localizedStringWithFormat("📮 Sent a request to un-ignore \(node.num.toHex())")
		try await send(toRadio, debugDescription: logString)
	}

	public func removeNode(node: NodeInfoEntity, connectedNodeNum: Int64) async throws {
		var adminPacket = AdminMessage()
		adminPacket.removeByNodenum = UInt32(node.num)
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(connectedNodeNum)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		if let serializedData: Data = try? adminPacket.serializedData() {
			dataMessage.payload = serializedData
			dataMessage.portnum = PortNum.adminApp
			meshPacket.decoded = dataMessage
		} else {
			throw AccessoryError.ioFailed("removeNode: Unable to serialize data packet")
		}
		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket

		let logString = String.localizedStringWithFormat("🗑️ Sent a request to remove node \(node.num.toHex())")
		try await send(toRadio, debugDescription: logString)

			do {
				context.delete(node.user!)
				context.delete(node)
				try context.save()
			} catch {
				context.rollback()
				let nsError = error as NSError
				Logger.data.error("🚫 Error deleting node from core data: \(nsError, privacy: .public)")
			}

	}

	func requestDeviceMetadata(fromUser: UserEntity? = nil, toUser: UserEntity? = nil) async throws -> Int64 {

		guard isConnected else {
			throw AccessoryError.ioFailed("No connected accessory")
		}
		
		let fromUserNum = fromUser.map { UInt32($0.num) } ?? UInt32(activeDeviceNum ?? 0)
		let toUserNum = toUser.map { UInt32($0.num) } ?? UInt32(activeDeviceNum ?? 0)

		var adminPacket = AdminMessage()
		adminPacket.getDeviceMetadataRequest = true
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.to = toUserNum
		meshPacket.from	= fromUserNum
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		if let serializedData: Data = try? adminPacket.serializedData() {
			dataMessage.payload = serializedData
			dataMessage.portnum = PortNum.adminApp
			dataMessage.wantResponse = true
			meshPacket.decoded = dataMessage
		} else {
			throw AccessoryError.ioFailed("removeNode: Unable to serialize admin packet")
		}

		let messageDescription = "🛎️ [Device Metadata] Requested for node \(toUser?.longName ?? "#\(toUserNum)") by \(fromUser?.longName ?? "#\(fromUser)")"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
		return Int64(meshPacket.id)
	}

	public func saveAmbientLightingModuleConfig(config: ModuleConfig.AmbientLightingConfig, fromUser: UserEntity, toUser: UserEntity) async throws -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.ambientLighting = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("saveAmbientLightingModuleConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage

		let messageDescription = "🛟 Saved Ambient Lighting Module Config for \(toUser.longName ?? "Unknown".localized)"

		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)

			upsertAmbientLightingModuleConfigPacket(config: config, nodeNum: toUser.num, context: context)

		return Int64(meshPacket.id)

	}

	public func requestAmbientLightingConfig(fromUser: UserEntity, toUser: UserEntity) async throws {

		var adminPacket = AdminMessage()
		adminPacket.getModuleConfigRequest = AdminMessage.ModuleConfigType.ambientlightingConfig
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("requestAmbientLightingConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true

		meshPacket.decoded = dataMessage

		let messageDescription = "🛎️ Requested Ambient Lighting Config using an admin key for node: \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
	}

	public func saveCannedMessageModuleConfig(config: ModuleConfig.CannedMessageConfig, fromUser: UserEntity, toUser: UserEntity) async throws -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.cannedMessage = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("saveCannedMessageModuleConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage

		let messageDescription = "🛟 Saved Canned Message Module Config for \(toUser.longName ?? "Unknown".localized)"

		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)

			upsertCannedMessagesModuleConfigPacket(config: config, nodeNum: toUser.num, context: context)

		return Int64(meshPacket.id)
	}

	public func saveCannedMessageModuleMessages(messages: String, fromUser: UserEntity, toUser: UserEntity) async throws -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setCannedMessageModuleMessages = messages
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("saveCannedMessageModuleMessages: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		meshPacket.decoded = dataMessage

		let messageDescription = "🛟 Saved Canned Message Module Messages for \(toUser.longName ?? "Unknown".localized)"

		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
		return Int64(meshPacket.id)
	}

	public func requestCannedMessagesModuleConfig(fromUser: UserEntity, toUser: UserEntity) async throws {

		var adminPacket = AdminMessage()
		adminPacket.getModuleConfigRequest = AdminMessage.ModuleConfigType.cannedmsgConfig
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("requestCannedMessagesModuleConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true

		meshPacket.decoded = dataMessage

		let messageDescription = "🛎️ Requested Canned Messages Module Config using an admin key for node: \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
	}

	public func saveDetectionSensorModuleConfig(config: ModuleConfig.DetectionSensorConfig, fromUser: UserEntity, toUser: UserEntity) async throws -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.detectionSensor = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("saveDetectionSensorModuleConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage

		let messageDescription = "🛟 Saved Detection Sensor Module Config for \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)

			upsertDetectionSensorModuleConfigPacket(config: config, nodeNum: toUser.num, context: context)

		return Int64(meshPacket.id)
	}

	public func requestDetectionSensorModuleConfig(fromUser: UserEntity, toUser: UserEntity) async throws {

		var adminPacket = AdminMessage()
		adminPacket.getModuleConfigRequest = AdminMessage.ModuleConfigType.detectionsensorConfig
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("requestDetectionSensorModuleConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true

		meshPacket.decoded = dataMessage

		let messageDescription = "🛎️ Requested Detection Sensor Module Config using an admin key for node: \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
	}

	public func saveExternalNotificationModuleConfig(config: ModuleConfig.ExternalNotificationConfig, fromUser: UserEntity, toUser: UserEntity) async throws -> Int64 {
		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.externalNotification = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("saveExternalNotificationModuleConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage

		let messageDescription = "🛟 Saved External Notification Module Config for \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)

			upsertExternalNotificationModuleConfigPacket(config: config, nodeNum: toUser.num, context: context)

		return Int64(meshPacket.id)
	}

	public func savePaxcounterModuleConfig(config: ModuleConfig.PaxcounterConfig, fromUser: UserEntity, toUser: UserEntity) async throws -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.paxcounter = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("savePaxcounterModuleConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage

		let messageDescription = "🛟 Saved PAX Counter Module Config for \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)

			upsertPaxCounterModuleConfigPacket(config: config, nodeNum: toUser.num, context: context)

		return Int64(meshPacket.id)
	}

	public func saveRtttlConfig(ringtone: String, fromUser: UserEntity, toUser: UserEntity) async throws -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setRingtoneMessage = ringtone
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("saveRtttlConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage

		let messageDescription = "🛟 Saved RTTTL Ringtone Config for \(toUser.longName ?? "Unknown".localized)"

		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)

			upsertRtttlConfigPacket(ringtone: ringtone, nodeNum: toUser.num, context: context)

		return Int64(meshPacket.id)
	}

	public func saveMQTTConfig(config: ModuleConfig.MQTTConfig, fromUser: UserEntity, toUser: UserEntity) async throws -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.mqtt = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("saveMQTTConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp

		meshPacket.decoded = dataMessage

		let messageDescription = "🛟 Saved MQTT Config for \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)

			upsertMqttModuleConfigPacket(config: config, nodeNum: toUser.num, context: context)

		return Int64(meshPacket.id)
	}

	public func saveRangeTestModuleConfig(config: ModuleConfig.RangeTestConfig, fromUser: UserEntity, toUser: UserEntity) async throws -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.rangeTest = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("saveRangeTestModuleConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage

		let messageDescription = "🛟 Saved Range Test Module Config for \(toUser.longName ?? "Unknown".localized)"

		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)

			upsertRangeTestModuleConfigPacket(config: config, nodeNum: toUser.num, context: context)

		return Int64(meshPacket.id)
	}

	public func saveSerialModuleConfig(config: ModuleConfig.SerialConfig, fromUser: UserEntity, toUser: UserEntity) async throws -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.serial = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("saveSerialModuleConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage

		let messageDescription = "🛟 Saved Serial Module Config for \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)

			upsertSerialModuleConfigPacket(config: config, nodeNum: toUser.num, context: context)

		return Int64(meshPacket.id)
	}

	public func requestExternalNotificationModuleConfig(fromUser: UserEntity, toUser: UserEntity) async throws {

		var adminPacket = AdminMessage()
		adminPacket.getModuleConfigRequest = AdminMessage.ModuleConfigType.extnotifConfig
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("requestExternalNotificationModuleConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true

		meshPacket.decoded = dataMessage

		let messageDescription = "🛎️ Requested External Notificaiton Module Config using an admin key for node: \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
	}

	public func requestPaxCounterModuleConfig(fromUser: UserEntity, toUser: UserEntity) async throws {
		var adminPacket = AdminMessage()
		adminPacket.getModuleConfigRequest = AdminMessage.ModuleConfigType.paxcounterConfig
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("requestPaxCounterModuleConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true

		meshPacket.decoded = dataMessage

		let messageDescription = "🛎️ Requested PAX Counter Module Config using an admin key for node: \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
	}

	public func requestRtttlConfig(fromUser: UserEntity, toUser: UserEntity) async throws {

		var adminPacket = AdminMessage()
		adminPacket.getRingtoneRequest = true
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("requestRtttlConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true

		meshPacket.decoded = dataMessage

		let messageDescription = "🛎️ Requested RTTTL Ringtone Config using an admin key for node: \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
	}

	public func requestRangeTestModuleConfig(fromUser: UserEntity, toUser: UserEntity) async throws {

		var adminPacket = AdminMessage()
		adminPacket.getModuleConfigRequest = AdminMessage.ModuleConfigType.rangetestConfig
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("requestRangeTestModuleConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true

		meshPacket.decoded = dataMessage

		let messageDescription = "🛎️ Requested Range Test Module Config using an admin key for node: \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
	}

	public func requestMqttModuleConfig(fromUser: UserEntity, toUser: UserEntity) async throws {

		var adminPacket = AdminMessage()
		adminPacket.getModuleConfigRequest = AdminMessage.ModuleConfigType.mqttConfig
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("requestMqttModuleConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true

		meshPacket.decoded = dataMessage

		let messageDescription = "🛎️ Requested MQTT Module Config using an admin key for node: \(String(activeDeviceNum ?? 0))"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
	}

	public func requestSerialModuleConfig(fromUser: UserEntity, toUser: UserEntity) async throws {

		var adminPacket = AdminMessage()
		adminPacket.getModuleConfigRequest = AdminMessage.ModuleConfigType.serialConfig
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("requestSerialModuleConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true

		meshPacket.decoded = dataMessage

		let messageDescription = "🛎️ Requested Serial Module Config using an admin key for node: \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
	}

	public func saveStoreForwardModuleConfig(config: ModuleConfig.StoreForwardConfig, fromUser: UserEntity, toUser: UserEntity) async throws -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.storeForward = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("saveStoreForwardModuleConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage

		let messageDescription = "🛟 Saved Store & Forward Module Config for \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)

			upsertStoreForwardModuleConfigPacket(config: config, nodeNum: toUser.num, context: context)

		return Int64(meshPacket.id)
	}

	public func requestStoreAndForwardModuleConfig(fromUser: UserEntity, toUser: UserEntity) async throws {

		var adminPacket = AdminMessage()
		adminPacket.getModuleConfigRequest = AdminMessage.ModuleConfigType.storeforwardConfig
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("requestStoreAndForwardModuleConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true

		meshPacket.decoded = dataMessage

		let messageDescription = "🛎️ Requested Store and Forward Module Config using an admin key for node: \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)

	}

	public func sendEnterDfuMode(fromUser: UserEntity, toUser: UserEntity) async throws {
		var adminPacket = AdminMessage()
		adminPacket.enterDfuModeRequest = true
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		meshPacket.channel = UInt32(0)
		var dataMessage = DataMessage()
		if let serializedData: Data = try? adminPacket.serializedData() {
			dataMessage.payload = serializedData
			dataMessage.portnum = PortNum.adminApp
			meshPacket.decoded = dataMessage
		} else {
			throw AccessoryError.ioFailed("sendEnterDfuMode: Unable to serialize admin packet")
		}
		// TODO: automatic reconnect
		// automaticallyReconnect = false
		let messageDescription = "🚀 Sent enter DFU mode Admin Message to: \(toUser.longName ?? "Unknown".localized) from: \(fromUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
	}

	public func sendRebootOta(fromUser: UserEntity, toUser: UserEntity) async throws {
		var adminPacket = AdminMessage()
		adminPacket.rebootOtaSeconds = 5
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		if let serializedData: Data = try? adminPacket.serializedData() {
			dataMessage.payload = serializedData
			dataMessage.portnum = PortNum.adminApp
			meshPacket.decoded = dataMessage
		} else {
			throw AccessoryError.ioFailed("sendRebootOta: Unable to serialize admin packet")
		}
		let messageDescription = "🚀 Sent Reboot OTA Admin Message to: \(toUser.longName ?? "Unknown".localized) from: \(fromUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
	}

	public func saveUser(config: User, fromUser: UserEntity, toUser: UserEntity) async throws -> Int64 {
		var adminPacket = AdminMessage()
		adminPacket.setOwner = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		if let serializedData: Data = try? adminPacket.serializedData() {
			dataMessage.payload = serializedData
			dataMessage.portnum = PortNum.adminApp
			meshPacket.decoded = dataMessage
		} else {
			throw AccessoryError.ioFailed("saveUser: Unable to serialize admin packet")
		}
		let messageDescription = "🛟 Saved User Config for \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
		return Int64(meshPacket.id)
	}

	public func saveLicensedUser(ham: HamParameters, fromUser: UserEntity, toUser: UserEntity) async throws -> Int64 {
		var adminPacket = AdminMessage()
		adminPacket.setHamMode = ham
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("saveLicensedUser: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		let messageDescription = "🛟 Saved Ham Parameters for \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
		return Int64(meshPacket.id)
	}

	public func sendFactoryReset(fromUser: UserEntity, toUser: UserEntity, resetDevice: Bool = false) async throws {
		var adminPacket = AdminMessage()
		if resetDevice {
			adminPacket.factoryResetDevice = 5
		} else {
			adminPacket.factoryResetConfig = 5
		}
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	=  UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		if let serializedData: Data = try? adminPacket.serializedData() {
			dataMessage.payload = serializedData
			dataMessage.portnum = PortNum.adminApp
			meshPacket.decoded = dataMessage
		} else {
			throw AccessoryError.ioFailed("saveLicensedUser: Unable to serialize admin packet")
		}

		let messageDescription = "🚀 Sent Factory Reset Admin Message to: \(toUser.longName ?? "Unknown".localized) from: \(fromUser.longName ??  "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
	}

	public func setFixedPosition(fromUser: UserEntity, channel: Int32) async throws {
		var adminPacket = AdminMessage()

		guard let positionPacket = try await getPositionFromPhoneGPS(destNum: fromUser.num, fixedPosition: true) else {
			throw AccessoryError.appError("Unable to get position from GPS")
		}

		adminPacket.setFixedPosition = positionPacket
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(fromUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		meshPacket.channel = UInt32(channel)
		var dataMessage = DataMessage()
		meshPacket.decoded = dataMessage
		if let serializedData: Data = try? adminPacket.serializedData() {
			dataMessage.payload = serializedData
			dataMessage.portnum = PortNum.adminApp
			meshPacket.decoded = dataMessage
		} else {
			throw AccessoryError.ioFailed("setFixedPosition: Unable to serialize admin packet")
		}
		let messageDescription = "🚀 Sent Set Fixed Postion Admin Message to: \(fromUser.longName ?? "Unknown".localized) from: \(fromUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
	}

	public func removeFixedPosition(fromUser: UserEntity, channel: Int32) async throws {
		var adminPacket = AdminMessage()
		adminPacket.removeFixedPosition = true
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(fromUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		meshPacket.channel = UInt32(channel)
		var dataMessage = DataMessage()
		if let serializedData: Data = try? adminPacket.serializedData() {
			dataMessage.payload = serializedData
			dataMessage.portnum = PortNum.adminApp
			meshPacket.decoded = dataMessage
		} else {
			throw AccessoryError.ioFailed("setFixedPosition: Unable to serialize admin packet")
		}
		let messageDescription = "🚀 Sent Remove Fixed Position Admin Message to: \(fromUser.longName ?? "Unknown".localized) from: \(fromUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
	}

	public func savePositionConfig(config: Config.PositionConfig, fromUser: UserEntity, toUser: UserEntity) async throws -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setConfig.position = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("savePositionConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp

		meshPacket.decoded = dataMessage

		let messageDescription = "🛟 Saved Position Config for \(toUser.longName ?? "Unknown".localized)"

		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)

			upsertPositionConfigPacket(config: config, nodeNum: toUser.num, context: context)

		return Int64(meshPacket.id)
	}

	public func requestPositionConfig(fromUser: UserEntity, toUser: UserEntity) async throws {

		var adminPacket = AdminMessage()
		adminPacket.getConfigRequest = AdminMessage.ConfigType.positionConfig
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("requestPositionConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true

		meshPacket.decoded = dataMessage

		let messageDescription = "🛎️ Requested Position Config using an admin key for node: \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
	}

	public func savePowerConfig(config: Config.PowerConfig, fromUser: UserEntity, toUser: UserEntity) async throws -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setConfig.power = config

		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("savePowerConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp

		meshPacket.decoded = dataMessage

		let messageDescription = "🛟 Saved Power Config for \(toUser.longName ?? "Unknown".localized)"

		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)

			upsertPowerConfigPacket(config: config, nodeNum: toUser.num, context: context)

		return Int64(meshPacket.id)
	}

	public func requestPowerConfig(fromUser: UserEntity, toUser: UserEntity) async throws {
		var adminPacket = AdminMessage()
		adminPacket.getConfigRequest = AdminMessage.ConfigType.powerConfig
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("requestPowerConfig: Unable to serialize admin packet")

		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true

		meshPacket.decoded = dataMessage

		let messageDescription = "🛎️ Requested Power Config using an admin key for node: \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
	}

	public func saveNetworkConfig(config: Config.NetworkConfig, fromUser: UserEntity, toUser: UserEntity) async throws -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setConfig.network = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("saveNetworkConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp

		meshPacket.decoded = dataMessage

		let messageDescription = "🛟 Saved Network Config for \(toUser.longName ?? "Unknown".localized)"

		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)

			upsertNetworkConfigPacket(config: config, nodeNum: toUser.num, context: context)

		return Int64(meshPacket.id)
	}

	public func saveSecurityConfig(config: Config.SecurityConfig, fromUser: UserEntity, toUser: UserEntity) async throws -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setConfig.security = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("saveSecurityConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp

		meshPacket.decoded = dataMessage

		let messageDescription = "🛟 Saved Security Config for \(toUser.longName ?? "Unknown".localized)"

		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)

			upsertSecurityConfigPacket(config: config, nodeNum: toUser.num, context: context)

		return Int64(meshPacket.id)
	}

	public func requestSecurityConfig(fromUser: UserEntity, toUser: UserEntity) async throws {

		var adminPacket = AdminMessage()
		adminPacket.getConfigRequest = AdminMessage.ConfigType.securityConfig
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("requestSecurityConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true

		meshPacket.decoded = dataMessage

		let messageDescription = "🛎️ Requested Security Config using an admin key for node: \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
	}

	public func requestTelemetryModuleConfig(fromUser: UserEntity, toUser: UserEntity) async throws {

		var adminPacket = AdminMessage()
		adminPacket.getModuleConfigRequest = AdminMessage.ModuleConfigType.telemetryConfig
		adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("requestTelemetryModuleConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true

		meshPacket.decoded = dataMessage

		let messageDescription = "🛎️ Requested Telemetry Module Config for node: \(toUser.longName ?? "unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
	}

	public func sendNodeDBReset(fromUser: UserEntity, toUser: UserEntity) async throws {
		var adminPacket = AdminMessage()
		adminPacket.nodedbReset = true
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= 0 // UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("sendNodeDBReset: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp

		meshPacket.decoded = dataMessage
		let messageDescription = "🚀 Sent NodeDB Reset Admin Message to: \(toUser.longName ?? "unknown".localized) from: \(fromUser.longName ?? "unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
	}

	public func requestBluetoothConfig(fromUser: UserEntity, toUser: UserEntity) async throws {

		var adminPacket = AdminMessage()
		adminPacket.getConfigRequest = AdminMessage.ConfigType.bluetoothConfig
		if UserDefaults.enableAdministration {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("requestBluetoothConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true

		meshPacket.decoded = dataMessage

		let messageDescription = "🛎️ Requested Bluetooth Config for node: \(String(activeDeviceNum ?? -1))"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
	}

	public func saveBluetoothConfig(config: Config.BluetoothConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32? = nil) async throws -> Int64 {
		var adminPacket = AdminMessage()
		adminPacket.setConfig.bluetooth = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		if let adminIndex = adminIndex {
			meshPacket.channel = UInt32(adminIndex)
		}
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("saveBluetoothConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		let messageDescription = "🛟 Saved Bluetooth Config for \(toUser.longName ?? "unknown".localized)"

		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)

			upsertBluetoothConfigPacket(config: config, nodeNum: toUser.num, sessionPasskey: toUser.userNode?.sessionPasskey, context: context)

		return Int64(meshPacket.id)
	}

	public func saveTelemetryModuleConfig(config: ModuleConfig.TelemetryConfig, fromUser: UserEntity, toUser: UserEntity) async throws -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.telemetry = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("saveTelemetryModuleConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage

		let messageDescription = "Saved Telemetry Module Config for \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)

			upsertTelemetryModuleConfigPacket(config: config, nodeNum: toUser.num, context: context)

		return Int64(meshPacket.id)
	}

	public func requestDisplayConfig(fromUser: UserEntity, toUser: UserEntity) async throws {

		var adminPacket = AdminMessage()
		adminPacket.getConfigRequest = AdminMessage.ConfigType.displayConfig
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("requestDisplayConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true

		meshPacket.decoded = dataMessage

		let messageDescription = "🛎️ Requested Display Config using an admin key for node: \(toUser.longName ?? "Unknown".localized)"

		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
	}

	public func saveDisplayConfig(config: Config.DisplayConfig, fromUser: UserEntity, toUser: UserEntity) async throws -> Int64 {
		var adminPacket = AdminMessage()
		adminPacket.setConfig.display = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("saveDisplayConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		let messageDescription = "🛟 Saved Display Config for \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)

			upsertDisplayConfigPacket(config: config, nodeNum: toUser.num, sessionPasskey: toUser.userNode?.sessionPasskey, context: context)

		return Int64(meshPacket.id)
	}

	public func requestNetworkConfig(fromUser: UserEntity, toUser: UserEntity) async throws {

		var adminPacket = AdminMessage()
		adminPacket.getConfigRequest = AdminMessage.ConfigType.networkConfig
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("requestNetworkConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		meshPacket.decoded = dataMessage

		let messageDescription = "🛎️ Requested Network Config using an admin Key for node: \(toUser.longName ?? "Unknown".localized)"

		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
	}

	public func requestDeviceConfig(fromUser: UserEntity, toUser: UserEntity) async throws {

		var adminPacket = AdminMessage()
		adminPacket.getConfigRequest = AdminMessage.ConfigType.deviceConfig
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("requestDeviceConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true

		meshPacket.decoded = dataMessage

		let messageDescription = "🛎️ Requested Device Config using an admin key for node: \(toUser.longName ?? "Unknown".localized)"

		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
	}

	public func saveDeviceConfig(config: Config.DeviceConfig, fromUser: UserEntity, toUser: UserEntity) async throws -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setConfig.device = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("saveDeviceConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		let messageDescription = "🛟 Saved Device Config for \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)

			upsertDeviceConfigPacket(config: config, nodeNum: toUser.num, sessionPasskey: toUser.userNode?.sessionPasskey, context: context)

		return Int64(meshPacket.id)
	}

	public func saveLoRaConfig(config: Config.LoRaConfig, fromUser: UserEntity, toUser: UserEntity) async throws -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setConfig.lora = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("saveLoRaConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		let messageDescription = "🛟 Saved LoRa Config for \(toUser.longName ?? "Unknown".localized)"

		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)

		upsertLoRaConfigPacket(config: config, nodeNum: toUser.num, sessionPasskey: toUser.userNode?.sessionPasskey, context: context)

		return Int64(meshPacket.id)
	}
	public func requestLoRaConfig(fromUser: UserEntity, toUser: UserEntity) async throws {

			var adminPacket = AdminMessage()
			adminPacket.getConfigRequest = AdminMessage.ConfigType.loraConfig
			var meshPacket: MeshPacket = MeshPacket()
			meshPacket.to = UInt32(toUser.num)
			meshPacket.from	= UInt32(fromUser.num)
			meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
			meshPacket.priority =  MeshPacket.Priority.reliable
			meshPacket.wantAck = true

			var dataMessage = DataMessage()
			guard let adminData: Data = try? adminPacket.serializedData() else {
				throw AccessoryError.ioFailed("requestLoRaConfig: Unable to serialize admin packet")
			}
			dataMessage.payload = adminData
			dataMessage.portnum = PortNum.adminApp
			dataMessage.wantResponse = true

			meshPacket.decoded = dataMessage

			let messageDescription = "🛎️ Requested LoRa Config using an admin key for node: \(toUser.longName ?? "Unknown".localized)"

			try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
		}
}
