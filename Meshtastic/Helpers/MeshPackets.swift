//
//  MeshPackets.swift
//  Meshtastic Apple
//
//  Created by Garth Vander Houwen on 5/27/22.
//

import Foundation
import CoreData
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif

func generateMessageMarkdown (message: String) -> String {
	let types: NSTextCheckingResult.CheckingType = [.address, .link, .phoneNumber]
	let detector = try! NSDataDetector(types: types.rawValue)
	let matches = detector.matches(in: message, options: [], range: NSRange(location: 0, length: message.utf16.count))
	var messageWithMarkdown = message
	if matches.count > 0 {
		for match in matches {
			guard let range = Range(match.range, in: message) else { continue }
			if match.resultType == .address {
				let address = message[range]
				let urlEncodedAddress = address.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
				messageWithMarkdown = messageWithMarkdown.replacingOccurrences(of: address, with: "[\(address)](http://maps.apple.com/?address=\(urlEncodedAddress ?? ""))")
			} else if match.resultType == .phoneNumber {
				let phone = messageWithMarkdown[range]
				messageWithMarkdown = messageWithMarkdown.replacingOccurrences(of: phone, with: "[\(phone)](tel:\(phone))")
			} else if match.resultType == .link {
				let url = messageWithMarkdown[range]
				let absoluteUrl = match.url?.absoluteString ?? ""
				messageWithMarkdown = messageWithMarkdown.replacingOccurrences(of: url, with: "[\(String(match.url?.host ?? "Link"))\(String(match.url?.path ?? ""))](\(absoluteUrl))")
			}
		}
	}
	return messageWithMarkdown
}

func localConfig (config: Config, context: NSManagedObjectContext, nodeNum: Int64, nodeLongName: String) {
	// We don't care about any of the Power settings, config is available for everything else
	if config.payloadVariant == Config.OneOf_PayloadVariant.bluetooth(config.bluetooth) {
		upsertBluetoothConfigPacket(config: config.bluetooth, nodeNum: nodeNum, context: context)
	} else if config.payloadVariant == Config.OneOf_PayloadVariant.device(config.device) {
		upsertDeviceConfigPacket(config: config.device, nodeNum: nodeNum, context: context)
	} else if config.payloadVariant == Config.OneOf_PayloadVariant.display(config.display) {
		upsertDisplayConfigPacket(config: config.display, nodeNum: nodeNum, context: context)
	} else if config.payloadVariant == Config.OneOf_PayloadVariant.lora(config.lora) {
		upsertLoRaConfigPacket(config: config.lora, nodeNum: nodeNum, context: context)
	} else if config.payloadVariant == Config.OneOf_PayloadVariant.network(config.network) {
		upsertNetworkConfigPacket(config: config.network, nodeNum: nodeNum, context: context)
	} else if config.payloadVariant == Config.OneOf_PayloadVariant.position(config.position) {
		upsertPositionConfigPacket(config: config.position, nodeNum: nodeNum, context: context)
	}
}

func moduleConfig (config: ModuleConfig, context: NSManagedObjectContext, nodeNum: Int64, nodeLongName: String) {

	if config.payloadVariant == ModuleConfig.OneOf_PayloadVariant.cannedMessage(config.cannedMessage) {
		upsertCannedMessagesModuleConfigPacket(config: config.cannedMessage, nodeNum: nodeNum, context: context)
	} else if config.payloadVariant == ModuleConfig.OneOf_PayloadVariant.detectionSensor(config.detectionSensor) {
		upsertDetectionSensorModuleConfigPacket(config: config.detectionSensor, nodeNum: nodeNum, context: context)
	} else if config.payloadVariant == ModuleConfig.OneOf_PayloadVariant.externalNotification(config.externalNotification) {
		upsertExternalNotificationModuleConfigPacket(config: config.externalNotification, nodeNum: nodeNum, context: context)
	} else if config.payloadVariant == ModuleConfig.OneOf_PayloadVariant.mqtt(config.mqtt) {
		upsertMqttModuleConfigPacket(config: config.mqtt, nodeNum: nodeNum, context: context)
	} else if config.payloadVariant == ModuleConfig.OneOf_PayloadVariant.rangeTest(config.rangeTest) {
		upsertRangeTestModuleConfigPacket(config: config.rangeTest, nodeNum: nodeNum, context: context)
	} else if config.payloadVariant == ModuleConfig.OneOf_PayloadVariant.serial(config.serial) {
		upsertSerialModuleConfigPacket(config: config.serial, nodeNum: nodeNum, context: context)
	} else if config.payloadVariant == ModuleConfig.OneOf_PayloadVariant.telemetry(config.telemetry) {
		upsertTelemetryModuleConfigPacket(config: config.telemetry, nodeNum: nodeNum, context: context)
	} else if config.payloadVariant == ModuleConfig.OneOf_PayloadVariant.storeForward(config.storeForward) {
		upsertStoreForwardModuleConfigPacket(config: config.storeForward, nodeNum: nodeNum, context: context)
	}
}

