//
//  MeshPackets.swift
//  Meshtastic Apple
//
//  Created by Garth Vander Houwen on 5/27/22.
//

import Foundation
import CoreData
import MeshtasticProtobufs
import SwiftUI
import RegexBuilder
import OSLog
#if canImport(ActivityKit)
import ActivityKit
#endif

func generateMessageMarkdown (message: String) -> String {
	if !message.isEmoji() {
		let types: NSTextCheckingResult.CheckingType = [.address, .link, .phoneNumber]
		guard let detector = try? NSDataDetector(types: types.rawValue) else {
			return message
		}
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
					let start = match.range.lowerBound
					let stop = match.range.upperBound
					let url = message[start ..< stop]
					let absoluteUrl = match.url?.absoluteString ?? ""
					let markdownUrl = "[\(url)](\(absoluteUrl))"
					messageWithMarkdown = messageWithMarkdown.replacingOccurrences(of: url, with: markdownUrl)
				}
			}
		}
		return messageWithMarkdown
	}
	return message
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
	} else if config.payloadVariant == Config.OneOf_PayloadVariant.power(config.power) {
		upsertPowerConfigPacket(config: config.power, nodeNum: nodeNum, context: context)
	}
}

func moduleConfig (config: ModuleConfig, context: NSManagedObjectContext, nodeNum: Int64, nodeLongName: String) {

	if config.payloadVariant == ModuleConfig.OneOf_PayloadVariant.ambientLighting(config.ambientLighting) {
		upsertAmbientLightingModuleConfigPacket(config: config.ambientLighting, nodeNum: nodeNum, context: context)
	} else if config.payloadVariant == ModuleConfig.OneOf_PayloadVariant.cannedMessage(config.cannedMessage) {
		upsertCannedMessagesModuleConfigPacket(config: config.cannedMessage, nodeNum: nodeNum, context: context)
	} else if config.payloadVariant == ModuleConfig.OneOf_PayloadVariant.detectionSensor(config.detectionSensor) {
		upsertDetectionSensorModuleConfigPacket(config: config.detectionSensor, nodeNum: nodeNum, context: context)
	} else if config.payloadVariant == ModuleConfig.OneOf_PayloadVariant.externalNotification(config.externalNotification) {
		upsertExternalNotificationModuleConfigPacket(config: config.externalNotification, nodeNum: nodeNum, context: context)
	} else if config.payloadVariant == ModuleConfig.OneOf_PayloadVariant.mqtt(config.mqtt) {
		upsertMqttModuleConfigPacket(config: config.mqtt, nodeNum: nodeNum, context: context)
	} else if config.payloadVariant == ModuleConfig.OneOf_PayloadVariant.paxcounter(config.paxcounter) {
		upsertPaxCounterModuleConfigPacket(config: config.paxcounter, nodeNum: nodeNum, context: context)
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

	let fetchMyInfoRequest = MyInfoEntity.fetchRequest()
	fetchMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", Int64(myInfo.myNodeNum))

	do {
		let fetchedMyInfo = try context.fetch(fetchMyInfoRequest)
		// Not Found Insert
		if fetchedMyInfo.isEmpty {

			let myInfoEntity = MyInfoEntity(context: context)
			myInfoEntity.peripheralId = peripheralId
			myInfoEntity.myNodeNum = Int64(myInfo.myNodeNum)
			myInfoEntity.rebootCount = Int32(myInfo.rebootCount)
			do {
				try context.save()
				Logger.data.info("💾 Saved a new myInfo for node: \(myInfo.myNodeNum.toHex(), privacy: .public)")
				return myInfoEntity
			} catch {
				context.rollback()
				let nsError = error as NSError
				Logger.data.error("💥 Error Inserting New Core Data MyInfoEntity: \(nsError, privacy: .public)")
			}
		} else {

			fetchedMyInfo[0].peripheralId = peripheralId
			fetchedMyInfo[0].myNodeNum = Int64(myInfo.myNodeNum)
			fetchedMyInfo[0].rebootCount = Int32(myInfo.rebootCount)

			do {
				try context.save()
				Logger.data.info("💾 Updated myInfo for node: \(myInfo.myNodeNum.toHex(), privacy: .public)")
				return fetchedMyInfo[0]
			} catch {
				context.rollback()
				let nsError = error as NSError
				Logger.data.error("💥 Error Updating Core Data MyInfoEntity: \(nsError, privacy: .public)")
			}
		}
	} catch {
		Logger.data.error("💥 Fetch MyInfo Error")
	}
	return nil
}

func channelPacket (channel: Channel, fromNum: Int64, context: NSManagedObjectContext) {

	if channel.isInitialized && channel.hasSettings && channel.role != Channel.Role.disabled {

		let logString = String.localizedStringWithFormat("mesh.log.channel.received %d %@".localized, channel.index, String(fromNum))
		MeshLogger.log("🎛️ \(logString)")

		let fetchedMyInfoRequest = MyInfoEntity.fetchRequest()
		fetchedMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", fromNum)

		do {
			let fetchedMyInfo = try context.fetch(fetchedMyInfoRequest)
			if fetchedMyInfo.count == 1 {
				let newChannel = ChannelEntity(context: context)
				newChannel.id = Int32(channel.index)
				newChannel.index = Int32(channel.index)
				newChannel.uplinkEnabled = channel.settings.uplinkEnabled
				newChannel.downlinkEnabled = channel.settings.downlinkEnabled
				newChannel.name = channel.settings.name
				newChannel.role = Int32(channel.role.rawValue)
				newChannel.psk = channel.settings.psk
				if channel.settings.hasModuleSettings {
					newChannel.positionPrecision = Int32(truncatingIfNeeded: channel.settings.moduleSettings.positionPrecision)
					newChannel.mute = channel.settings.moduleSettings.isClientMuted
				}
				guard let mutableChannels = fetchedMyInfo[0].channels!.mutableCopy() as? NSMutableOrderedSet else {
					return
				}
				if let oldChannel = mutableChannels.first(where: {($0 as AnyObject).index == newChannel.index }) as? ChannelEntity {
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
				} catch {
					Logger.data.error("💥 Failed to save channel: \(error.localizedDescription, privacy: .public)")
				}
				Logger.data.info("💾 Updated MyInfo channel \(channel.index) from Channel App Packet For: \(fetchedMyInfo[0].myNodeNum)")
			} else if channel.role.rawValue > 0 {
				Logger.data.error("💥Trying to save a channel to a MyInfo that does not exist: \(fromNum.toHex(), privacy: .public)")
			}
		} catch {
			context.rollback()
			let nsError = error as NSError
			Logger.data.error("💥 Error Saving MyInfo Channel from ADMIN_APP \(nsError, privacy: .public)")
		}
	}
}

func deviceMetadataPacket (metadata: DeviceMetadata, fromNum: Int64, context: NSManagedObjectContext) {

	if metadata.isInitialized {
		let logString = String.localizedStringWithFormat("mesh.log.device.metadata.received %@".localized, fromNum.toHex())
		MeshLogger.log("🏷️ \(logString)")

		let fetchedNodeRequest = NodeInfoEntity.fetchRequest()
		fetchedNodeRequest.predicate = NSPredicate(format: "num == %lld", fromNum)

		do {
			let fetchedNode = try context.fetch(fetchedNodeRequest)
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
			var version = metadata.firmwareVersion[...(lastDotIndex ?? String.Index(utf16Offset: 6, in: metadata.firmwareVersion))]
			version = version.dropLast()
			newMetadata.firmwareVersion = String(version)
			if fetchedNode.count > 0 {
				fetchedNode[0].metadata = newMetadata
			} else {

				if fromNum > 0 {
					let newNode = createNodeInfo(num: Int64(fromNum), context: context)
					newNode.metadata = newMetadata
				}
			}
			do {
				try context.save()
			} catch {
				Logger.data.error("💥 Failed to save device metadata: \(error.localizedDescription, privacy: .public)")
			}
			Logger.data.info("💾 Updated Device Metadata from Admin App Packet For: \(fromNum.toHex(), privacy: .public)")
		} catch {
			context.rollback()
			let nsError = error as NSError
			Logger.data.error("Error Saving MyInfo Channel from ADMIN_APP \(nsError, privacy: .public)")
		}
	}
}

func nodeInfoPacket (nodeInfo: NodeInfo, channel: UInt32, context: NSManagedObjectContext) -> NodeInfoEntity? {

	let logString = String.localizedStringWithFormat("mesh.log.nodeinfo.received %@".localized, String(nodeInfo.num))
	MeshLogger.log("📟 \(logString)")

	guard nodeInfo.num > 0 else { return nil }

	let fetchNodeInfoRequest = NodeInfoEntity.fetchRequest()
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeInfo.num))

	do {
		let fetchedNode = try context.fetch(fetchNodeInfoRequest)
		// Not Found Insert
		if fetchedNode.isEmpty && nodeInfo.num > 0 {

			let newNode = NodeInfoEntity(context: context)
			newNode.id = Int64(nodeInfo.num)
			newNode.num = Int64(nodeInfo.num)
			newNode.channel = Int32(nodeInfo.channel)
			newNode.favorite = nodeInfo.isFavorite
			newNode.hopsAway = Int32(nodeInfo.hopsAway)

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
			newNode.firstHeard = Date(timeIntervalSince1970: TimeInterval(Int64(nodeInfo.lastHeard)))
			newNode.lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(nodeInfo.lastHeard)))
			newNode.snr = nodeInfo.snr
			if nodeInfo.hasUser {

				let newUser = UserEntity(context: context)
				newUser.userId = nodeInfo.user.id
				newUser.num = Int64(nodeInfo.num)
				newUser.longName = nodeInfo.user.longName
				newUser.shortName = nodeInfo.user.shortName
				newUser.hwModel = String(describing: nodeInfo.user.hwModel).uppercased()
				newUser.hwModelId = Int32(nodeInfo.user.hwModel.rawValue)
				Task {
					Api().loadDeviceHardwareData { (hw) in
						let dh = hw.first(where: { $0.hwModel == newUser.hwModelId })
						newUser.hwDisplayName = dh?.displayName
					}
				}
				newUser.isLicensed = nodeInfo.user.isLicensed
				newUser.role = Int32(nodeInfo.user.role.rawValue)
				newNode.user = newUser
			} else if nodeInfo.num > Constants.minimumNodeNum {
				let newUser = createUser(num: Int64(nodeInfo.num), context: context)
				newNode.user = newUser
			}

			if (nodeInfo.position.longitudeI != 0 && nodeInfo.position.latitudeI != 0) && (nodeInfo.position.latitudeI != 373346000 && nodeInfo.position.longitudeI != -1220090000) {
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
			let fetchMyInfoRequest = MyInfoEntity.fetchRequest()
			fetchMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", Int64(nodeInfo.num))

			do {
				let fetchedMyInfo = try context.fetch(fetchMyInfoRequest)
				if fetchedMyInfo.count > 0 {
					newNode.myInfo = fetchedMyInfo[0]
				}
				do {
					try context.save()
					Logger.data.info("💾 Saved a new Node Info For: \(String(nodeInfo.num))")
					return newNode
				} catch {
					context.rollback()
					let nsError = error as NSError
					Logger.data.error("Error Saving Core Data NodeInfoEntity: \(nsError)")
				}
			} catch {
				Logger.data.error("Fetch MyInfo Error")
			}
		} else if nodeInfo.num > 0 {

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
					Api().loadDeviceHardwareData { (hw) in
						let dh = hw.first(where: { $0.hwModel == fetchedNode[0].user!.hwModelId })
						fetchedNode[0].user!.hwDisplayName = dh?.displayName
					}
				}
			} else {
				if fetchedNode[0].user == nil && nodeInfo.num > Constants.minimumNodeNum {

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

				if (nodeInfo.position.longitudeI != 0 && nodeInfo.position.latitudeI != 0) && (nodeInfo.position.latitudeI != 373346000 && nodeInfo.position.longitudeI != -1220090000) {

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
			let fetchMyInfoRequest = MyInfoEntity.fetchRequest()
			fetchMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", Int64(nodeInfo.num))

			do {
				let fetchedMyInfo = try context.fetch(fetchMyInfoRequest)
				if fetchedMyInfo.count > 0 {
					fetchedNode[0].myInfo = fetchedMyInfo[0]
				}
				do {
					try context.save()
					Logger.data.info("💾 [NodeInfo] saved for \(nodeInfo.num.toHex(), privacy: .public)")
					return fetchedNode[0]
				} catch {
					context.rollback()
					let nsError = error as NSError
					Logger.data.error("💥 Error Saving Core Data NodeInfoEntity: \(nsError, privacy: .public)")
				}
			} catch {
				Logger.data.error("💥 Fetch MyInfo Error")
			}
		}
	} catch {
		Logger.data.error("💥 Fetch NodeInfoEntity Error")
	}
	return nil
}

