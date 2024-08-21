import CoreData
import Foundation
import MeshtasticProtobufs
import OSLog
import RegexBuilder
import SwiftUI

extension BLEManager {
	func generateMessageMarkdown(message: String) -> String {
		guard !message.isEmoji() else {
			return message
		}

		let types: NSTextCheckingResult.CheckingType = [.address, .link, .phoneNumber]
		guard let detector = try? NSDataDetector(types: types.rawValue) else {
			return message
		}

		let matches = detector.matches(
			in: message,
			options: [],
			range: NSRange(location: 0, length: message.utf16.count)
		)
		var messageWithMarkdown = message

		if !matches.isEmpty {
			for match in matches {
				guard let range = Range(match.range, in: message) else {
					continue
				}

				if match.resultType == .address {
					let address = message[range]
					let urlEncodedAddress = address.addingPercentEncoding(withAllowedCharacters: .alphanumerics)

					messageWithMarkdown = messageWithMarkdown.replacingOccurrences(
						of: address,
						with: "[\(address)](http://maps.apple.com/?address=\(urlEncodedAddress ?? ""))"
					)
				}
				else if match.resultType == .phoneNumber {
					let phone = messageWithMarkdown[range]

					messageWithMarkdown = messageWithMarkdown.replacingOccurrences(
						of: phone,
						with: "[\(phone)](tel:\(phone))"
					)
				}
				else if match.resultType == .link {
					let start = match.range.lowerBound
					let stop = match.range.upperBound
					let url = message[start ..< stop]
					let absoluteUrl = match.url?.absoluteString ?? ""
					let markdownUrl = "[\(url)](\(absoluteUrl))"

					messageWithMarkdown = messageWithMarkdown.replacingOccurrences(
						of: url,
						with: markdownUrl
					)
				}
			}
		}

		return messageWithMarkdown
	}

	func localConfig(
		config: Config,
		context: NSManagedObjectContext,
		nodeNum: Int64,
		nodeLongName: String
	) {
		if config.payloadVariant == Config.OneOf_PayloadVariant.bluetooth(config.bluetooth) {
			upsertBluetoothConfigPacket(config: config.bluetooth, nodeNum: nodeNum, context: context)
		}
		else if config.payloadVariant == Config.OneOf_PayloadVariant.device(config.device) {
			upsertDeviceConfigPacket(config: config.device, nodeNum: nodeNum, context: context)
		}
		else if config.payloadVariant == Config.OneOf_PayloadVariant.display(config.display) {
			upsertDisplayConfigPacket(config: config.display, nodeNum: nodeNum, context: context)
		}
		else if config.payloadVariant == Config.OneOf_PayloadVariant.lora(config.lora) {
			upsertLoRaConfigPacket(config: config.lora, nodeNum: nodeNum, context: context)
		}
		else if config.payloadVariant == Config.OneOf_PayloadVariant.network(config.network) {
			upsertNetworkConfigPacket(config: config.network, nodeNum: nodeNum, context: context)
		}
		else if config.payloadVariant == Config.OneOf_PayloadVariant.position(config.position) {
			upsertPositionConfigPacket(config: config.position, nodeNum: nodeNum, context: context)
		}
		else if config.payloadVariant == Config.OneOf_PayloadVariant.power(config.power) {
			upsertPowerConfigPacket(config: config.power, nodeNum: nodeNum, context: context)
		}
	}

	func moduleConfig(
		config: ModuleConfig,
		context: NSManagedObjectContext,
		nodeNum: Int64,
		nodeLongName: String
	) {
		if config.payloadVariant == ModuleConfig.OneOf_PayloadVariant.ambientLighting(config.ambientLighting) {
			upsertAmbientLightingModuleConfigPacket(
				config: config.ambientLighting,
				nodeNum: nodeNum,
				context: context
			)
		}
		else if config.payloadVariant == ModuleConfig.OneOf_PayloadVariant.cannedMessage(config.cannedMessage) {
			upsertCannedMessagesModuleConfigPacket(
				config: config.cannedMessage,
				nodeNum: nodeNum,
				context: context
			)
		}
		else if config.payloadVariant == ModuleConfig.OneOf_PayloadVariant.detectionSensor(config.detectionSensor) {
			upsertDetectionSensorModuleConfigPacket(
				config: config.detectionSensor,
				nodeNum: nodeNum,
				context: context
			)
		}
		else if config.payloadVariant
					== ModuleConfig.OneOf_PayloadVariant.externalNotification(config.externalNotification)
		{
			upsertExternalNotificationModuleConfigPacket(
				config: config.externalNotification,
				nodeNum: nodeNum,
				context: context
			)
		}
		else if config.payloadVariant == ModuleConfig.OneOf_PayloadVariant.mqtt(config.mqtt) {
			upsertMqttModuleConfigPacket(
				config: config.mqtt,
				nodeNum: nodeNum,
				context: context
			)
		}
		else if config.payloadVariant == ModuleConfig.OneOf_PayloadVariant.paxcounter(config.paxcounter) {
			upsertPaxCounterModuleConfigPacket(
				config: config.paxcounter,
				nodeNum: nodeNum,
				context: context
			)
		}
		else if config.payloadVariant == ModuleConfig.OneOf_PayloadVariant.rangeTest(config.rangeTest) {
			upsertRangeTestModuleConfigPacket(
				config: config.rangeTest,
				nodeNum: nodeNum,
				context: context
			)
		}
		else if config.payloadVariant == ModuleConfig.OneOf_PayloadVariant.serial(config.serial) {
			upsertSerialModuleConfigPacket(
				config: config.serial,
				nodeNum: nodeNum,
				context: context
			)
		}
		else if config.payloadVariant == ModuleConfig.OneOf_PayloadVariant.telemetry(config.telemetry) {
			upsertTelemetryModuleConfigPacket(
				config: config.telemetry,
				nodeNum: nodeNum,
				context: context
			)
		}
		else if config.payloadVariant == ModuleConfig.OneOf_PayloadVariant.storeForward(config.storeForward) {
			upsertStoreForwardModuleConfigPacket(
				config: config.storeForward,
				nodeNum: nodeNum,
				context: context
			)
		}
	}