func myInfoPacket (myInfo: MyNodeInfo, peripheralId: String, context: NSManagedObjectContext) -> MyInfoEntity? {

	let logString = String.localizedStringWithFormat("mesh.log.myinfo %@".localized, String(myInfo.myNodeNum))
	MeshLogger.log("ℹ️ \(logString)")

	let fetchMyInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "MyInfoEntity")
	fetchMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", Int64(myInfo.myNodeNum))

	do {
		guard let fetchedMyInfo = try context.fetch(fetchMyInfoRequest) as? [MyInfoEntity] else {
			return nil
		}
		// Not Found Insert
		if fetchedMyInfo.isEmpty {

			let myInfoEntity = MyInfoEntity(context: context)
			myInfoEntity.peripheralId = peripheralId
			myInfoEntity.myNodeNum = Int64(myInfo.myNodeNum)
			myInfoEntity.rebootCount = Int32(myInfo.rebootCount)
			do {
				try context.save()
				print("💾 Saved a new myInfo for node number: \(String(myInfo.myNodeNum))")
				return myInfoEntity
			} catch {
				context.rollback()
				let nsError = error as NSError
				print("💥 Error Inserting New Core Data MyInfoEntity: \(nsError)")
			}
		} else {

			fetchedMyInfo[0].peripheralId = peripheralId
			fetchedMyInfo[0].myNodeNum = Int64(myInfo.myNodeNum)
			fetchedMyInfo[0].rebootCount = Int32(myInfo.rebootCount)

			do {
				try context.save()
				print("💾 Updated myInfo for node number: \(String(myInfo.myNodeNum))")
				return fetchedMyInfo[0]
			} catch {
				context.rollback()
				let nsError = error as NSError
				print("💥 Error Updating Core Data MyInfoEntity: \(nsError)")
			}
		}
	} catch {
		print("💥 Fetch MyInfo Error")
	}
	return nil
}

func channelPacket (channel: Channel, fromNum: Int64, context: NSManagedObjectContext) {

	if channel.isInitialized && channel.hasSettings && channel.role != Channel.Role.disabled {

		let logString = String.localizedStringWithFormat("mesh.log.channel.received %d %@".localized, channel.index, String(fromNum))
		MeshLogger.log("🎛️ \(logString)")

		let fetchedMyInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "MyInfoEntity")
		fetchedMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", fromNum)

		do {
			guard let fetchedMyInfo = try context.fetch(fetchedMyInfoRequest) as? [MyInfoEntity] else {
				return
			}
			if fetchedMyInfo.count == 1 {
				let newChannel = ChannelEntity(context: context)
				newChannel.id = Int32(channel.index)
				newChannel.index = Int32(channel.index)
				newChannel.uplinkEnabled = channel.settings.uplinkEnabled
				newChannel.downlinkEnabled = channel.settings.downlinkEnabled
				newChannel.name = channel.settings.name
				newChannel.role = Int32(channel.role.rawValue)
				newChannel.psk = channel.settings.psk
				guard let mutableChannels = fetchedMyInfo[0].channels!.mutableCopy() as? NSMutableOrderedSet else {
					return
				}
				if mutableChannels.contains(newChannel) {
					mutableChannels.replaceObject(at: Int(newChannel.index), with: newChannel)
				} else {
					mutableChannels.add(newChannel)
				}
				fetchedMyInfo[0].channels = mutableChannels.copy() as? NSOrderedSet
				if newChannel.name?.lowercased() == "admin" {
					fetchedMyInfo[0].adminIndex = newChannel.index
				}
				do {
					try context.save()
				} catch {
					print("Failed to save channel")
				}
				print("💾 Updated MyInfo channel \(channel.index) from Channel App Packet For: \(fetchedMyInfo[0].myNodeNum)")
			} else if channel.role.rawValue > 0 {
				print("💥 Trying to save a channel to a MyInfo that does not exist: \(fromNum)")
			}
		} catch {
			context.rollback()
			let nsError = error as NSError
			print("💥 Error Saving MyInfo Channel from ADMIN_APP \(nsError)")
		}
	}
}

func deviceMetadataPacket (metadata: DeviceMetadata, fromNum: Int64, context: NSManagedObjectContext) {

	if metadata.isInitialized {
		let logString = String.localizedStringWithFormat("mesh.log.device.metadata.received %@".localized, String(fromNum))
		MeshLogger.log("🏷️ \(logString)")

		let fetchedNodeRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
		fetchedNodeRequest.predicate = NSPredicate(format: "num == %lld", fromNum)

		do {
			guard let fetchedNode = try context.fetch(fetchedNodeRequest) as? [NodeInfoEntity] else {
				return
			}
			if fetchedNode.count > 0 {
				let newMetadata = DeviceMetadataEntity(context: context)
				newMetadata.firmwareVersion = metadata.firmwareVersion
				newMetadata.deviceStateVersion = Int32(metadata.deviceStateVersion)
				newMetadata.canShutdown = metadata.canShutdown
				newMetadata.hasWifi = metadata.hasWifi_p
				newMetadata.hasBluetooth = metadata.hasBluetooth_p
				newMetadata.hasEthernet	= metadata.hasEthernet_p
				newMetadata.role = Int32(metadata.role.rawValue)
				newMetadata.positionFlags = Int32(metadata.positionFlags)
				// Swift does strings weird, this does work to get the version without the github hash
				let lastDotIndex = metadata.firmwareVersion.lastIndex(of: ".")
				var version = metadata.firmwareVersion[...(lastDotIndex ?? String.Index(utf16Offset: 6, in: metadata.firmwareVersion))]
				version = version.dropLast()
				newMetadata.firmwareVersion = String(version)
				fetchedNode[0].metadata = newMetadata

				do {
					try context.save()
				} catch {
					print("Failed to save device metadata")
				}
				print("💾 Updated Device Metadata from Admin App Packet For: \(fromNum)")
			}
		} catch {
			context.rollback()
			let nsError = error as NSError
			print("💥 Error Saving MyInfo Channel from ADMIN_APP \(nsError)")
		}
	}
}