func adminAppPacket (packet: MeshPacket, context: NSManagedObjectContext) {

	if let adminMessage = try? AdminMessage(serializedData: packet.decoded.payload) {

		if adminMessage.payloadVariant == AdminMessage.OneOf_PayloadVariant.getCannedMessageModuleMessagesResponse(adminMessage.getCannedMessageModuleMessagesResponse) {

			if let cmmc = try? CannedMessageModuleConfig(serializedData: packet.decoded.payload) {

				if !cmmc.messages.isEmpty {

					let logString = String.localizedStringWithFormat("mesh.log.cannedmessages.messages.received %@".localized, packet.from.toHex())
					MeshLogger.log("🥫 \(logString)")

					let fetchNodeRequest = NodeInfoEntity.fetchRequest()
					fetchNodeRequest.predicate = NSPredicate(format: "num == %lld", Int64(packet.from))

					do {
						let fetchedNode = try context.fetch(fetchNodeRequest)
						if fetchedNode.count == 1 {
							let messages =  String(cmmc.textFormatString())
								.replacingOccurrences(of: "11: ", with: "")
								.replacingOccurrences(of: "\"", with: "")
								.trimmingCharacters(in: .whitespacesAndNewlines)
							fetchedNode[0].cannedMessageConfig?.messages = messages
							do {
								try context.save()
								Logger.data.info("💾 Updated Canned Messages Messages For: \(fetchedNode[0].num.toHex(), privacy: .public)")
							} catch {
								context.rollback()
								let nsError = error as NSError
								Logger.data.error("💥 Error Saving NodeInfoEntity from POSITION_APP \(nsError, privacy: .public)")
							}
						}
					} catch {
						Logger.data.error("💥 Error Deserializing ADMIN_APP packet.")
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
			} else if config.payloadVariant == Config.OneOf_PayloadVariant.power(config.power) {
				upsertPowerConfigPacket(config: config.power, nodeNum: Int64(packet.from), context: context)
			}
		} else if adminMessage.payloadVariant == AdminMessage.OneOf_PayloadVariant.getModuleConfigResponse(adminMessage.getModuleConfigResponse) {
			let moduleConfig = adminMessage.getModuleConfigResponse
			if moduleConfig.payloadVariant == ModuleConfig.OneOf_PayloadVariant.ambientLighting(moduleConfig.ambientLighting) {
				upsertAmbientLightingModuleConfigPacket(config: moduleConfig.ambientLighting, nodeNum: Int64(packet.from), context: context)
			} else if moduleConfig.payloadVariant == ModuleConfig.OneOf_PayloadVariant.cannedMessage(moduleConfig.cannedMessage) {
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
			MeshLogger.log("🕸️ MESH PACKET received Admin App UNHANDLED \((try? packet.decoded.jsonString()) ?? "JSON Decode Failure")")
		}
		// Save an ack for the admin message log for each admin message response received as we stopped sending acks if there is also a response to reduce airtime.
		adminResponseAck(packet: packet, context: context)
	}
}

func adminResponseAck (packet: MeshPacket, context: NSManagedObjectContext) {

	let fetchedAdminMessageRequest = MessageEntity.fetchRequest()
	fetchedAdminMessageRequest.predicate = NSPredicate(format: "messageId == %lld", packet.decoded.requestID)
	do {
		let fetchedMessage = try context.fetch(fetchedAdminMessageRequest)
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
				Logger.data.error("Failed to save admin message response as an ack: \(error.localizedDescription)")
			}
		}
	} catch {
		Logger.data.error("Failed to fetch admin message by requestID: \(error.localizedDescription)")
	}
}
func paxCounterPacket (packet: MeshPacket, context: NSManagedObjectContext) {

	let logString = String.localizedStringWithFormat("mesh.log.paxcounter %@".localized, String(packet.from))
	MeshLogger.log("🧑‍🤝‍🧑 \(logString)")

	let fetchNodeInfoRequest = NodeInfoEntity.fetchRequest()
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(packet.from))

	do {
		let fetchedNode = try context.fetch(fetchNodeInfoRequest)

		if let paxMessage = try? Paxcount(serializedData: packet.decoded.payload) {

			let newPax = PaxCounterEntity(context: context)
			newPax.ble = Int32(truncatingIfNeeded: paxMessage.ble)
			newPax.wifi = Int32(truncatingIfNeeded: paxMessage.wifi)
			newPax.uptime = Int32(truncatingIfNeeded: paxMessage.uptime)
			newPax.time = Date()

			if fetchedNode.count > 0 {
				guard let mutablePax = fetchedNode[0].pax!.mutableCopy() as? NSMutableOrderedSet else {
					return
				}
				mutablePax.add(newPax)
				fetchedNode[0].pax = mutablePax
				do {
					try context.save()
				} catch {
					Logger.data.error("Failed to save pax: \(error.localizedDescription)")
				}
			} else {
				Logger.data.info("Node Info Not Found")
			}
		}
	} catch {

	}
}