	func myInfoPacket(
		myInfo: MyNodeInfo,
		peripheralId: String,
		context: NSManagedObjectContext
	) -> MyInfoEntity? {
		let logString = String.localizedStringWithFormat("mesh.log.myinfo %@".localized, String(myInfo.myNodeNum))
		MeshLogger.log("ℹ️ \(logString)")

		let fetchMyInfoRequest = MyInfoEntity.fetchRequest()
		fetchMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", Int64(myInfo.myNodeNum))

		guard let fetchedMyInfo = try? context.fetch(fetchMyInfoRequest) else {
			return nil
		}

		if fetchedMyInfo.isEmpty {
			let myInfoEntity = MyInfoEntity(context: context)
			myInfoEntity.peripheralId = peripheralId
			myInfoEntity.myNodeNum = Int64(myInfo.myNodeNum)
			myInfoEntity.rebootCount = Int32(myInfo.rebootCount)

			do {
				try context.save()

				return myInfoEntity
			}
			catch {
				context.rollback()
			}
		} else {
			fetchedMyInfo[0].peripheralId = peripheralId
			fetchedMyInfo[0].myNodeNum = Int64(myInfo.myNodeNum)
			fetchedMyInfo[0].rebootCount = Int32(myInfo.rebootCount)

			do {
				try context.save()

				return fetchedMyInfo[0]
			}
			catch {
				context.rollback()
			}
		}

		return nil
	}

	func channelPacket(channel: Channel, fromNum: Int64, context: NSManagedObjectContext) {
		let request = MyInfoEntity.fetchRequest()
		request.predicate = NSPredicate(format: "myNodeNum == %lld", fromNum)

		guard
			channel.isInitialized,
			channel.hasSettings,
			channel.role != .disabled,
			let fetchedMyInfo = try? context.fetch(request),
			!fetchedMyInfo.isEmpty
		else {
			return
		}

		let newChannel = ChannelEntity(context: context)
		newChannel.id = Int32(channel.index)
		newChannel.index = Int32(channel.index)
		newChannel.uplinkEnabled = channel.settings.uplinkEnabled
		newChannel.downlinkEnabled = channel.settings.downlinkEnabled
		newChannel.name = channel.settings.name
		newChannel.role = Int32(channel.role.rawValue)
		newChannel.psk = channel.settings.psk

		if channel.settings.hasModuleSettings {
			newChannel.positionPrecision = Int32(
				truncatingIfNeeded: channel.settings.moduleSettings.positionPrecision
			)
			newChannel.mute = channel.settings.moduleSettings.isClientMuted
		}

		guard let mutableChannels = fetchedMyInfo[0].channels?.mutableCopy() as? NSMutableOrderedSet else {
			return
		}

		if let oldChannel = mutableChannels.first(where: {
			($0 as AnyObject).index == newChannel.index
		}) as? ChannelEntity {
			let index = mutableChannels.index(of: oldChannel as Any)
			mutableChannels.replaceObject(at: index, with: newChannel)
		} else {
			mutableChannels.add(newChannel)
		}

		fetchedMyInfo[0].channels = mutableChannels.copy() as? NSOrderedSet
		if newChannel.name?.lowercased() == "admin" {
			fetchedMyInfo[0].adminIndex = newChannel.index
		}

		context.refresh(newChannel, mergeChanges: true)
		do {
			try context.save()
		}
		catch {
			context.rollback()
		}
	}