func nodeInfoPacket (nodeInfo: NodeInfo, channel: UInt32, context: NSManagedObjectContext) -> NodeInfoEntity? {

	let logString = String.localizedStringWithFormat("mesh.log.nodeinfo.received %@".localized, String(nodeInfo.num))
	MeshLogger.log("📟 \(logString)")

	guard nodeInfo.num > 0 else { return nil }

	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeInfo.num))

	do {
		guard let fetchedNode = try context.fetch(fetchNodeInfoRequest) as? [NodeInfoEntity] else {
			return nil
		}
		// Not Found Insert
		if fetchedNode.isEmpty {

			let newNode = NodeInfoEntity(context: context)
			newNode.id = Int64(nodeInfo.num)
			newNode.num = Int64(nodeInfo.num)
			newNode.channel = Int32(nodeInfo.channel)

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

			newNode.lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(nodeInfo.lastHeard)))
			newNode.snr = nodeInfo.snr
			if nodeInfo.hasUser {
				let newUser = UserEntity(context: context)
				newUser.userId = nodeInfo.user.id
				newUser.num = Int64(nodeInfo.num)
				newUser.longName = nodeInfo.user.longName
				newUser.shortName = nodeInfo.user.shortName
				newUser.hwModel = String(describing: nodeInfo.user.hwModel).uppercased()
				newNode.user = newUser
			}

			if nodeInfo.position.longitudeI > 0 || nodeInfo.position.latitudeI > 0 && (nodeInfo.position.latitudeI != 373346000 && nodeInfo.position.longitudeI != -1220090000) {
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
			let fetchMyInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "MyInfoEntity")
			fetchMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", Int64(nodeInfo.num))

			do {
				guard let fetchedMyInfo = try context.fetch(fetchMyInfoRequest) as? [MyInfoEntity] else {
					return nil
				}
				if fetchedMyInfo.count > 0 {
					newNode.myInfo = fetchedMyInfo[0]
				}
				do {
					try context.save()
					print(" Saved a new Node Info For: (String(nodeInfo.num))")

					return newNode
				} catch {
					context.rollback()
					let nsError = error as NSError
					print("💥 Error Saving Core Data NodeInfoEntity: \(nsError)")
				}
			} catch {
				print("💥 Fetch MyInfo Error")
			}
		} else if nodeInfo.hasUser && nodeInfo.num > 0 {

			fetchedNode[0].id = Int64(nodeInfo.num)
			fetchedNode[0].num = Int64(nodeInfo.num)
			fetchedNode[0].lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(nodeInfo.lastHeard)))
			fetchedNode[0].snr = nodeInfo.snr
			fetchedNode[0].channel = Int32(nodeInfo.channel)

			if nodeInfo.hasUser {
				if (fetchedNode[0].user == nil) {
					fetchedNode[0].user = UserEntity(context: context)
				}
				fetchedNode[0].user!.userId = nodeInfo.user.id
				fetchedNode[0].user!.num = Int64(nodeInfo.num)
				fetchedNode[0].user!.longName = nodeInfo.user.longName
				fetchedNode[0].user!.shortName = nodeInfo.user.shortName
				fetchedNode[0].user!.hwModel = String(describing: nodeInfo.user.hwModel).uppercased()
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

				if nodeInfo.position.longitudeI > 0 || nodeInfo.position.latitudeI > 0 && (nodeInfo.position.latitudeI != 373346000 && nodeInfo.position.longitudeI != -1220090000) {

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
			let fetchMyInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "MyInfoEntity")
			fetchMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", Int64(nodeInfo.num))

			do {
				guard let fetchedMyInfo = try context.fetch(fetchMyInfoRequest) as? [MyInfoEntity] else {
					return nil
				}
				if fetchedMyInfo.count > 0 {
					fetchedNode[0].myInfo = fetchedMyInfo[0]
				}
				do {
					try context.save()
					print("💾 NodeInfo saved for \(nodeInfo.num)")
					return fetchedNode[0]
				} catch {
					context.rollback()
					let nsError = error as NSError
					print("💥 Error Saving Core Data NodeInfoEntity: \(nsError)")
				}
			} catch {
				print("💥 Fetch MyInfo Error")
			}
		}
	} catch {
		print("💥 Fetch NodeInfoEntity Error")
	}
	return nil
}

