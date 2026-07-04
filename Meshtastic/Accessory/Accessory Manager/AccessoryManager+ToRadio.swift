//
//  AccessoryManager+ToRadio.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/18/25.
//

import Foundation
import MeshtasticProtobufs
import OSLog
@preconcurrency import SwiftData

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
			Logger.admin.debug("\(adminDescription, privacy: .public)")
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
					// Do not auto-favorite when using CLIENT_BASE role to avoid creating routing issues
					let shouldFavorite = connectedDeviceRole != .clientBase
					await MeshPackets.shared.upsertNodeInfoPacket(packet: nodeMeshPacket, favorite: shouldFavorite, overTheMesh: false)
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

			let messageUsers = FetchDescriptor<UserEntity>(predicate: #Predicate { $0.num == fromUserNum || $0.num == toUserNum })

			do {
				let fetchedUsers = try context.fetch(messageUsers)
				if fetchedUsers.isEmpty {

					Logger.data.error("🚫 Message Users Not Found, Fail")
					throw AccessoryError.ioFailed("🚫 Message Users Not Found, Fail")
				} else if fetchedUsers.count >= 1 {
					let newMessage = MessageEntity()
					context.insert(newMessage)
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
						Logger.mesh.info("💬 \(logString, privacy: .public)")
					}
					do {
						try context.save()
						Logger.data.info("💾 Saved a new sent message from \(self.activeDeviceNum?.toHex() ?? "0", privacy: .public) to \(toUserNum.toHex(), privacy: .public)")
						// Donate outgoing message to SiriKit for CarPlay
						if !isEmoji {
							#if os(iOS)
							CarPlayIntentDonation.donateOutgoingMessage(content: message, toUserNum: toUserNum, channel: channel)
							#endif
						}
					} catch {
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
		let channelLink = try MeshtasticChannelURL.parse(base64UrlString, defaultAddChannels: addChannels)
		try await saveChannelSet(
			channelSet: channelLink.channelSet,
			addChannels: channelLink.addChannels,
			okToMQTT: okToMQTT
		)
	}

	public func saveChannelSet(channelSet incomingChannelSet: ChannelSet, addChannels: Bool = false, okToMQTT: Bool = false) async throws {
		guard let deviceNum = self.activeConnection?.device.num else {
			Logger.services.error("Error while sending saveChannelSet request.  No active device.")
			throw AccessoryError.ioFailed("No active device")
		}

		guard !incomingChannelSet.settings.isEmpty else {
			throw AccessoryError.appError("No channels found in QR code")
		}

		guard incomingChannelSet.settings.count <= 8 else {
			throw AccessoryError.appError("A Meshtastic radio supports up to 8 channels")
		}

		if !addChannels && !incomingChannelSet.hasLoraConfig {
			throw AccessoryError.appError("Replace requires LoRa configuration in the QR code")
		}

		var channelSet = incomingChannelSet
		let incomingChannelNames = channelSet.settings.map(\.name)
		guard Set(incomingChannelNames).count == incomingChannelNames.count else {
			throw AccessoryError.appError("Channel names must be unique")
		}
		var i: Int32 = 0

		if addChannels {
			let fetchMyInfoRequest = FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == deviceNum })

			let fetchedMyInfo = try context.fetch(fetchMyInfoRequest)
			guard fetchedMyInfo.count == 1, let fetched = fetchedMyInfo.first else {
				throw AccessoryError.appError("MyInfo not found")
			}

			i = Int32(fetched.channels.count)

			guard i >= 0 && i < 8 else {
				throw AccessoryError.appError("No free channel slots available")
			}

			guard fetched.channels.count + channelSet.settings.count <= 8 else {
				throw AccessoryError.appError("Not enough free channel slots")
			}

			for cs in channelSet.settings {
				if fetched.channels.contains(where: { $0.name == cs.name }) {
					throw AccessoryError.appError("Channel already exists")
				}
			}
		} else {
			let currentLoRaConfig = currentLoRaConfig(for: deviceNum)
			channelSet.loraConfig.configOkToMqtt = currentLoRaConfig?.configOkToMqtt ?? okToMQTT
			if let txPower = currentLoRaConfig?.txPower {
				channelSet.loraConfig.txPower = txPower
			}
		}

		var deliveredChannels: [Channel] = []
		for cs in channelSet.settings {
			var chan = Channel()
			chan.role = (i == 0) ? .primary : .secondary
			chan.settings = cs
			chan.index = i
			// Ensure moduleSettings is always explicitly set so the device
			// stores a defined position_precision value. QR codes typically
			// omit moduleSettings which causes the firmware to default to 32
			// (full precision), leaking exact GPS coordinates.
			if !cs.hasModuleSettings {
				chan.settings.moduleSettings.positionPrecision = 0
				chan.settings.moduleSettings.isMuted = false
			}
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
			deliveredChannels.append(chan)
		}

		// Replacing channels also replaces the LoRa config (the replace-mode guard
		// above guarantees one is present), and sending it reboots the device.
		let didSendLoRaConfig = !addChannels
		if didSendLoRaConfig {
			// Save the LoRa Config and the device will reboot if required.
			var adminPacket = AdminMessage()
			adminPacket.setConfig.lora = channelSet.loraConfig
			var meshPacket = MeshPacket()
			meshPacket.to = UInt32(deviceNum)
			meshPacket.from	= UInt32(deviceNum)
			meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
			meshPacket.priority =  MeshPacket.Priority.reliable
			meshPacket.wantAck = true
			meshPacket.channel = 0
			var dataMessage = DataMessage()
			guard let adminData: Data = try? adminPacket.serializedData() else {
				throw AccessoryError.ioFailed("saveChannelSet: Unable to serialize LoRa config")
			}
			dataMessage.payload = adminData
			dataMessage.portnum = PortNum.adminApp
			meshPacket.decoded = dataMessage
			var toRadio = ToRadio()
			toRadio.packet = meshPacket

			let logString = String.localizedStringWithFormat("Sent a LoRa.Config for: %@".localized, String(deviceNum))
			try await send(toRadio, debugDescription: logString)
		}

		// Mirror delivered channels locally only after channel and LoRa writes
		// succeed, so a failed replace cannot wipe local state.
		if !addChannels {
			tryClearExistingChannels()
		}
		for chan in deliveredChannels {
			await MeshPackets.shared.channelPacket(channel: chan, fromNum: deviceNum)
		}

		// Re-sync after the change. When we sent a LoRa config the device reboots
		// and the connection drops, so the follow-up wantConfig is expected to fail
		// — treat that as success since the channels/config were already delivered.
		// When no reboot is expected, let wantConfig errors surface normally.
		if didSendLoRaConfig {
			do {
				Logger.transport.debug("[AccessoryManager] sending wantConfig after channel set (device may reboot)")
				try await sendWantConfig()
			} catch {
				Logger.transport.warning("[AccessoryManager] wantConfig after channel set did not complete; device is likely rebooting: \(error.localizedDescription, privacy: .public)")
			}
		} else {
			Logger.transport.debug("[AccessoryManager] sending wantConfig for saveChannelSet")
			try await sendWantConfig()
		}
	}

	private func currentLoRaConfig(for deviceNum: Int64) -> Config.LoRaConfig? {
		let request = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == deviceNum })
		do {
			return try context.fetch(request).first?.loRaConfig?.toProto()
		} catch {
			Logger.data.error("Failed to fetch current LoRa config while saving channel set: \(error.localizedDescription, privacy: .public)")
			return nil
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

	/// Join a mesh advertised by a beacon: set the primary channel to the offered channel (name +
	/// PSK), then apply the offered region/preset. The channel change lands first (no reboot); the
	/// LoRa config change reboots the radio onto the advertised mesh. `region`/`preset` fall back to
	/// the radio's current values when the beacon didn't advertise them. `channelNum` is forced to 0
	/// so the firmware derives the frequency from the new channel name + preset + region.
	@MainActor
	public func joinBeaconMesh(channelName: String, channelPSK: Data, region: RegionCodes?, preset: ModemPresets?) async throws {
		guard let deviceNum = self.activeConnection?.device.num else {
			throw AccessoryError.ioFailed("No active device")
		}
		guard let node = getNodeInfo(id: Int64(deviceNum), context: context), let user = node.user else {
			throw AccessoryError.appError("Connected node not found")
		}

		// Snapshot the current primary channel so a partial failure (channel write succeeds but the
		// LoRa apply fails) can be rolled back — otherwise the radio is stranded on a new channel with
		// the old preset/region on an undecodable frequency (research D3 / contract C4).
		let primarySnapshot = beaconPrimaryChannelSnapshot(for: node)

		// D5: an offered channel with an empty PSK is an "open channel" — use the well-known default
		// public key rather than sending an empty (no-encryption) key.
		let effectivePSK = channelPSK.isEmpty ? Data([1]) : channelPSK

		// 1. Set the primary channel to the beacon's offered channel (no reboot).
		var channel = Channel()
		channel.index = 0
		channel.role = .primary
		channel.settings.name = channelName
		channel.settings.psk = effectivePSK
		// Default to no position sharing on a foreign/beacon-advertised mesh (privacy). Otherwise the
		// firmware defaults moduleSettings to full precision (32), leaking exact GPS coordinates —
		// mirrors addBeaconChannel's handling for the same "join someone else's mesh" scenario.
		channel.settings.moduleSettings.positionPrecision = 0
		_ = try await saveChannel(channel: channel, fromUser: user, toUser: user)

		// 2. Apply region/preset (reboots). Carry the full existing LoRa config so unrelated fields
		//    (bandwidth, coding rate, overrides, MQTT flags…) aren't wiped.
		var lora = Config.LoRaConfig()
		if let existing = node.loRaConfig, !existing.isDeleted {
			lora.usePreset = existing.usePreset
			lora.hopLimit = UInt32(existing.hopLimit)
			lora.txEnabled = existing.txEnabled
			lora.txPower = existing.txPower
			lora.bandwidth = UInt32(existing.bandwidth)
			lora.codingRate = UInt32(existing.codingRate)
			lora.spreadFactor = UInt32(existing.spreadFactor)
			lora.frequencyOffset = existing.frequencyOffset
			lora.overrideFrequency = existing.overrideFrequency
			lora.overrideDutyCycle = existing.overrideDutyCycle
			lora.sx126XRxBoostedGain = existing.sx126xRxBoostedGain
			lora.ignoreMqtt = existing.ignoreMqtt
			lora.configOkToMqtt = existing.okToMqtt
			lora.region = Config.LoRaConfig.RegionCode(rawValue: Int(existing.regionCode)) ?? .unset
			lora.modemPreset = ModemPresets(rawValue: Int(existing.modemPreset))?.protoEnumValue() ?? .longFast
		}
		if let region { lora.region = region.protoEnumValue() }
		if let preset { lora.modemPreset = preset.protoEnumValue() }
		lora.usePreset = true
		// Derive the frequency from the new channel + preset + region rather than a stale slot.
		lora.channelNum = 0
		do {
			_ = try await saveLoRaConfig(config: lora, fromUser: user, toUser: user)
		} catch {
			// Roll the primary channel back so we don't strand the radio between meshes. The channel
			// write doesn't reboot, so this restore is safe.
			Logger.admin.error("🔀 [Beacon] LoRa apply failed after channel write; rolling back primary channel: \(error.localizedDescription, privacy: .public)")
			if let primarySnapshot {
				do {
					_ = try await saveChannel(channel: primarySnapshot, fromUser: user, toUser: user)
					Logger.admin.info("🔀 [Beacon] Rolled back primary channel after failed switch")
				} catch {
					Logger.admin.error("🔀 [Beacon] Primary channel rollback also failed: \(error.localizedDescription, privacy: .public)")
				}
			}
			throw error
		}
		Logger.mesh.info("🔀 [Beacon] Switched to advertised channel '\(channelName, privacy: .private)' and applied preset/region")
	}

	/// Reconstruct a `Channel` proto for the connected node's current primary channel (index 0),
	/// used to roll back a failed Switch. Returns `nil` when there's no stored primary to restore.
	@MainActor
	private func beaconPrimaryChannelSnapshot(for node: NodeInfoEntity) -> Channel? {
		guard let primary = node.myInfo?.channels.first(where: { $0.index == 0 || $0.role == 1 }) else {
			return nil
		}
		var channel = Channel()
		channel.index = 0
		channel.role = .primary
		channel.settings.name = primary.name ?? ""
		channel.settings.psk = primary.psk ?? Data()
		channel.settings.uplinkEnabled = primary.uplinkEnabled
		channel.settings.downlinkEnabled = primary.downlinkEnabled
		channel.settings.moduleSettings.positionPrecision = UInt32(primary.positionPrecision)
		return channel
	}

	/// A secondary channel slot a beacon channel could replace (research D2).
	public struct BeaconSecondaryChannel: Identifiable, Sendable {
		public let index: Int32
		public let name: String
		public var id: Int32 { index }
	}

	/// The connected node's secondary channels (index 1–7) that a beacon channel could replace when
	/// no free slot is available (research D2). Never returns the primary (index 0); falls back to
	/// "Channel N" for an unnamed slot.
	@MainActor
	public func beaconReplaceableSecondaryChannels() -> [BeaconSecondaryChannel] {
		guard let deviceNum = self.activeConnection?.device.num,
			  let node = getNodeInfo(id: Int64(deviceNum), context: context) else {
			return []
		}
		return (node.myInfo?.channels ?? [])
			.filter { $0.index >= 1 && $0.index <= 7 }
			.sorted { $0.index < $1.index }
			.map { channel in
				let name = channel.name?.isEmpty == false ? channel.name! : "Channel \(channel.index)"
				return BeaconSecondaryChannel(index: channel.index, name: name)
			}
	}

	/// Whether at least one secondary slot (1–7) is free on the connected node.
	@MainActor
	public func beaconHasFreeSecondarySlot() -> Bool {
		guard let deviceNum = self.activeConnection?.device.num,
			  let node = getNodeInfo(id: Int64(deviceNum), context: context) else {
			return false
		}
		let usedIndexes = Set(node.myInfo?.channels.map { $0.index } ?? [])
		return (Int32(1)...Int32(7)).contains { !usedIndexes.contains($0) }
	}

	/// Add a beacon's advertised channel to a secondary slot without touching the primary channel or
	/// LoRa config — so **no reboot** (contract C3 / FR-016, research D2). Used by the Add channel
	/// action, which is only offered when the offered mesh already runs on the radio's current
	/// preset/region/frequency slot.
	///
	/// When `replacingIndex` is nil, picks the lowest free secondary index (1–7); when all secondary
	/// slots are taken, throws so the UI can offer the replace-a-secondary picker (D2). When
	/// `replacingIndex` is provided, writes into that (secondary) slot, overwriting the channel there —
	/// never the primary (index 0).
	@MainActor
	public func addBeaconChannel(channelName: String, channelPSK: Data, replacingIndex: Int32? = nil) async throws {
		guard let deviceNum = self.activeConnection?.device.num else {
			throw AccessoryError.ioFailed("No active device")
		}
		guard let node = getNodeInfo(id: Int64(deviceNum), context: context), let user = node.user else {
			throw AccessoryError.appError("Connected node not found")
		}

		let targetIndex: Int32
		if let replacingIndex {
			// Protect the primary channel — only secondary slots may be replaced (D2).
			guard (Int32(1)...Int32(7)).contains(replacingIndex) else {
				throw AccessoryError.appError("Cannot replace the primary channel")
			}
			targetIndex = replacingIndex
		} else {
			let usedIndexes = Set(node.myInfo?.channels.map { $0.index } ?? [])
			// Secondary slots are 1...7 (0 is reserved for the primary channel).
			guard let freeIndex = (Int32(1)...Int32(7)).first(where: { !usedIndexes.contains($0) }) else {
				throw AccessoryError.appError("No free channel slot — remove a secondary channel first")
			}
			targetIndex = freeIndex
		}

		// D5: an offered channel with an empty PSK is an "open channel" — use the default public key.
		let effectivePSK = channelPSK.isEmpty ? Data([1]) : channelPSK

		var channel = Channel()
		channel.index = targetIndex
		channel.role = .secondary
		channel.settings.name = channelName
		channel.settings.psk = effectivePSK
		// Default to no position sharing on an added foreign channel.
		channel.settings.moduleSettings.positionPrecision = 0

		_ = try await saveChannel(channel: channel, fromUser: user, toUser: user)

		// Mirror the added channel into local state so it appears immediately (no reboot / re-sync).
		await MeshPackets.shared.channelPacket(channel: channel, fromNum: deviceNum)

		Logger.mesh.info("➕ [Beacon] Added advertised channel '\(channelName, privacy: .private)' to secondary slot \(targetIndex, privacy: .public) — no reboot")
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
				wayPointEntity.locked = true
			} else {
				wayPointEntity.locked = false
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

			let traceRoute = TraceRouteEntity()
			context.insert(traceRoute)
			traceRoute.sent = true
			// TODO: Not sure what's going on here. We always have a fromNodeNum
			let nodes = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == destNum || $0.num == fromNodeNum })
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
					let nsError = error as NSError
					Logger.data.error("Error Updating Core Data BluetoothConfigEntity: \(nsError, privacy: .public)")
				}

				let logString = String.localizedStringWithFormat("Sent a Trace Route Request to node: %@".localized, destNum.toHex())
				Logger.mesh.info("🪧 \(logString, privacy: .public)")

			} catch {

			}

	}

	public func requestStoreAndForwardClientHistory(fromUser: UserEntity, toUser: UserEntity, channel: Int32) async throws {

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
		meshPacket.channel = UInt32(channel)
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
				if let user = node.user {
					context.delete(user)
				}
				context.delete(node)
				try context.save()
			} catch {
				let nsError = error as NSError
				Logger.data.error("🚫 Error deleting node: \(nsError, privacy: .public)")
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

		let messageDescription = "🛎️ [Device Metadata] Requested for node \(toUser?.longName ?? "#\(toUserNum)") by \(fromUser?.longName ?? "#\(fromUserNum)")"
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

		await MeshPackets.shared.upsertAmbientLightingModuleConfigPacket(config: config, nodeNum: toUser.num)

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

		await MeshPackets.shared.upsertCannedMessagesModuleConfigPacket(config: config, nodeNum: toUser.num)

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

		await MeshPackets.shared.upsertDetectionSensorModuleConfigPacket(config: config, nodeNum: toUser.num)

		return Int64(meshPacket.id)
	}

	public func saveMeshBeaconModuleConfig(config: ModuleConfig.MeshBeaconConfig, fromUser: UserEntity, toUser: UserEntity) async throws -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.meshBeacon = config
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
			throw AccessoryError.ioFailed("saveMeshBeaconModuleConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage

		let messageDescription = "🛟 Saved Mesh Beacon Module Config for \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)

		await MeshPackets.shared.upsertMeshBeaconModuleConfigPacket(config: config, nodeNum: toUser.num)

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

		await MeshPackets.shared.upsertExternalNotificationModuleConfigPacket(config: config, nodeNum: toUser.num)

		return Int64(meshPacket.id)
	}

	public func saveNeighborInfoModuleConfig(config: ModuleConfig.NeighborInfoConfig, fromUser: UserEntity, toUser: UserEntity) async throws -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.neighborInfo = config
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
			throw AccessoryError.ioFailed("saveNeighborInfoModuleConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage

		let messageDescription = "🛟 Saved Neighbor Info Module Config for \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)

		await MeshPackets.shared.upsertNeighborInfoModuleConfigPacket(config: config, nodeNum: toUser.num)

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

		await MeshPackets.shared.upsertPaxCounterModuleConfigPacket(config: config, nodeNum: toUser.num)

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

		await MeshPackets.shared.upsertRtttlConfigPacket(ringtone: ringtone, nodeNum: toUser.num)

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

		await MeshPackets.shared.upsertMqttModuleConfigPacket(config: config, nodeNum: toUser.num)

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

		await MeshPackets.shared.upsertRangeTestModuleConfigPacket(config: config, nodeNum: toUser.num)

		return Int64(meshPacket.id)
	}

	public func requestAudioModuleConfig(fromUser: UserEntity, toUser: UserEntity) async throws {

		var adminPacket = AdminMessage()
		adminPacket.getModuleConfigRequest = AdminMessage.ModuleConfigType.audioConfig
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("requestAudioModuleConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true

		meshPacket.decoded = dataMessage

		let messageDescription = "🛎️ Requested Audio Module Config using an admin key for node: \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
	}

	public func saveAudioModuleConfig(config: ModuleConfig.AudioConfig, fromUser: UserEntity, toUser: UserEntity) async throws -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.audio = config
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
			throw AccessoryError.ioFailed("saveAudioModuleConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage

		let messageDescription = "🛟 Saved Audio Module Config for \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)

		await MeshPackets.shared.upsertAudioModuleConfigPacket(config: config, nodeNum: toUser.num)

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

		await MeshPackets.shared.upsertSerialModuleConfigPacket(config: config, nodeNum: toUser.num)

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

	public func requestNeighborInfoModuleConfig(fromUser: UserEntity, toUser: UserEntity) async throws {
		var adminPacket = AdminMessage()
		adminPacket.getModuleConfigRequest = AdminMessage.ModuleConfigType.neighborinfoConfig
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("requestNeighborInfoModuleConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true

		meshPacket.decoded = dataMessage

		let messageDescription = "🛎️ Requested Neighbor Info Module Config using an admin key for node: \(toUser.longName ?? "Unknown".localized)"
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

	public func saveStatusMessageModuleConfig(config: ModuleConfig.StatusMessageConfig, fromUser: UserEntity, toUser: UserEntity) async throws -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.statusmessage = config
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
			throw AccessoryError.ioFailed("saveStatusMessageModuleConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage

		let messageDescription = "🛟 Saved Status Message Module Config for \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)

		await MeshPackets.shared.upsertStatusMessageModuleConfigPacket(config: config, nodeNum: toUser.num)

		return Int64(meshPacket.id)
	}

	public func requestStatusMessageModuleConfig(fromUser: UserEntity, toUser: UserEntity) async throws {

		var adminPacket = AdminMessage()
		adminPacket.getModuleConfigRequest = AdminMessage.ModuleConfigType.statusmessageConfig
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("requestStatusMessageModuleConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true

		meshPacket.decoded = dataMessage

		let messageDescription = "🛎️ Requested Status Message Module Config using an admin key for node: \(toUser.longName ?? "Unknown".localized)"
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

		await MeshPackets.shared.upsertStoreForwardModuleConfigPacket(config: config, nodeNum: toUser.num)

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

	public func sendRebootOta(fromUser: UserEntity, toUser: UserEntity, mode: OTAMode, otaHash: Data) async throws {
		var adminPacket = AdminMessage()
		var otaRequest = AdminMessage.OTAEvent()
		
		guard otaHash.count == 32 else {
			throw AccessoryError.ioFailed("sendRebootOta: Unable to serialize admin packet")
		}

		otaRequest.otaHash = otaHash
		otaRequest.rebootOtaMode = mode
		adminPacket.otaRequest = otaRequest
		
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

		try await MeshPackets.shared.upsertPositionConfigPacket(config: config, nodeNum: toUser.num)

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

		await MeshPackets.shared.upsertPowerConfigPacket(config: config, nodeNum: toUser.num)

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

		await MeshPackets.shared.upsertNetworkConfigPacket(config: config, nodeNum: toUser.num)

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

		await MeshPackets.shared.upsertSecurityConfigPacket(config: config, nodeNum: toUser.num)

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

	public func requestTAKModuleConfig(fromUser: UserEntity, toUser: UserEntity) async throws {

		var adminPacket = AdminMessage()
		adminPacket.getModuleConfigRequest = AdminMessage.ModuleConfigType.takConfig
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from = UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority = MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("requestTAKModuleConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true

		meshPacket.decoded = dataMessage

		let messageDescription = "🛎️ Requested TAK Module Config for node: \(toUser.longName ?? "unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
	}

	public func sendNodeDBReset(fromUser: UserEntity, toUser: UserEntity, preserveFavorites: Bool = true) async throws {
		var adminPacket = AdminMessage()
		// nodedbReset = true means preserve favorites; false means wipe all nodes.
		adminPacket.nodedbReset = preserveFavorites
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

		await MeshPackets.shared.upsertBluetoothConfigPacket(config: config, nodeNum: toUser.num, sessionPasskey: toUser.userNode?.sessionPasskey)

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

		await MeshPackets.shared.upsertTelemetryModuleConfigPacket(config: config, nodeNum: toUser.num)

		return Int64(meshPacket.id)
	}

	public func saveTAKModuleConfig(config: ModuleConfig.TAKConfig, fromUser: UserEntity, toUser: UserEntity) async throws -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.tak = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from = UInt32(fromUser.num)
		meshPacket.priority = MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("saveTAKModuleConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage

		let messageDescription = "🛟 Saved TAK Module Config for \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)

		await MeshPackets.shared.upsertTAKModuleConfigPacket(config: config, nodeNum: toUser.num)

		return Int64(meshPacket.id)
	}

	public func saveTrafficManagementModuleConfig(config: ModuleConfig.TrafficManagementConfig, fromUser: UserEntity, toUser: UserEntity) async throws -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.trafficManagement = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from = UInt32(fromUser.num)
		meshPacket.priority = MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("saveTrafficManagementModuleConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage

		let messageDescription = "🛟 Saved Traffic Management Module Config for \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)

		await MeshPackets.shared.upsertTrafficManagementModuleConfigPacket(config: config, nodeNum: toUser.num)

		return Int64(meshPacket.id)
	}

	public func requestTrafficManagementModuleConfig(fromUser: UserEntity, toUser: UserEntity) async throws {

		var adminPacket = AdminMessage()
		adminPacket.getModuleConfigRequest = AdminMessage.ModuleConfigType.trafficmanagementConfig
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from = UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority = MeshPacket.Priority.reliable
		meshPacket.wantAck = true

		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			throw AccessoryError.ioFailed("requestTrafficManagementModuleConfig: Unable to serialize admin packet")
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true

		meshPacket.decoded = dataMessage

		let messageDescription = "🛎️ Requested Traffic Management Module Config using an admin key for node: \(toUser.longName ?? "Unknown".localized)"
		try await sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription)
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

		await MeshPackets.shared.upsertDisplayConfigPacket(config: config, nodeNum: toUser.num, sessionPasskey: toUser.userNode?.sessionPasskey)

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

		await MeshPackets.shared.upsertDeviceConfigPacket(config: config, nodeNum: toUser.num, sessionPasskey: toUser.userNode?.sessionPasskey)

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

		await MeshPackets.shared.upsertLoRaConfigPacket(config: config, nodeNum: toUser.num, sessionPasskey: toUser.userNode?.sessionPasskey)

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

	public func exchangeUserInfo(fromUser: UserEntity, toUser: UserEntity) async throws -> Int64 {

		let userProto = fromUser.toProto()
		guard let userPayload: Data = try? userProto.serializedData() else {
			throw AccessoryError.ioFailed("exchangeUserInfo: Unable to serialize User protobuf")
		}

		var dataMessage = DataMessage()
		dataMessage.payload = userPayload
		dataMessage.portnum = PortNum.nodeinfoApp
		dataMessage.wantResponse = true

		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from = UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority = MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		meshPacket.channel = UInt32(toUser.userNode?.channel ?? 0)
		meshPacket.decoded = dataMessage

		var toRadio: ToRadio = ToRadio()
		toRadio.packet = meshPacket

		let logString = String.localizedStringWithFormat("Sent User Info Exchange request from %@ to %@".localized, fromUser.longName ?? "Unknown".localized, toUser.longName ?? "Unknown".localized)
		try await send(toRadio, debugDescription: logString)

		return Int64(meshPacket.id)
	}

	func sendLocalStatsRequest(destNum: Int64, wantResponse: Bool) async throws {
		guard let fromNodeNum = self.activeConnection?.device.num else {
			Logger.services.error("Error while sending local stats request.  No active device.")
			throw AccessoryError.ioFailed("No active device")
		}

		var telemetryPacket = Telemetry()
		telemetryPacket.localStats = LocalStats()

		var meshPacket = MeshPacket()
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.to = UInt32(destNum)
		meshPacket.from = UInt32(fromNodeNum)
		meshPacket.wantAck = true
		meshPacket.decoded.wantResponse = wantResponse

		var dataMessage = DataMessage()
		if let serializedData: Data = try? telemetryPacket.serializedData() {
			dataMessage.payload = serializedData
			dataMessage.portnum = PortNum.telemetryApp
			dataMessage.wantResponse = wantResponse
			meshPacket.decoded = dataMessage
		} else {
			throw AccessoryError.ioFailed("sendLocalStatsRequest: Unable to serialize telemetry packet")
		}

		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket

		let logString = String.localizedStringWithFormat("📊 Sent Local Stats Request from: %@ to: %@".localized, String(fromNodeNum), String(destNum))
		try await send(toRadio, debugDescription: logString)

		Logger.mesh.info("📊 \(logString, privacy: .public)")
	}
}