	func deviceMetadataPacket(
		metadata: DeviceMetadata,
		fromNum: Int64,
		context: NSManagedObjectContext
	) {
		guard metadata.isInitialized else {
			return
		}

		let fetchedNodeRequest = NodeInfoEntity.fetchRequest()
		fetchedNodeRequest.predicate = NSPredicate(format: "num == %lld", fromNum)

		guard let fetchedNode = try? context.fetch(fetchedNodeRequest) else {
			return
		}

		let newMetadata = DeviceMetadataEntity(context: context)
		newMetadata.time = Date()
		newMetadata.deviceStateVersion = Int32(metadata.deviceStateVersion)
		newMetadata.canShutdown = metadata.canShutdown
		newMetadata.hasWifi = metadata.hasWifi_p
		newMetadata.hasBluetooth = metadata.hasBluetooth_p
		newMetadata.hasEthernet	= metadata.hasEthernet_p
		newMetadata.role = Int32(metadata.role.rawValue)
		newMetadata.positionFlags = Int32(metadata.positionFlags)

		// Swift does strings weird, this does work to get the version without the github hash
		let lastDotIndex = metadata.firmwareVersion.lastIndex(of: ".")
		var version = metadata.firmwareVersion[
			...(lastDotIndex ?? String.Index(utf16Offset: 6, in: metadata.firmwareVersion))
		]
		version = version.dropLast()
		newMetadata.firmwareVersion = String(version)

		if !fetchedNode.isEmpty {
			fetchedNode[0].metadata = newMetadata
		}
		else {
			if fromNum > 0 {
				let newNode = createNodeInfo(num: Int64(fromNum), context: context)
				newNode.metadata = newMetadata
			}
		}

		do {
			try context.save()
		}
		catch {
			context.rollback()
		}
	}