func adminAppPacket (packet: MeshPacket, context: NSManagedObjectContext) {

	if let adminMessage = try? AdminMessage(serializedData: packet.decoded.payload) {

		if adminMessage.payloadVariant == AdminMessage.OneOf_PayloadVariant.getCannedMessageModuleMessagesResponse(adminMessage.getCannedMessageModuleMessagesResponse) {

			if let cmmc = try? CannedMessageModuleConfig(serializedData: packet.decoded.payload) {

				if !cmmc.messages.isEmpty {

					let logString = String.localizedStringWithFormat("mesh.log.cannedmessages.messages.received %@".localized, String(packet.from))
					MeshLogger.log("🥫 \(logString)")

					let fetchNodeRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
					fetchNodeRequest.predicate = NSPredicate(format: "num == %lld", Int64(packet.from))

					do {
						guard let fetchedNode = try context.fetch(fetchNodeRequest) as? [NodeInfoEntity] else {
							return
						}
						if fetchedNode.count == 1 {
							let messages =  String(cmmc.textFormatString())
								.replacingOccurrences(of: "11: ", with: "")
								.replacingOccurrences(of: "\"", with: "")
								.trimmingCharacters(in: .whitespacesAndNewlines)
							fetchedNode[0].cannedMessageConfig?.messages = messages
							do {
								try context.save()
								print("💾 Updated Canned Messages Messages For: \(fetchedNode[0].num)")
							} catch {
								context.rollback()
								let nsError = error as NSError
								print("💥 Error Saving NodeInfoEntity from POSITION_APP \(nsError)")
							}
						}
					} catch {
						print("💥 Error Deserializing ADMIN_APP packet.")
					}
				}
			}
		} else if adminMessage.payloadVariant == AdminMessage.OneOf_PayloadVariant.getChannelResponse(adminMessage.getChannelResponse) {
			channelPacket(channel: adminMessage.getChannelResponse, fromNum: Int64(packet.from), context: context)
		} else if adminMessage.payloadVariant == AdminMessage.OneOf_PayloadVariant.getDeviceMetadataResponse(adminMessage.getDeviceMetadataResponse) {
			deviceMetadataPacket(metadata: adminMessage.getDeviceMetadataResponse, fromNum: Int64(packet.from), context: context)
		} else if adminMessage.payloadVariant == AdminMessage.OneOf_PayloadVariant.getConfigResponse(adminMessage.getConfigResponse) {
			let config = adminMessage.getConfigResponse
			if config.payloadVariant == Config.OneOf_PayloadVariant.bluetooth(config.bluetooth) {
				upsertBluetoothConfigPacket(config: config.bluetooth, nodeNum: Int64(packet.from), context: context)
			} else if config.payloadVariant == Config.OneOf_PayloadVariant.device(config.device) {
				upsertDeviceConfigPacket(config: config.device, nodeNum: Int64(packet.from), context: context)
			} else if config.payloadVariant == Config.OneOf_PayloadVariant.display(config.display) {
				upsertDisplayConfigPacket(config: config.display, nodeNum: Int64(packet.from), context: context)
			} else if config.payloadVariant == Config.OneOf_PayloadVariant.lora(config.lora) {
				upsertLoRaConfigPacket(config: config.lora, nodeNum: Int64(packet.from), context: context)
			} else if config.payloadVariant == Config.OneOf_PayloadVariant.network(config.network) {
				upsertNetworkConfigPacket(config: config.network, nodeNum: Int64(packet.from), context: context)
			} else if config.payloadVariant == Config.OneOf_PayloadVariant.position(config.position) {
				upsertPositionConfigPacket(config: config.position, nodeNum: Int64(packet.from), context: context)
			}
		} else if adminMessage.payloadVariant == AdminMessage.OneOf_PayloadVariant.getModuleConfigResponse(adminMessage.getModuleConfigResponse) {
			let moduleConfig = adminMessage.getModuleConfigResponse
			if moduleConfig.payloadVariant == ModuleConfig.OneOf_PayloadVariant.cannedMessage(moduleConfig.cannedMessage) {
				upsertCannedMessagesModuleConfigPacket(config: moduleConfig.cannedMessage, nodeNum: Int64(packet.from), context: context)
			} else if moduleConfig.payloadVariant == ModuleConfig.OneOf_PayloadVariant.detectionSensor(moduleConfig.detectionSensor) {
				upsertDetectionSensorModuleConfigPacket(config: moduleConfig.detectionSensor, nodeNum: Int64(packet.from), context: context)
			} else if moduleConfig.payloadVariant == ModuleConfig.OneOf_PayloadVariant.externalNotification(moduleConfig.externalNotification) {
				upsertExternalNotificationModuleConfigPacket(config: moduleConfig.externalNotification, nodeNum: Int64(packet.from), context: context)
			} else if moduleConfig.payloadVariant == ModuleConfig.OneOf_PayloadVariant.mqtt(moduleConfig.mqtt) {
				upsertMqttModuleConfigPacket(config: moduleConfig.mqtt, nodeNum: Int64(packet.from), context: context)
			} else if moduleConfig.payloadVariant == ModuleConfig.OneOf_PayloadVariant.rangeTest(moduleConfig.rangeTest) {
				upsertRangeTestModuleConfigPacket(config: moduleConfig.rangeTest, nodeNum: Int64(packet.from), context: context)
			} else if moduleConfig.payloadVariant == ModuleConfig.OneOf_PayloadVariant.serial(moduleConfig.serial) {
				upsertSerialModuleConfigPacket(config: moduleConfig.serial, nodeNum: Int64(packet.from), context: context)
			} else if moduleConfig.payloadVariant == ModuleConfig.OneOf_PayloadVariant.storeForward(moduleConfig.storeForward) {
				upsertStoreForwardModuleConfigPacket(config: moduleConfig.storeForward, nodeNum: Int64(packet.from), context: context)
			} else if moduleConfig.payloadVariant == ModuleConfig.OneOf_PayloadVariant.telemetry(moduleConfig.telemetry) {
				upsertTelemetryModuleConfigPacket(config: moduleConfig.telemetry, nodeNum: Int64(packet.from), context: context)
			}
		} else if adminMessage.payloadVariant == AdminMessage.OneOf_PayloadVariant.getRingtoneResponse(adminMessage.getRingtoneResponse) {
			let ringtone = adminMessage.getRingtoneResponse
			upsertRtttlConfigPacket(ringtone: ringtone, nodeNum: Int64(packet.from), context: context)
		} else {
			MeshLogger.log("🕸️ MESH PACKET received for Admin App \(try! packet.decoded.jsonString())")
		}
		// Save an ack for the admin message log for each admin message response received as we stopped sending acks if there is also a response to reduce airtime.
		adminResponseAck(packet: packet, context: context)
	}
}