func routingPacket (packet: MeshPacket, connectedNodeNum: Int64, context: NSManagedObjectContext) {

	if let routingMessage = try? Routing(serializedData: packet.decoded.payload) {

		let routingError = RoutingError(rawValue: routingMessage.errorReason.rawValue)

		let routingErrorString = routingError?.display ?? "unknown".localized
		let logString = String.localizedStringWithFormat("mesh.log.routing.message %@ %@".localized, String(packet.decoded.requestID), routingErrorString)
		MeshLogger.log("🕸️ \(logString)")

		let fetchMessageRequest = MessageEntity.fetchRequest()
		fetchMessageRequest.predicate = NSPredicate(format: "messageId == %lld", Int64(packet.decoded.requestID))

		do {
			let fetchedMessage = try context.fetch(fetchMessageRequest)
			if fetchedMessage.count > 0 {

				if fetchedMessage[0].toUser != nil {
					// Real ACK from DM Recipient
					if packet.to != packet.from {
						fetchedMessage[0].realACK = true
					}
				}
				fetchedMessage[0].ackError = Int32(routingMessage.errorReason.rawValue)

				if routingMessage.errorReason == Routing.Error.none {

					fetchedMessage[0].receivedACK = true
				}
				fetchedMessage[0].ackSNR = packet.rxSnr
				fetchedMessage[0].ackTimestamp = Int32(truncatingIfNeeded: packet.rxTime)

				if fetchedMessage[0].toUser != nil {
					fetchedMessage[0].toUser!.objectWillChange.send()
				} else {
					let fetchMyInfoRequest = MyInfoEntity.fetchRequest()
					fetchMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", connectedNodeNum)
					do {
						let fetchedMyInfo = try context.fetch(fetchMyInfoRequest)
						if fetchedMyInfo.count > 0 {

							for ch in fetchedMyInfo[0].channels!.array as? [ChannelEntity] ?? [] where ch.index == packet.channel {
								ch.objectWillChange.send()
							}
						}
					} catch { }
				}

			} else {
				return
			}
			try context.save()
			Logger.data.info("💾 ACK Saved for Message: \(packet.decoded.requestID)")
		} catch {
			context.rollback()
			let nsError = error as NSError
			Logger.data.error("Error Saving ACK for message: \(packet.id) Error: \(nsError)")
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
		if telemetryMessage.variant != Telemetry.OneOf_Variant.deviceMetrics(telemetryMessage.deviceMetrics) && telemetryMessage.variant != Telemetry.OneOf_Variant.environmentMetrics(telemetryMessage.environmentMetrics) {
			/// Other unhandled telemetry packets
			return
		}

		let telemetry = TelemetryEntity(context: context)

		let fetchNodeTelemetryRequest = NodeInfoEntity.fetchRequest()
		fetchNodeTelemetryRequest.predicate = NSPredicate(format: "num == %lld", Int64(packet.from))

		do {
			let fetchedNode = try context.fetch(fetchNodeTelemetryRequest)
			if fetchedNode.count == 1 {
				/// Currently only Device Metrics and Environment Telemetry are supported in the app
				if telemetryMessage.variant == Telemetry.OneOf_Variant.deviceMetrics(telemetryMessage.deviceMetrics) {
					// Device Metrics
					telemetry.airUtilTx = telemetryMessage.deviceMetrics.airUtilTx
					telemetry.channelUtilization = telemetryMessage.deviceMetrics.channelUtilization
					telemetry.batteryLevel = Int32(telemetryMessage.deviceMetrics.batteryLevel)
					telemetry.voltage = telemetryMessage.deviceMetrics.voltage
					telemetry.uptimeSeconds = Int32(telemetryMessage.deviceMetrics.uptimeSeconds)
					telemetry.metricsType = 0
					Logger.statistics.info("📈 [Mesh Statistics] Channel Utilization: \(telemetryMessage.deviceMetrics.channelUtilization, privacy: .public) Airtime: \(telemetryMessage.deviceMetrics.airUtilTx, privacy: .public) for Node: \(packet.from.toHex(), privacy: .public)")
				} else if telemetryMessage.variant == Telemetry.OneOf_Variant.environmentMetrics(telemetryMessage.environmentMetrics) {
					// Environment Metrics
					telemetry.barometricPressure = telemetryMessage.environmentMetrics.barometricPressure
					telemetry.current = telemetryMessage.environmentMetrics.current
					telemetry.iaq = Int32(truncatingIfNeeded: telemetryMessage.environmentMetrics.iaq)
					telemetry.gasResistance = telemetryMessage.environmentMetrics.gasResistance
					telemetry.relativeHumidity = telemetryMessage.environmentMetrics.relativeHumidity
					telemetry.temperature = telemetryMessage.environmentMetrics.temperature
					telemetry.current = telemetryMessage.environmentMetrics.current
					telemetry.voltage = telemetryMessage.environmentMetrics.voltage
					telemetry.weight = telemetryMessage.environmentMetrics.weight
					telemetry.windSpeed = telemetryMessage.environmentMetrics.windSpeed
					telemetry.windGust = telemetryMessage.environmentMetrics.windGust
					telemetry.windLull = telemetryMessage.environmentMetrics.windLull
					telemetry.windDirection = Int32(truncatingIfNeeded: telemetryMessage.environmentMetrics.windDirection)
					telemetry.metricsType = 1
				}
				telemetry.snr = packet.rxSnr
				telemetry.rssi = packet.rxRssi
				telemetry.time = Date(timeIntervalSince1970: TimeInterval(Int64(truncatingIfNeeded: telemetryMessage.time)))
				guard let mutableTelemetries = fetchedNode[0].telemetries!.mutableCopy() as? NSMutableOrderedSet else {
					return
				}
				mutableTelemetries.add(telemetry)
				fetchedNode[0].lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(truncatingIfNeeded: packet.rxTime)))
				fetchedNode[0].telemetries = mutableTelemetries.copy() as? NSOrderedSet
			}
			try context.save()
			// Only log telemetry from the mesh not the connected device
			if connectedNode != Int64(packet.from) {
				Logger.data.info("💾 [TelemetryEntity] Saved for Node: \(packet.from.toHex())")
			} else if telemetry.metricsType == 0 {
				// Connected Device Metrics
				// ------------------------
				// Low Battery notification
				if UserDefaults.lowBatteryNotifications && telemetry.batteryLevel > 0 && telemetry.batteryLevel < 4 {
					let manager = LocalNotificationManager()
					manager.notifications = [
						Notification(
							id: ("notification.id.\(UUID().uuidString)"),
							title: "Critically Low Battery!",
							subtitle: "AKA \(telemetry.nodeTelemetry?.user?.shortName ?? "UNK")",
							content: "Time to charge your radio, there is \(telemetry.batteryLevel)% battery remaining.",
							target: "nodes",
							path: "meshtastic:///nodes?nodenum=\(telemetry.nodeTelemetry?.num ?? 0)"
						)
					]
					manager.schedule()
				}
				// Update our live activity if there is one running, not available on mac iOS >= 16.2
#if !targetEnvironment(macCatalyst)

					let oneMinuteLater = Calendar.current.date(byAdding: .minute, value: (Int(1) ), to: Date())!
					let date = Date.now...oneMinuteLater
				let updatedMeshStatus = MeshActivityAttributes.MeshActivityStatus(timerRange: date, connected: true, channelUtilization: telemetry.channelUtilization, airtime: telemetry.airUtilTx, batteryLevel: UInt32(telemetry.batteryLevel), nodes: 17, nodesOnline: 9)
				let alertConfiguration = AlertConfiguration(title: "Mesh activity update", body: "Updated Device Metrics Data.", sound: .default)
					let updatedContent = ActivityContent(state: updatedMeshStatus, staleDate: nil)

					let meshActivity = Activity<MeshActivityAttributes>.activities.first(where: { $0.attributes.nodeNum == connectedNode })
					if meshActivity != nil {
						Task {
							await meshActivity?.update(updatedContent, alertConfiguration: alertConfiguration)
							// await meshActivity?.update(updatedContent)
							Logger.services.debug("Updated live activity.")
						}
					}
#endif
			}
		} catch {
			context.rollback()
			let nsError = error as NSError
			Logger.data.error("💥 Error Saving Telemetry for Node \(packet.from, privacy: .public) Error: \(nsError, privacy: .public)")
		}
	} else {
		Logger.data.error("💥 Error Fetching NodeInfoEntity for Node \(packet.from.toHex(), privacy: .public)")
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

	var messageText = String(bytes: packet.decoded.payload, encoding: .utf8)
	let rangeRef = Reference(Int.self)
	let rangeTestRegex = Regex {
		"seq "

		TryCapture(as: rangeRef) {
			OneOrMore(.digit)
		} transform: { match in
			Int(match)
		}
	}
	let rangeTest = messageText?.contains(rangeTestRegex) ?? false && messageText?.starts(with: "seq ") ?? false

	if !wantRangeTestPackets && rangeTest {
		return
	}
	var storeForwardBroadcast = false
	if storeForward {
		if let storeAndForwardMessage = try? StoreAndForward(serializedData: packet.decoded.payload) {
			messageText = String(bytes: storeAndForwardMessage.text, encoding: .utf8)
			if storeAndForwardMessage.rr == .routerTextBroadcast {
				storeForwardBroadcast = true
			}
		}
	}

	if messageText?.count ?? 0 > 0 {

		MeshLogger.log("💬 \("mesh.log.textmessage.received".localized)")

		let messageUsers = UserEntity.fetchRequest()
		messageUsers.predicate = NSPredicate(format: "num IN %@", [packet.to, packet.from])
		do {
			let fetchedUsers = try context.fetch(messageUsers)
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
			if packet.decoded.portnum == PortNum.detectionSensorApp {
				if !UserDefaults.enableDetectionNotifications {
					newMessage.read = true
				}
			}
			if packet.decoded.replyID > 0 {
				newMessage.replyID = Int64(packet.decoded.replyID)
			}

			if fetchedUsers.first(where: { $0.num == packet.to }) != nil && packet.to != Constants.maximumNodeNum {
				if !storeForwardBroadcast {
					newMessage.toUser = fetchedUsers.first(where: { $0.num == packet.to })
				}
			}
			if fetchedUsers.first(where: { $0.num == packet.from }) != nil {
				newMessage.fromUser = fetchedUsers.first(where: { $0.num == packet.from })
				if packet.rxTime > 0 {
					newMessage.fromUser?.userNode?.lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(packet.rxTime)))
				}
			}
			newMessage.messagePayload = messageText
			newMessage.messagePayloadMarkdown = generateMessageMarkdown(message: messageText!)
			if packet.to != Constants.maximumNodeNum && newMessage.fromUser != nil {
				newMessage.fromUser?.lastMessage = Date()
			}
			var messageSaved = false

			do {

				try context.save()
				Logger.data.info("💾 Saved a new message for \(newMessage.messageId)")
				messageSaved = true

				if messageSaved {

					if packet.decoded.portnum == PortNum.detectionSensorApp && !UserDefaults.enableDetectionNotifications {
						return
					}
					if newMessage.fromUser != nil && newMessage.toUser != nil {
						// Set Unread Message Indicators
						if packet.to == connectedNode {
							appState.unreadDirectMessages = newMessage.toUser?.unreadMessages ?? 0
						}
						if !(newMessage.fromUser?.mute ?? false) {
							// Create an iOS Notification for the received DM message and schedule it immediately
							let manager = LocalNotificationManager()
							manager.notifications = [
								Notification(
									id: ("notification.id.\(newMessage.messageId)"),
									title: "\(newMessage.fromUser?.longName ?? "unknown".localized)",
									subtitle: "AKA \(newMessage.fromUser?.shortName ?? "?")",
									content: messageText!,
									target: "messages",
									path: "meshtastic:///messages?userNum=\(newMessage.fromUser?.num ?? 0)&messageId=\(newMessage.messageId)"
								)
							]
							manager.schedule()
							Logger.services.debug("iOS Notification Scheduled for text message from \(newMessage.fromUser?.longName ?? "unknown".localized)")
						}
					} else if newMessage.fromUser != nil && newMessage.toUser == nil {

						let fetchMyInfoRequest = MyInfoEntity.fetchRequest()
						fetchMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", Int64(connectedNode))

						do {
							let fetchedMyInfo = try context.fetch(fetchMyInfoRequest)
							if !fetchedMyInfo.isEmpty {
								appState.unreadChannelMessages = fetchedMyInfo[0].unreadMessages

								for channel in (fetchedMyInfo[0].channels?.array ?? []) as? [ChannelEntity] ?? [] {
									if channel.index == newMessage.channel {
										context.refresh(channel, mergeChanges: true)
									}
									if channel.index == newMessage.channel && !channel.mute && UserDefaults.channelMessageNotifications {
										// Create an iOS Notification for the received private channel message and schedule it immediately
										let manager = LocalNotificationManager()
										manager.notifications = [
											Notification(
												id: ("notification.id.\(newMessage.messageId)"),
												title: "\(newMessage.fromUser?.longName ?? "unknown".localized)",
												subtitle: "AKA \(newMessage.fromUser?.shortName ?? "?")",
												content: messageText!,
												target: "messages",
												path: "meshtastic:///messages?channelId=\(newMessage.channel)&messageId=\(newMessage.messageId)")
										]
										manager.schedule()
										Logger.services.debug("iOS Notification Scheduled for text message from \(newMessage.fromUser?.longName ?? "unknown".localized)")
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
				Logger.data.error("Failed to save new MessageEntity \(nsError)")
			}
		} catch {
			Logger.data.error("Fetch Message To and From Users Error")
		}
	}
}

func waypointPacket (packet: MeshPacket, context: NSManagedObjectContext) {

	let logString = String.localizedStringWithFormat("mesh.log.waypoint.received %@".localized, String(packet.from))
	MeshLogger.log("📍 \(logString)")

	let fetchWaypointRequest = WaypointEntity.fetchRequest()
	fetchWaypointRequest.predicate = NSPredicate(format: "id == %lld", Int64(packet.id))

	do {

		if let waypointMessage = try? Waypoint(serializedData: packet.decoded.payload) {
			let fetchedWaypoint = try context.fetch(fetchWaypointRequest)
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
					Logger.data.info("💾 Added Node Waypoint App Packet For: \(waypoint.id)")
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
					Logger.data.debug("meshtastic:///map?waypointid=\(waypoint.id)")
					manager.schedule()
				} catch {
					context.rollback()
					let nsError = error as NSError
					Logger.data.error("Error Saving WaypointEntity from WAYPOINT_APP \(nsError)")
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
					Logger.data.info("💾 Updated Node Waypoint App Packet For: \(fetchedWaypoint[0].id)")
				} catch {
					context.rollback()
					let nsError = error as NSError
					Logger.data.error("Error Saving WaypointEntity from WAYPOINT_APP \(nsError)")
				}
			}
		}
	} catch {
		Logger.mesh.error("Error Deserializing WAYPOINT_APP packet.")
	}
}