	func nodeInfoPacket(
		nodeInfo: NodeInfo,
		channel: UInt32,
		context: NSManagedObjectContext
	) -> NodeInfoEntity? {
		guard nodeInfo.num > 0 else {
			return nil
		}

		let infoRequest = NodeInfoEntity.fetchRequest()
		infoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeInfo.num))

		guard let fetchedNode = try? context.fetch(infoRequest) else {
			return nil
		}

		if fetchedNode.isEmpty, nodeInfo.num > 0 {
			let newNode = NodeInfoEntity(context: context)
			newNode.id = Int64(nodeInfo.num)
			newNode.num = Int64(nodeInfo.num)
			newNode.channel = Int32(nodeInfo.channel)
			newNode.favorite = nodeInfo.isFavorite
			newNode.hopsAway = Int32(nodeInfo.hopsAway)
			newNode.firstHeard = Date(timeIntervalSince1970: TimeInterval(Int64(nodeInfo.lastHeard)))
			newNode.lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(nodeInfo.lastHeard)))
			newNode.snr = nodeInfo.snr

			if nodeInfo.hasDeviceMetrics {
				let telemetry = TelemetryEntity(context: context)
				telemetry.batteryLevel = Int32(nodeInfo.deviceMetrics.batteryLevel)
				telemetry.voltage = nodeInfo.deviceMetrics.voltage
				telemetry.channelUtilization = nodeInfo.deviceMetrics.channelUtilization
				telemetry.airUtilTx = nodeInfo.deviceMetrics.airUtilTx

				var newTelemetries = [TelemetryEntity]()
				newTelemetries.append(telemetry)

				newNode.telemetries? = NSOrderedSet(array: newTelemetries)
			}

			if nodeInfo.hasUser {
				let newUser = UserEntity(context: context)
				newUser.userId = nodeInfo.user.id
				newUser.num = Int64(nodeInfo.num)
				newUser.longName = nodeInfo.user.longName
				newUser.shortName = nodeInfo.user.shortName
				newUser.hwModel = String(describing: nodeInfo.user.hwModel).uppercased()
				newUser.hwModelId = Int32(nodeInfo.user.hwModel.rawValue)
				newUser.isLicensed = nodeInfo.user.isLicensed
				newUser.role = Int32(nodeInfo.user.role.rawValue)

				Task {
					Api().loadDeviceHardwareData { hw in
						let dh = hw.first(where: {
							$0.hwModel == newUser.hwModelId
						})
						newUser.hwDisplayName = dh?.displayName
					}
				}

				newNode.user = newUser
			}
			else if nodeInfo.num > Constants.minimumNodeNum {
				let newUser = createUser(num: Int64(nodeInfo.num), context: context)
				newNode.user = newUser
			}

			if
				nodeInfo.position.longitudeI != 0,
				nodeInfo.position.latitudeI != 0,
				nodeInfo.position.latitudeI != 373346000,
				nodeInfo.position.longitudeI != -1220090000
			{
				let position = PositionEntity(context: context)
				position.latest = true
				position.seqNo = Int32(nodeInfo.position.seqNumber)
				position.latitudeI = nodeInfo.position.latitudeI
				position.longitudeI = nodeInfo.position.longitudeI
				position.altitude = nodeInfo.position.altitude
				position.satsInView = Int32(nodeInfo.position.satsInView)
				position.speed = Int32(nodeInfo.position.groundSpeed)
				position.heading = Int32(nodeInfo.position.groundTrack)
				position.time = Date(timeIntervalSince1970: TimeInterval(Int64(nodeInfo.position.time)))

				var newPostions = [PositionEntity]()
				newPostions.append(position)

				newNode.positions? = NSOrderedSet(array: newPostions)
			}

			// Look for a MyInfo
			let myInfoRequest = MyInfoEntity.fetchRequest()
			myInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", Int64(nodeInfo.num))

			if let fetchedMyInfo = try? context.fetch(myInfoRequest) {
				if !fetchedMyInfo.isEmpty {
					newNode.myInfo = fetchedMyInfo[0]
				}

				do {
					try context.save()
					Logger.data.info("💾 Saved a new Node Info For: \(String(nodeInfo.num))")
					return newNode
				}
				catch {
					context.rollback()
					let nsError = error as NSError
					Logger.data.error("Error Saving Core Data NodeInfoEntity: \(nsError)")
				}
			}
		}
		else if nodeInfo.num > 0 {
			fetchedNode[0].id = Int64(nodeInfo.num)
			fetchedNode[0].num = Int64(nodeInfo.num)
			fetchedNode[0].lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(nodeInfo.lastHeard)))
			fetchedNode[0].snr = nodeInfo.snr
			fetchedNode[0].channel = Int32(nodeInfo.channel)
			fetchedNode[0].favorite = nodeInfo.isFavorite
			fetchedNode[0].hopsAway = Int32(nodeInfo.hopsAway)

			if nodeInfo.hasUser {
				if fetchedNode[0].user == nil {
					fetchedNode[0].user = UserEntity(context: context)
				}
				fetchedNode[0].user!.userId = nodeInfo.user.id
				fetchedNode[0].user!.num = Int64(nodeInfo.num)
				fetchedNode[0].user!.numString = String(nodeInfo.num)
				fetchedNode[0].user!.longName = nodeInfo.user.longName
				fetchedNode[0].user!.shortName = nodeInfo.user.shortName
				fetchedNode[0].user!.isLicensed = nodeInfo.user.isLicensed
				fetchedNode[0].user!.role = Int32(nodeInfo.user.role.rawValue)
				fetchedNode[0].user!.hwModel = String(describing: nodeInfo.user.hwModel).uppercased()
				fetchedNode[0].user!.hwModelId = Int32(nodeInfo.user.hwModel.rawValue)

				Task {
					Api().loadDeviceHardwareData { hw in
						let dh = hw.first(where: {
							$0.hwModel == fetchedNode[0].user!.hwModelId
						})
						fetchedNode[0].user!.hwDisplayName = dh?.displayName
					}
				}
			}
			else {
				if fetchedNode[0].user == nil, nodeInfo.num > Constants.minimumNodeNum {
					let newUser = createUser(num: Int64(nodeInfo.num), context: context)
					fetchedNode[0].user = newUser
				}
			}

			if nodeInfo.hasDeviceMetrics {
				let newTelemetry = TelemetryEntity(context: context)
				newTelemetry.batteryLevel = Int32(nodeInfo.deviceMetrics.batteryLevel)
				newTelemetry.voltage = nodeInfo.deviceMetrics.voltage
				newTelemetry.channelUtilization = nodeInfo.deviceMetrics.channelUtilization
				newTelemetry.airUtilTx = nodeInfo.deviceMetrics.airUtilTx

				guard let mutableTelemetries = fetchedNode[0].telemetries!.mutableCopy() as? NSMutableOrderedSet else {
					return nil
				}

				fetchedNode[0].telemetries = mutableTelemetries.copy() as? NSOrderedSet
			}

			if nodeInfo.hasPosition {
				if
					nodeInfo.position.longitudeI != 0,
					nodeInfo.position.latitudeI != 0,
					nodeInfo.position.latitudeI != 373346000,
					nodeInfo.position.longitudeI != -1220090000
				{
					let position = PositionEntity(context: context)
					position.latitudeI = nodeInfo.position.latitudeI
					position.longitudeI = nodeInfo.position.longitudeI
					position.altitude = nodeInfo.position.altitude
					position.satsInView = Int32(nodeInfo.position.satsInView)
					position.time = Date(timeIntervalSince1970: TimeInterval(Int64(nodeInfo.position.time)))

					guard let mutablePositions = fetchedNode[0].positions!.mutableCopy() as? NSMutableOrderedSet else {
						return nil
					}

					fetchedNode[0].positions = mutablePositions.copy() as? NSOrderedSet
				}

			}

			// Look for a MyInfo
			let myInfoRequest = MyInfoEntity.fetchRequest()
			myInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", Int64(nodeInfo.num))

			if let fetchedMyInfo = try? context.fetch(myInfoRequest) {
				if !fetchedMyInfo.isEmpty {
					fetchedNode[0].myInfo = fetchedMyInfo[0]
				}

				do {
					try context.save()

					return fetchedNode[0]
				} catch {
					context.rollback()
				}
			}
		}

		return nil
	}

	func adminAppPacket(packet: MeshPacket, context: NSManagedObjectContext) {
		guard
			let message = try? AdminMessage(serializedData: packet.decoded.payload),
			let variant = message.payloadVariant
		else {
			return
		}

		switch variant {
		case AdminMessage.OneOf_PayloadVariant.getCannedMessageModuleMessagesResponse(
			message.getCannedMessageModuleMessagesResponse
		):
			let requst = NodeInfoEntity.fetchRequest()
			requst.predicate = NSPredicate(format: "num == %lld", Int64(packet.from))

			guard
				let fetchedNode = try? context.fetch(requst),
				!fetchedNode.isEmpty,
				let cmmc = try? CannedMessageModuleConfig(serializedData: packet.decoded.payload),
				!cmmc.messages.isEmpty
			else {
				break
			}

			let messages =  String(cmmc.textFormatString())
				.replacingOccurrences(of: "11: ", with: "")
				.replacingOccurrences(of: "\"", with: "")
				.trimmingCharacters(in: .whitespacesAndNewlines)
			fetchedNode[0].cannedMessageConfig?.messages = messages

			do {
				try context.save()
			}
			catch {
				context.rollback()
			}

		case AdminMessage.OneOf_PayloadVariant.getChannelResponse(message.getChannelResponse):
			channelPacket(
				channel: message.getChannelResponse,
				fromNum: Int64(packet.from),
				context: context
			)

		case AdminMessage.OneOf_PayloadVariant.getDeviceMetadataResponse(message.getDeviceMetadataResponse):
			deviceMetadataPacket(
				metadata: message.getDeviceMetadataResponse,
				fromNum: Int64(packet.from),
				context: context
			)

		case AdminMessage.OneOf_PayloadVariant.getConfigResponse(message.getConfigResponse):
			let config = message.getConfigResponse
			guard let variant = config.payloadVariant else {
				break
			}

			switch variant {
			case Config.OneOf_PayloadVariant.bluetooth(config.bluetooth):
				upsertBluetoothConfigPacket(
					config: config.bluetooth,
					nodeNum: Int64(packet.from),
					context: context
				)

			case Config.OneOf_PayloadVariant.device(config.device):
				upsertDeviceConfigPacket(
					config: config.device,
					nodeNum: Int64(packet.from),
					context: context
				)

			case Config.OneOf_PayloadVariant.display(config.display):
				upsertDisplayConfigPacket(
					config: config.display,
					nodeNum: Int64(packet.from),
					context: context
				)

			case Config.OneOf_PayloadVariant.lora(config.lora):
				upsertLoRaConfigPacket(
					config: config.lora,
					nodeNum: Int64(packet.from),
					context: context
				)

			case Config.OneOf_PayloadVariant.network(config.network):
				upsertNetworkConfigPacket(
					config: config.network,
					nodeNum: Int64(packet.from),
					context: context
				)

			case Config.OneOf_PayloadVariant.position(config.position):
				upsertPositionConfigPacket(
					config: config.position,
					nodeNum: Int64(packet.from),
					context: context
				)

			case Config.OneOf_PayloadVariant.power(config.power):
				upsertPowerConfigPacket(
					config: config.power,
					nodeNum: Int64(packet.from),
					context: context
				)

			default:
				break
			}

		case AdminMessage.OneOf_PayloadVariant.getModuleConfigResponse(message.getModuleConfigResponse):
			let moduleConfig = message.getModuleConfigResponse
			guard let variant = moduleConfig.payloadVariant else {
				break
			}

			switch variant {
			case ModuleConfig.OneOf_PayloadVariant.ambientLighting(moduleConfig.ambientLighting):
					upsertAmbientLightingModuleConfigPacket(
						config: moduleConfig.ambientLighting,
						nodeNum: Int64(packet.from),
						context: context
					)

			case ModuleConfig.OneOf_PayloadVariant.cannedMessage(moduleConfig.cannedMessage):
					upsertCannedMessagesModuleConfigPacket(
						config: moduleConfig.cannedMessage,
						nodeNum: Int64(packet.from),
						context: context
					)

			case ModuleConfig.OneOf_PayloadVariant.detectionSensor(moduleConfig.detectionSensor):
					upsertDetectionSensorModuleConfigPacket(
						config: moduleConfig.detectionSensor,
						nodeNum: Int64(packet.from),
						context: context
					)

			case ModuleConfig.OneOf_PayloadVariant.externalNotification(moduleConfig.externalNotification):
					upsertExternalNotificationModuleConfigPacket(
						config: moduleConfig.externalNotification,
						nodeNum: Int64(packet.from),
						context: context
					)

			case ModuleConfig.OneOf_PayloadVariant.mqtt(moduleConfig.mqtt):
					upsertMqttModuleConfigPacket(
						config: moduleConfig.mqtt,
						nodeNum: Int64(packet.from),
						context: context
					)

			case ModuleConfig.OneOf_PayloadVariant.rangeTest(moduleConfig.rangeTest):
					upsertRangeTestModuleConfigPacket(
						config: moduleConfig.rangeTest,
						nodeNum: Int64(packet.from),
						context: context
					)

			case ModuleConfig.OneOf_PayloadVariant.serial(moduleConfig.serial):
					upsertSerialModuleConfigPacket(
						config: moduleConfig.serial,
						nodeNum: Int64(packet.from),
						context: context
					)

			case ModuleConfig.OneOf_PayloadVariant.storeForward(moduleConfig.storeForward):
					upsertStoreForwardModuleConfigPacket(
						config: moduleConfig.storeForward,
						nodeNum: Int64(packet.from),
						context: context
					)

			case ModuleConfig.OneOf_PayloadVariant.telemetry(moduleConfig.telemetry):
					upsertTelemetryModuleConfigPacket(
						config: moduleConfig.telemetry,
						nodeNum: Int64(packet.from),
						context: context
					)

			default:
				break
			}

		case AdminMessage.OneOf_PayloadVariant.getRingtoneResponse(message.getRingtoneResponse):
			let ringtone = message.getRingtoneResponse
			upsertRtttlConfigPacket(ringtone: ringtone, nodeNum: Int64(packet.from), context: context)

		default:
			MeshLogger.log(
				"🕸️ MESH PACKET received Admin App UNHANDLED \((try? packet.decoded.jsonString()) ?? "JSON Decode Failure")"
			)
		}

		adminResponseAck(packet: packet, context: context)
	}

	func adminResponseAck(packet: MeshPacket, context: NSManagedObjectContext) {
		let request = MessageEntity.fetchRequest()
		request.predicate = NSPredicate(format: "messageId == %lld", packet.decoded.requestID)

		guard
			let fetchedMessage = try? context.fetch(request),
			!fetchedMessage.isEmpty
		else {
			return
		}

		fetchedMessage[0].ackTimestamp = Int32(Date().timeIntervalSince1970)
		fetchedMessage[0].ackError = Int32(RoutingError.none.rawValue)
		fetchedMessage[0].receivedACK = true
		fetchedMessage[0].realACK = true
		fetchedMessage[0].ackSNR = packet.rxSnr
		fetchedMessage[0].fromUser?.objectWillChange.send()

		do {
			try context.save()
		}
		catch {
			context.rollback()
		}
	}

	func paxCounterPacket(packet: MeshPacket, context: NSManagedObjectContext) {
		let requst = NodeInfoEntity.fetchRequest()
		requst.predicate = NSPredicate(format: "num == %lld", Int64(packet.from))

		guard
			let fetchedNode = try? context.fetch(requst),
			!fetchedNode.isEmpty,
			let mutablePax = fetchedNode[0].pax?.mutableCopy() as? NSMutableOrderedSet,
			let paxMessage = try? Paxcount(serializedData: packet.decoded.payload)
		else {
			return
		}

		let newPax = PaxCounterEntity(context: context)
		newPax.ble = Int32(truncatingIfNeeded: paxMessage.ble)
		newPax.wifi = Int32(truncatingIfNeeded: paxMessage.wifi)
		newPax.uptime = Int32(truncatingIfNeeded: paxMessage.uptime)
		newPax.time = Date()

		mutablePax.add(newPax)
		fetchedNode[0].pax = mutablePax

		try? context.save()
	}

	func routingPacket(packet: MeshPacket, connectedNodeNum: Int64, context: NSManagedObjectContext) {
		let request = MessageEntity.fetchRequest()
		request.predicate = NSPredicate(format: "messageId == %lld", Int64(packet.decoded.requestID))

		guard
			let fetchedMessage = try? context.fetch(request),
			!fetchedMessage.isEmpty,
			let routingMessage = try? Routing(serializedData: packet.decoded.payload)
		else {
			return
		}

		let routingError = RoutingError(rawValue: routingMessage.errorReason.rawValue)
		let routingErrorString = routingError?.display ?? "unknown".localized

		fetchedMessage[0].ackTimestamp = Int32(truncatingIfNeeded: packet.rxTime)
		fetchedMessage[0].ackSNR = packet.rxSnr
		fetchedMessage[0].ackError = Int32(routingMessage.errorReason.rawValue)

		if fetchedMessage[0].toUser != nil {
			if packet.to != packet.from {
				fetchedMessage[0].realACK = true
			}

			fetchedMessage[0].toUser!.objectWillChange.send()
		} else {
			let myInfoRequest = MyInfoEntity.fetchRequest()
			myInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", connectedNodeNum)

			if
				let fetchedMyInfo = try? context.fetch(myInfoRequest),
				!fetchedMyInfo.isEmpty,
				let channels = fetchedMyInfo[0].channels!.array as? [ChannelEntity]
			{
				for channel in channels where channel.index == packet.channel {
					channel.objectWillChange.send()
				}
			}
		}

		if routingMessage.errorReason == Routing.Error.none {
			fetchedMessage[0].receivedACK = true
		}

		do {
			try context.save()
		}
		catch {
			context.rollback()
		}
	}

	func telemetryPacket(packet: MeshPacket, connectedNode: Int64, context: NSManagedObjectContext) {
		let request = NodeInfoEntity.fetchRequest()
		request.predicate = NSPredicate(format: "num == %lld", Int64(packet.from))

		guard
			let fetchedNode = try? context.fetch(request),
			!fetchedNode.isEmpty,
			let telemetryMessage = try? Telemetry(serializedData: packet.decoded.payload)
		else {
			return
		}

		let telemetry = TelemetryEntity(context: context)
		telemetry.time = Date(
			timeIntervalSince1970: TimeInterval(Int64(truncatingIfNeeded: telemetryMessage.time))
		)
		telemetry.snr = packet.rxSnr
		telemetry.rssi = packet.rxRssi

		if telemetryMessage.variant == .deviceMetrics(telemetryMessage.deviceMetrics) {
			let metrics = telemetryMessage.deviceMetrics

			telemetry.metricsType = 0
			telemetry.airUtilTx = metrics.airUtilTx
			telemetry.channelUtilization = metrics.channelUtilization
			telemetry.batteryLevel = Int32(metrics.batteryLevel)
			telemetry.voltage = metrics.voltage
			telemetry.uptimeSeconds = Int32(metrics.uptimeSeconds)

			if Int64(packet.from) == connectedNode {
				scheduleLowBatteryNotification(telemetry: telemetry)
			}
		}
		else if telemetryMessage.variant == .environmentMetrics(telemetryMessage.environmentMetrics) {
			let metrics = telemetryMessage.environmentMetrics

			telemetry.metricsType = 1
			telemetry.barometricPressure = metrics.barometricPressure
			telemetry.current = metrics.current
			telemetry.iaq = Int32(truncatingIfNeeded: metrics.iaq)
			telemetry.gasResistance = metrics.gasResistance
			telemetry.relativeHumidity = metrics.relativeHumidity
			telemetry.temperature = metrics.temperature
			telemetry.current = metrics.current
			telemetry.voltage = metrics.voltage
			telemetry.weight = metrics.weight
			telemetry.windSpeed = metrics.windSpeed
			telemetry.windGust = metrics.windGust
			telemetry.windLull = metrics.windLull
			telemetry.windDirection = Int32(truncatingIfNeeded: metrics.windDirection)
		}
		else {
			return
		}

		guard let mutableTelemetries = fetchedNode[0].telemetries!.mutableCopy() as? NSMutableOrderedSet else {
			return
		}
		mutableTelemetries.add(telemetry)

		fetchedNode[0].lastHeard = Date(
			timeIntervalSince1970: TimeInterval(Int64(truncatingIfNeeded: packet.rxTime))
		)
		fetchedNode[0].telemetries = mutableTelemetries.copy() as? NSOrderedSet

		do {
			try context.save()
		}
		catch {
			context.rollback()
		}
	}

	func textMessageAppPacket(
		packet: MeshPacket,
		wantRangeTestPackets: Bool,
		connectedNode: Int64,
		storeForward: Bool = false,
		context: NSManagedObjectContext,
		appState: AppState
	) {
		let rangeRef = Reference(Int.self)
		let rangeTestRegex = Regex {
			"seq "
			TryCapture(as: rangeRef) {
				OneOrMore(.digit)
			} transform: { match in
				Int(match)
			}
		}

		var messageText = String(bytes: packet.decoded.payload, encoding: .utf8)

		if
			!wantRangeTestPackets,
			let messageText,
			messageText.contains(rangeTestRegex),
			messageText.starts(with: "seq ")
		{
			return
		}

		var storeForwardBroadcast = false
		if
			storeForward,
			let storeAndForwardMessage = try? StoreAndForward(serializedData: packet.decoded.payload)
		{
			messageText = String(bytes: storeAndForwardMessage.text, encoding: .utf8)
			if storeAndForwardMessage.rr == .routerTextBroadcast {
				storeForwardBroadcast = true
			}
		}

		let request = UserEntity.fetchRequest()
		request.predicate = NSPredicate(format: "num IN %@", [packet.to, packet.from])

		guard
			let messageText,
			!messageText.isEmpty,
			let fetchedUsers = try? context.fetch(request)
		else {
			return
		}


		let newMessage = MessageEntity(context: context)
		newMessage.messageId = Int64(packet.id)
		if packet.rxTime == 0 {
			newMessage.messageTimestamp = Int32(Date().timeIntervalSince1970)
		} else {
			newMessage.messageTimestamp = Int32(packet.rxTime)
		}
		newMessage.receivedACK = false
		newMessage.snr = packet.rxSnr
		newMessage.rssi = packet.rxRssi
		newMessage.isEmoji = packet.decoded.emoji == 1
		newMessage.channel = Int32(packet.channel)
		newMessage.portNum = Int32(packet.decoded.portnum.rawValue)

		if
			!UserDefaults.enableDetectionNotifications,
			packet.decoded.portnum == PortNum.detectionSensorApp
		{
			newMessage.read = true
		}

		if packet.decoded.replyID > 0 {
			newMessage.replyID = Int64(packet.decoded.replyID)
		}

		if
			!storeForwardBroadcast,
			let firstUserTo = fetchedUsers.first(where: {
				$0.num == packet.to
			}),
			packet.to != Constants.maximumNodeNum
		{
			newMessage.toUser = firstUserTo
		}

		if let firstUserFrom = fetchedUsers.first(where: {
			$0.num == packet.from
		}) {
			newMessage.fromUser = firstUserFrom
			if packet.rxTime > 0 {
				newMessage.fromUser?.userNode?.lastHeard = Date(
					timeIntervalSince1970: TimeInterval(Int64(packet.rxTime))
				)
			}
		}
		newMessage.messagePayload = messageText
		newMessage.messagePayloadMarkdown = generateMessageMarkdown(message: messageText)

		if
			packet.to != Constants.maximumNodeNum,
			newMessage.fromUser != nil
		{
			newMessage.fromUser?.lastMessage = Date.now
		}

		do {
			try context.save()

			guard
				UserDefaults.enableDetectionNotifications,
				packet.decoded.portnum != .detectionSensorApp,
				let fromUser = newMessage.fromUser
			else {
				return
			}

			if let toUser = newMessage.toUser {
				// Set Unread Message Indicators
				if packet.to == connectedNode {
					appState.unreadDirectMessages = toUser.unreadMessages
				}

				if !fromUser.mute {
					let manager = LocalNotificationManager()
					manager.notifications = [
						Notification(
							id: ("notification.id.\(newMessage.messageId)"),
							title: "\(fromUser.longName ?? "unknown".localized)",
							subtitle: "AKA \(fromUser.shortName ?? "?")",
							content: messageText,
							target: "messages",
							path: "meshtastic:///messages?userNum=\(newMessage.fromUser?.num ?? 0)&messageId=\(newMessage.messageId)"
						)
					]

					manager.schedule()
				}
			}
			else {
				let fetchMyInfoRequest = MyInfoEntity.fetchRequest()
				fetchMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", Int64(connectedNode))

				if
					let fetchedMyInfo = try? context.fetch(fetchMyInfoRequest),
					!fetchedMyInfo.isEmpty,
					let channels = fetchedMyInfo[0].channels?.array as? [ChannelEntity]
				{
					appState.unreadChannelMessages = fetchedMyInfo[0].unreadMessages

					for channel in channels {
						if channel.index == newMessage.channel {
							context.refresh(channel, mergeChanges: true)
						}

						if
							UserDefaults.channelMessageNotifications,
							channel.index == newMessage.channel,
							!channel.mute
						{
							let manager = LocalNotificationManager()
							manager.notifications = [
								Notification(
									id: ("notification.id.\(newMessage.messageId)"),
									title: "\(fromUser.longName ?? "unknown".localized)",
									subtitle: "AKA \(fromUser.shortName ?? "?")",
									content: messageText,
									target: "messages",
									path: "meshtastic:///messages?channelId=\(newMessage.channel)&messageId=\(newMessage.messageId)")
							]

							manager.schedule()
						}
					}
				}
			}
		} catch {
			context.rollback()
		}
	}

	func waypointPacket (packet: MeshPacket, context: NSManagedObjectContext) {
		let request = WaypointEntity.fetchRequest()
		request.predicate = NSPredicate(format: "id == %lld", Int64(packet.id))

		guard
			let waypointMessage = try? Waypoint(serializedData: packet.decoded.payload),
			let fetchedWaypoint = try? context.fetch(request)
		else {
			return
		}

		if fetchedWaypoint.isEmpty {
			let waypoint = WaypointEntity(context: context)

			waypoint.id = Int64(packet.id)
			waypoint.name = waypointMessage.name
			waypoint.longDescription = waypointMessage.description_p
			waypoint.latitudeI = waypointMessage.latitudeI
			waypoint.longitudeI = waypointMessage.longitudeI
			waypoint.icon = Int64(waypointMessage.icon)
			waypoint.locked = Int64(waypointMessage.lockedTo)
			waypoint.created = Date.now
			if waypointMessage.expire >= 1 {
				waypoint.expire = Date(
					timeIntervalSince1970: TimeInterval(Int64(waypointMessage.expire))
				)
			} else {
				waypoint.expire = nil
			}

			do {
				try context.save()

				let manager = LocalNotificationManager()
				let icon = String(UnicodeScalar(Int(waypoint.icon)) ?? "📍")
				let latitude = Double(waypoint.latitudeI) / 1e7
				let longitude = Double(waypoint.longitudeI) / 1e7

				manager.notifications = [
					Notification(
						id: ("notification.id.\(waypoint.id)"),
						title: "New Waypoint Received",
						subtitle: "\(icon) \(waypoint.name ?? "Dropped Pin")",
						content: "\(waypoint.longDescription ?? "\(latitude), \(longitude)")",
						target: "map",
						path: "meshtastic:///map?waypointid=\(waypoint.id)"
					)
				]

				manager.schedule()
			} catch {
				context.rollback()
			}
		} else {
			fetchedWaypoint[0].id = Int64(packet.id)
			fetchedWaypoint[0].name = waypointMessage.name
			fetchedWaypoint[0].longDescription = waypointMessage.description_p
			fetchedWaypoint[0].latitudeI = waypointMessage.latitudeI
			fetchedWaypoint[0].longitudeI = waypointMessage.longitudeI
			fetchedWaypoint[0].icon = Int64(waypointMessage.icon)
			fetchedWaypoint[0].locked = Int64(waypointMessage.lockedTo)
			fetchedWaypoint[0].lastUpdated = Date.now
			if waypointMessage.expire >= 1 {
				fetchedWaypoint[0].expire = Date(
					timeIntervalSince1970: TimeInterval(Int64(waypointMessage.expire))
				)
			} else {
				fetchedWaypoint[0].expire = nil
			}

			do {
				try context.save()
			} catch {
				context.rollback()
			}
		}
	}

	private func scheduleLowBatteryNotification(telemetry: TelemetryEntity) {
		guard
			UserDefaults.lowBatteryNotifications,
			telemetry.batteryLevel > 0,
			telemetry.batteryLevel < 4
		else {
			return
		}

		let shortName = telemetry.nodeTelemetry?.user?.shortName ?? "unknown name"
		let path: String?
		if let num = telemetry.nodeTelemetry?.num {
			path = "meshtastic:///nodes?nodenum=\(num)"
		}
		else {
			path = nil
		}

		let manager = LocalNotificationManager()
		manager.notifications = [
			Notification(
				id: "notification.id.\(UUID().uuidString)",
				title: "Node Battery is Low",
				subtitle: "Node: " + shortName,
				content: "Time to charge your node. There is \(telemetry.batteryLevel)% battery remaining.",
				target: "nodes",
				path: path
			)
		]

		manager.schedule()
	}
}