func adminResponseAck (packet: MeshPacket, context: NSManagedObjectContext) {

	let fetchedAdminMessageRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "MessageEntity")
	fetchedAdminMessageRequest.predicate = NSPredicate(format: "messageId == %lld", packet.decoded.requestID)
	do {
		guard let fetchedMessage = try context.fetch(fetchedAdminMessageRequest) as? [MessageEntity] else {
			return
		}
		if fetchedMessage.count > 0 {
			fetchedMessage[0].ackTimestamp = Int32(Date().timeIntervalSince1970)
			fetchedMessage[0].ackError = Int32(RoutingError.none.rawValue)
			fetchedMessage[0].receivedACK = true
			fetchedMessage[0].realACK = true
			fetchedMessage[0].ackSNR = packet.rxSnr
			if fetchedMessage[0].fromUser != nil {
				fetchedMessage[0].fromUser?.objectWillChange.send()
			}
			do {
				try context.save()
			} catch {
				print("Failed to save admin message response as an ack")
			}
		}
	} catch {
		print("Failed to fetch admin message by requestID")
	}
}

func routingPacket (packet: MeshPacket, connectedNodeNum: Int64, context: NSManagedObjectContext) {

	if let routingMessage = try? Routing(serializedData: packet.decoded.payload) {

		let routingError = RoutingError(rawValue: routingMessage.errorReason.rawValue)

		let routingErrorString = routingError?.display ?? "unknown".localized
		let logString = String.localizedStringWithFormat("mesh.log.routing.message %@ %@".localized, String(packet.decoded.requestID), routingErrorString)
		MeshLogger.log("🕸️ \(logString)")

		let fetchMessageRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "MessageEntity")
		fetchMessageRequest.predicate = NSPredicate(format: "messageId == %lld", Int64(packet.decoded.requestID))

		do {
			let fetchedMessage = try context.fetch(fetchMessageRequest) as? [MessageEntity]
			if fetchedMessage?.count ?? 0 > 0 {

				if fetchedMessage![0].toUser != nil {
					// Real ACK from DM Recipient
					if packet.to != packet.from {
						fetchedMessage![0].realACK = true
					}
				}
				fetchedMessage![0].ackError = Int32(routingMessage.errorReason.rawValue)

				if routingMessage.errorReason == Routing.Error.none {

					fetchedMessage![0].receivedACK = true
				}
				fetchedMessage![0].ackSNR = packet.rxSnr
				fetchedMessage![0].ackTimestamp = Int32(packet.rxTime)

				if fetchedMessage![0].toUser != nil {
					fetchedMessage![0].toUser?.objectWillChange.send()
				} else {
					let fetchMyInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "MyInfoEntity")
					fetchMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", connectedNodeNum)
					do {
						let fetchedMyInfo = try context.fetch(fetchMyInfoRequest) as? [MyInfoEntity]
						if fetchedMyInfo?.count ?? 0 > 0 {

							for ch in fetchedMyInfo![0].channels!.array as? [ChannelEntity] ?? [] {

								if ch.index == packet.channel {
									ch.objectWillChange.send()
								}
							}
						}
					} catch {

					}
				}

			} else {
				return
			}
			try context.save()
			print("💾 ACK Saved for Message: \(packet.decoded.requestID)")
		} catch {
			context.rollback()
			let nsError = error as NSError
			print("💥 Error Saving ACK for message: \(packet.id) Error: \(nsError)")
		}
	}
}

func storeAndForwardPacket(packet: MeshPacket, connectedNodeNum: Int64, context: NSManagedObjectContext) {
	if let storeAndForwardMessage = try? StoreAndForward(serializedData: packet.decoded.payload) {
		// Request Response
		switch storeAndForwardMessage.rr {
		case .unset:
			MeshLogger.log("📮 Store and Forward \(storeAndForwardMessage.rr) message received \(storeAndForwardMessage)")
		case .routerError:
			MeshLogger.log("☠️ Store and Forward \(storeAndForwardMessage.rr) message received \(storeAndForwardMessage)")
		case .routerHeartbeat:
			// Query any messages since the heartbeat.period. Send their ids to the store and forward node.
			MeshLogger.log("💓 Store and Forward \(storeAndForwardMessage.rr) message received \(storeAndForwardMessage)")
		case .routerPing:
			MeshLogger.log("🏓 Store and Forward \(storeAndForwardMessage.rr) message received \(storeAndForwardMessage)")
		case .routerPong:
			MeshLogger.log("🏓 Store and Forward \(storeAndForwardMessage.rr) message received \(storeAndForwardMessage)")
		case .routerBusy:
			MeshLogger.log("🐝 Store and Forward \(storeAndForwardMessage.rr) message received \(storeAndForwardMessage)")
		case .routerHistory:
			MeshLogger.log("📜 Store and Forward \(storeAndForwardMessage.rr) message received \(storeAndForwardMessage)")
		case .routerStats:
			MeshLogger.log("📊 Store and Forward \(storeAndForwardMessage.rr) message received \(storeAndForwardMessage)")
		case .clientError:
			MeshLogger.log("☠️ Store and Forward \(storeAndForwardMessage.rr) message received \(storeAndForwardMessage)")
		case .clientHistory:
			MeshLogger.log("📜 Store and Forward \(storeAndForwardMessage.rr) message received \(storeAndForwardMessage)")
		case .clientStats:
			MeshLogger.log("📊 Store and Forward \(storeAndForwardMessage.rr) message received \(storeAndForwardMessage)")
		case .clientPing:
			MeshLogger.log("🏓 Store and Forward \(storeAndForwardMessage.rr) message received \(storeAndForwardMessage)")
		case .clientPong:
			MeshLogger.log("🏓 Store and Forward \(storeAndForwardMessage.rr) message received \(storeAndForwardMessage)")
		case .clientAbort:
			MeshLogger.log("🛑 Store and Forward \(storeAndForwardMessage.rr) message received \(storeAndForwardMessage)")
		case .UNRECOGNIZED:
			MeshLogger.log("📮 Store and Forward \(storeAndForwardMessage.rr) message received \(storeAndForwardMessage)")
		}
	}
}

func telemetryPacket(packet: MeshPacket, connectedNode: Int64, context: NSManagedObjectContext) {

	if let telemetryMessage = try? Telemetry(serializedData: packet.decoded.payload) {

		// Only log telemetry from the mesh not the connected device
		if connectedNode != Int64(packet.from) {
			let logString = String.localizedStringWithFormat("mesh.log.telemetry.received %@".localized, String(packet.from))
			MeshLogger.log("📈 \(logString)")
		} else {
			// If it is the connected node
		}

		let telemetry = TelemetryEntity(context: context)

		let fetchNodeTelemetryRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
		fetchNodeTelemetryRequest.predicate = NSPredicate(format: "num == %lld", Int64(packet.from))

		do {

			guard let fetchedNode = try context.fetch(fetchNodeTelemetryRequest) as? [NodeInfoEntity] else {
				return
			}
			if fetchedNode.count == 1 {
				if telemetryMessage.variant == Telemetry.OneOf_Variant.deviceMetrics(telemetryMessage.deviceMetrics) {
					// Device Metrics
					telemetry.airUtilTx = telemetryMessage.deviceMetrics.airUtilTx
					telemetry.channelUtilization = telemetryMessage.deviceMetrics.channelUtilization
					telemetry.batteryLevel = Int32(telemetryMessage.deviceMetrics.batteryLevel)
					telemetry.voltage = telemetryMessage.deviceMetrics.voltage
					telemetry.metricsType = 0
				} else if telemetryMessage.variant == Telemetry.OneOf_Variant.environmentMetrics(telemetryMessage.environmentMetrics) {
					// Environment Metrics
					telemetry.barometricPressure = telemetryMessage.environmentMetrics.barometricPressure
					telemetry.current = telemetryMessage.environmentMetrics.current
					telemetry.gasResistance = telemetryMessage.environmentMetrics.gasResistance
					telemetry.relativeHumidity = telemetryMessage.environmentMetrics.relativeHumidity
					telemetry.temperature = telemetryMessage.environmentMetrics.temperature
					telemetry.current = telemetryMessage.environmentMetrics.current
					telemetry.voltage = telemetryMessage.environmentMetrics.voltage
					telemetry.metricsType = 1
				}
				telemetry.snr = packet.rxSnr
				telemetry.rssi = packet.rxRssi
				telemetry.time = Date(timeIntervalSince1970: TimeInterval(Int64(telemetryMessage.time)))
				guard let mutableTelemetries = fetchedNode[0].telemetries!.mutableCopy() as? NSMutableOrderedSet else {
					return
				}
				mutableTelemetries.add(telemetry)
				fetchedNode[0].lastHeard = telemetry.time
				fetchedNode[0].telemetries = mutableTelemetries.copy() as? NSOrderedSet
			}
			try context.save()
			// Only log telemetry from the mesh not the connected device
			if connectedNode != Int64(packet.from) {
				print("💾 Telemetry Saved for Node: \(packet.from)")
			} else if telemetry.metricsType == 0 {
				// Connected Device Metrics
				// ------------------------
				// Low Battery notification
				if telemetry.batteryLevel > 0 && telemetry.batteryLevel < 5 {
					let content = UNMutableNotificationContent()
					content.title = "Critically Low Battery!"
					content.body = "Time to charge your radio, there is \(telemetry.batteryLevel)% battery remaining."
					content.userInfo["target"] = "node"
					let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
					let uuidString = UUID().uuidString
					let request = UNNotificationRequest(identifier: uuidString, content: content, trigger: trigger)
					let notificationCenter = UNUserNotificationCenter.current()
					notificationCenter.add(request) { (error) in
						if error != nil {
							// Handle any errors.
							print("Error creating local low battery notification: \(error?.localizedDescription ?? "no description")")
						} else {
							print("Created local low battery notification.")
						}
					}
				}
				// Update our live activity if there is one running, not available on mac iOS >= 16.2
#if !targetEnvironment(macCatalyst)

					let oneMinuteLater = Calendar.current.date(byAdding: .minute, value: (Int(1) ), to: Date())!
					let date = Date.now...oneMinuteLater
					let updatedMeshStatus = MeshActivityAttributes.MeshActivityStatus(timerRange: date, connected: true, channelUtilization: telemetry.channelUtilization, airtime: telemetry.airUtilTx, batteryLevel: UInt32(telemetry.batteryLevel))
					let alertConfiguration = AlertConfiguration(title: "Mesh activity update", body: "Updated Device Metrics Data.", sound: .default)
					let updatedContent = ActivityContent(state: updatedMeshStatus, staleDate: nil)

					let meshActivity = Activity<MeshActivityAttributes>.activities.first(where: { $0.attributes.nodeNum == connectedNode })
					if meshActivity != nil {
						Task {
							await meshActivity?.update(updatedContent, alertConfiguration: alertConfiguration)
							// await meshActivity?.update(updatedContent)
							print("Updated live activity.")
						}
					}
#endif
			}
		} catch {
			context.rollback()
			let nsError = error as NSError
			print("💥 Error Saving Telemetry for Node \(packet.from) Error: \(nsError)")
		}
	} else {
		print("💥 Error Fetching NodeInfoEntity for Node \(packet.from)")
	}
}

func textMessageAppPacket(packet: MeshPacket, blockRangeTest: Bool, connectedNode: Int64, context: NSManagedObjectContext) {

	if let messageText = String(bytes: packet.decoded.payload, encoding: .utf8) {
		
		if blockRangeTest && messageText.starts(with: "seq ") {
			return
		}

		MeshLogger.log("💬 \("mesh.log.textmessage.received".localized)")

		let messageUsers: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "UserEntity")
		messageUsers.predicate = NSPredicate(format: "num IN %@", [packet.to, packet.from])
		do {
			guard let fetchedUsers = try context.fetch(messageUsers) as? [UserEntity] else {
				return
			}
			let newMessage = MessageEntity(context: context)
			newMessage.messageId = Int64(packet.id)
			newMessage.messageTimestamp = Int32(bitPattern: packet.rxTime)
			newMessage.receivedTimestamp = Int32(Date().timeIntervalSince1970)
			newMessage.receivedACK = false
			newMessage.snr = packet.rxSnr
			newMessage.rssi = packet.rxRssi
			newMessage.isEmoji = packet.decoded.emoji == 1
			newMessage.channel = Int32(packet.channel)
			newMessage.portNum = Int32(packet.decoded.portnum.rawValue)

			if packet.decoded.replyID > 0 {
				newMessage.replyID = Int64(packet.decoded.replyID)
			}

			if fetchedUsers.first(where: { $0.num == packet.to }) != nil && packet.to != 4294967295 {
				newMessage.toUser = fetchedUsers.first(where: { $0.num == packet.to })
				if connectedNode == newMessage.toUser?.num {
					//UserDefaults.unreadMessages = (newMessage.toUser?.unreadMessages ?? 0) + 1
					//UserDefaults.standard.synchronize()
				}
			}
			if fetchedUsers.first(where: { $0.num == packet.from }) != nil {
				newMessage.fromUser = fetchedUsers.first(where: { $0.num == packet.from })
			}
			newMessage.messagePayload = messageText
			newMessage.messagePayloadMarkdown = generateMessageMarkdown(message: messageText)
			if packet.to != 4294967295 {
				newMessage.fromUser?.lastMessage = Date()
			}

			var messageSaved = false

			do {

				try context.save()
				print("💾 Saved a new message for \(newMessage.messageId)")
				messageSaved = true

				if messageSaved {
					if newMessage.fromUser != nil && newMessage.toUser != nil && !(newMessage.fromUser?.mute ?? false) {
						// Create an iOS Notification for the received DM message and schedule it immediately
						let manager = LocalNotificationManager()
						manager.notifications = [
							Notification(
								id: ("notification.id.\(newMessage.messageId)"),
								title: "\(newMessage.fromUser?.longName ?? "unknown".localized)",
								subtitle: "AKA \(newMessage.fromUser?.shortName ?? "???")",
								content: messageText,
								target: "message"
							)
						]
						manager.schedule()
						print("💬 iOS Notification Scheduled for text message from \(newMessage.fromUser?.longName ?? "unknown".localized)")
					} else if newMessage.fromUser != nil && newMessage.toUser == nil {

						let fetchMyInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "MyInfoEntity")
						fetchMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", Int64(connectedNode))

						do {
							guard let fetchedMyInfo = try context.fetch(fetchMyInfoRequest) as? [MyInfoEntity] else {
								return
							}
							if !fetchedMyInfo.isEmpty {
								for channel in (fetchedMyInfo[0].channels?.array ?? []) as? [ChannelEntity] ?? [] {
									if channel.index == newMessage.channel {
										context.refresh(channel, mergeChanges: true)
									}
									if channel.index == newMessage.channel && !channel.mute {
										// Create an iOS Notification for the received private channel message and schedule it immediately
										let manager = LocalNotificationManager()
										manager.notifications = [
											Notification(
												id: ("notification.id.\(newMessage.messageId)"),
												title: "\(newMessage.fromUser?.longName ?? "unknown".localized)",
												subtitle: "AKA \(newMessage.fromUser?.shortName ?? "???")",
												content: messageText,
												target: "message")
										]
										manager.schedule()
										print("💬 iOS Notification Scheduled for text message from \(newMessage.fromUser?.longName ?? "unknown".localized)")
									}
								}
							}
						} catch {

						}
					}
				}
			} catch {
				context.rollback()
				let nsError = error as NSError
				print("💥 Failed to save new MessageEntity \(nsError)")
			}
		} catch {
			print("💥 Fetch Message To and From Users Error")
		}
	}
}

func waypointPacket (packet: MeshPacket, context: NSManagedObjectContext) {

	let logString = String.localizedStringWithFormat("mesh.log.waypoint.received %@".localized, String(packet.from))
	MeshLogger.log("📍 \(logString)")

	let fetchWaypointRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "WaypointEntity")
	fetchWaypointRequest.predicate = NSPredicate(format: "id == %lld", Int64(packet.id))

	do {

		if let waypointMessage = try? Waypoint(serializedData: packet.decoded.payload) {
			guard let fetchedWaypoint = try context.fetch(fetchWaypointRequest) as? [WaypointEntity] else {
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
				if waypointMessage.expire >= 1 {
					waypoint.expire = Date(timeIntervalSince1970: TimeInterval(Int64(waypointMessage.expire)))
				} else {
					waypoint.expire = nil
				}
				waypoint.created = Date()
				do {
					try context.save()
					print("💾 Added Node Waypoint App Packet For: \(waypoint.id)")
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
							target: "map"
						)
					]
					manager.schedule()
				} catch {
					context.rollback()
					let nsError = error as NSError
					print("💥 Error Saving WaypointEntity from WAYPOINT_APP \(nsError)")
				}
			} else {
				fetchedWaypoint[0].id = Int64(packet.id)
				fetchedWaypoint[0].name = waypointMessage.name
				fetchedWaypoint[0].longDescription = waypointMessage.description_p
				fetchedWaypoint[0].latitudeI = waypointMessage.latitudeI
				fetchedWaypoint[0].longitudeI = waypointMessage.longitudeI
				fetchedWaypoint[0].icon = Int64(waypointMessage.icon)
				fetchedWaypoint[0].locked = Int64(waypointMessage.lockedTo)
				if waypointMessage.expire >= 1 {
					fetchedWaypoint[0].expire = Date(timeIntervalSince1970: TimeInterval(Int64(waypointMessage.expire)))
				} else {
					fetchedWaypoint[0].expire = nil
				}
				fetchedWaypoint[0].lastUpdated = Date()
				do {
					try context.save()
					print("💾 Updated Node Waypoint App Packet For: \(fetchedWaypoint[0].id)")
				} catch {
					context.rollback()
					let nsError = error as NSError
					print("💥 Error Saving WaypointEntity from WAYPOINT_APP \(nsError)")
				}
			}
		}
	} catch {
		print("💥 Error Deserializing WAYPOINT_APP packet.")
	}
}
