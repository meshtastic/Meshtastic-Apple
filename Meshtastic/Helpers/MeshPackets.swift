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

// Simple extension to concisely pass values through a has_XXX boolean check
fileprivate extension Bool {
	func then<T>(_ value: T) -> T? {
		self ? value : nil
	}
}

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
	switch config.payloadVariant {
	case .bluetooth:
		upsertBluetoothConfigPacket(config: config.bluetooth, nodeNum: nodeNum, context: context)
	case .device:
		upsertDeviceConfigPacket(config: config.device, nodeNum: nodeNum, context: context)
	case .display:
		upsertDisplayConfigPacket(config: config.display, nodeNum: nodeNum, context: context)
	case .lora:
		upsertLoRaConfigPacket(config: config.lora, nodeNum: nodeNum, context: context)
	case .network:
		upsertNetworkConfigPacket(config: config.network, nodeNum: nodeNum, context: context)
	case .position:
		upsertPositionConfigPacket(config: config.position, nodeNum: nodeNum, context: context)
	case .power:
		upsertPowerConfigPacket(config: config.power, nodeNum: nodeNum, context: context)
	case .security:
		upsertSecurityConfigPacket(config: config.security, nodeNum: nodeNum, context: context)
	default:
#if DEBUG
		Logger.services.error("⁉️ Unknown Config variant UNHANDLED \(config.payloadVariant.debugDescription, privacy: .public)")
#endif
	}
}

func moduleConfig (config: ModuleConfig, context: NSManagedObjectContext, nodeNum: Int64, nodeLongName: String) {
	switch config.payloadVariant {
	case .ambientLighting:
		upsertAmbientLightingModuleConfigPacket(config: config.ambientLighting, nodeNum: nodeNum, context: context)
	case .cannedMessage:
		upsertCannedMessagesModuleConfigPacket(config: config.cannedMessage, nodeNum: nodeNum, context: context)
	case .detectionSensor:
		upsertDetectionSensorModuleConfigPacket(config: config.detectionSensor, nodeNum: nodeNum, context: context)
	case .externalNotification:
		upsertExternalNotificationModuleConfigPacket(config: config.externalNotification, nodeNum: nodeNum, context: context)
	case .mqtt:
		upsertMqttModuleConfigPacket(config: config.mqtt, nodeNum: nodeNum, context: context)
	case .paxcounter:
		upsertPaxCounterModuleConfigPacket(config: config.paxcounter, nodeNum: nodeNum, context: context)
	case .rangeTest:
		upsertRangeTestModuleConfigPacket(config: config.rangeTest, nodeNum: nodeNum, context: context)
	case .serial:
		upsertSerialModuleConfigPacket(config: config.serial, nodeNum: nodeNum, context: context)
	case .telemetry:
		upsertTelemetryModuleConfigPacket(config: config.telemetry, nodeNum: nodeNum, context: context)
	case .storeForward:
		upsertStoreForwardModuleConfigPacket(config: config.storeForward, nodeNum: nodeNum, context: context)
	default:
#if DEBUG
		Logger.services.error("⁉️ Unknown Module Config variant UNHANDLED \(config.payloadVariant.debugDescription, privacy: .public)")
#endif
	}
}

func myInfoPacket (myInfo: MyNodeInfo, peripheralId: String, context: NSManagedObjectContext) -> MyInfoEntity? {

	let logString = String.localizedStringWithFormat("MyInfo received: %@".localized, String(myInfo.myNodeNum))
	Logger.mesh.info("ℹ️ \(logString, privacy: .public)")

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
			myInfoEntity.deviceId = myInfo.deviceID
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
		Logger.mesh.info("🎛️ \(logString, privacy: .public)")

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
					newChannel.mute = channel.settings.moduleSettings.isMuted
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
				context.refresh(newChannel, mergeChanges: true)
				do {
					try context.save()
				} catch {
					Logger.data.error("💥 Failed to save channel: \(error.localizedDescription, privacy: .public)")
				}
				Logger.data.info("💾 Updated MyInfo channel \(channel.index, privacy: .public) from Channel App Packet For: \(fetchedMyInfo[0].myNodeNum, privacy: .public)")
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

func deviceMetadataPacket (metadata: DeviceMetadata, fromNum: Int64, sessionPasskey: Data? = Data(), context: NSManagedObjectContext) {

	if metadata.isInitialized {
		let logString = String.localizedStringWithFormat("Device Metadata received from: %@".localized, fromNum.toHex())
		Logger.mesh.info("🏷️ \(logString, privacy: .public)")

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
			newMetadata.excludedModules = Int32(metadata.excludedModules)
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
			if sessionPasskey?.count != 0 {
				fetchedNode[0].sessionPasskey = sessionPasskey
				fetchedNode[0].sessionExpiration = Date().addingTimeInterval(300)
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

func nodeInfoPacket (nodeInfo: NodeInfo, channel: UInt32, context: NSManagedObjectContext, deferSave: Bool = false) -> NodeInfoEntity? {

	let logString = String.localizedStringWithFormat("[NodeInfo] received for: %@".localized, String(nodeInfo.num))
	Logger.mesh.info("📟 \(logString, privacy: .public)")

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
			newNode.ignored = nodeInfo.isIgnored
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
			if nodeInfo.lastHeard > 0 {
				newNode.firstHeard = Date(timeIntervalSince1970: TimeInterval(Int64(nodeInfo.lastHeard)))
				newNode.lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(nodeInfo.lastHeard)))
			} else {
				newNode.firstHeard = Date()
				newNode.lastHeard = Date()
			}
			newNode.snr = nodeInfo.snr
			if nodeInfo.hasUser {

				let newUser = UserEntity(context: context)
				newUser.userId = nodeInfo.num.toHex()
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
				if !nodeInfo.user.publicKey.isEmpty {
					newUser.pkiEncrypted = true
					newUser.publicKey = nodeInfo.user.publicKey
				}
				/// For nodes that have the optional isUnmessagable boolean use that, otherwise excluded roles that are unmessagable by default
				if nodeInfo.user.hasIsUnmessagable {
					newUser.unmessagable = nodeInfo.user.isUnmessagable
				} else {
					let roles = [2, 4, 5, 6, 7, 10, 11]
					let containsRole = roles.contains(Int(newUser.role))
					if containsRole {
						newUser.unmessagable = true
					} else {
						newUser.unmessagable = false
					}}
				newNode.user = newUser
			} else if nodeInfo.num > Constants.minimumNodeNum {
				do {
					let newUser = try createUser(num: Int64(nodeInfo.num), context: context)
					newNode.user = newUser
				} catch CoreDataError.invalidInput(let message) {
					Logger.data.error("Error Creating a new Core Data UserEntity (Invalid Input) from node number: \(nodeInfo.num, privacy: .public) Error:  \(message, privacy: .public)")
				} catch {
					Logger.data.error("Error Creating a new Core Data UserEntity from node number: \(nodeInfo.num, privacy: .public) Error:  \(error.localizedDescription, privacy: .public)")
				}
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
					if !deferSave {
						try context.save()
						Logger.data.info("💾 Saved a new Node Info For: \(String(nodeInfo.num), privacy: .public)")
					}
					return newNode
				} catch {
					context.rollback()
					let nsError = error as NSError
					Logger.data.error("Error Saving Core Data NodeInfoEntity: \(nsError, privacy: .public)")
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
			fetchedNode[0].ignored = nodeInfo.isIgnored
			fetchedNode[0].hopsAway = Int32(nodeInfo.hopsAway)

			if nodeInfo.hasUser {
				if fetchedNode[0].user == nil {
					fetchedNode[0].user = UserEntity(context: context)
				}
				// Set the public key for a user if it is empty, don't update
				if fetchedNode[0].user?.publicKey == nil && !nodeInfo.user.publicKey.isEmpty {
					fetchedNode[0].user?.pkiEncrypted = true
					fetchedNode[0].user?.publicKey = nodeInfo.user.publicKey
				}
				fetchedNode[0].user?.userId = nodeInfo.num.toHex()
				fetchedNode[0].user?.num = Int64(nodeInfo.num)
				fetchedNode[0].user?.numString = String(nodeInfo.num)
				fetchedNode[0].user?.longName = nodeInfo.user.longName
				fetchedNode[0].user?.shortName = nodeInfo.user.shortName
				fetchedNode[0].user?.isLicensed = nodeInfo.user.isLicensed
				fetchedNode[0].user?.role = Int32(nodeInfo.user.role.rawValue)
				fetchedNode[0].user?.hwModel = String(describing: nodeInfo.user.hwModel).uppercased()
				fetchedNode[0].user?.hwModelId = Int32(nodeInfo.user.hwModel.rawValue)
				/// For nodes that have the optional isUnmessagable boolean use that, otherwise excluded roles that are unmessagable by default
				if nodeInfo.user.hasIsUnmessagable {
					fetchedNode[0].user?.unmessagable = nodeInfo.user.isUnmessagable
				} else {
					let roles = [-1, 2, 4, 5, 6, 7, 10, 11]
					let containsRole = roles.contains(Int(fetchedNode[0].user?.role ?? -1))
					if containsRole {
						fetchedNode[0].user?.unmessagable = true
					} else {
						fetchedNode[0].user?.unmessagable = false
					}
				}
				Task {
					Api().loadDeviceHardwareData { (hw: [DeviceHardware]) in
						guard !hw.isEmpty,
							  let firstNode = fetchedNode.first,
							  let user = firstNode.user else {
							Logger.data.error("Error: Required DeviceHardware data is missing or array is empty.")
							return
						}

						let dh = hw.first(where: { $0.hwModel == user.hwModelId })

						if let deviceHardware = dh {
							firstNode.user?.hwDisplayName = deviceHardware.displayName
						} else {
							Logger.data.error("No matching hardware model found for ID: \(user.hwModelId, privacy: .public)")
						}
					}
				}
			} else {
				if fetchedNode[0].user == nil && nodeInfo.num > Constants.minimumNodeNum {
					do {
						let newUser = try createUser(num: Int64(nodeInfo.num), context: context)
						fetchedNode[0].user = newUser
					} catch CoreDataError.invalidInput(let message) {
						Logger.data.error("Error Creating a new Core Data UserEntity on an existing node (Invalid Input) from node number: \(nodeInfo.num, privacy: .public) Error:  \(message, privacy: .public)")
					} catch {
						Logger.data.error("Error Creating a new Core Data UserEntity on an existing node from node number: \(nodeInfo.num, privacy: .public) Error:  \(error.localizedDescription, privacy: .public)")
					}
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
				mutableTelemetries.add(newTelemetry)
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
					if !deferSave {
						try context.save()
						Logger.data.info("💾 [NodeInfo] saved for \(nodeInfo.num.toHex(), privacy: .public)")
					}
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

	if let adminMessage = try? AdminMessage(serializedBytes: packet.decoded.payload) {

		if adminMessage.payloadVariant == AdminMessage.OneOf_PayloadVariant.getCannedMessageModuleMessagesResponse(adminMessage.getCannedMessageModuleMessagesResponse) {

			if let cmmc = try? CannedMessageModuleConfig(serializedBytes: packet.decoded.payload) {
					let logString = String.localizedStringWithFormat("Canned Messages Messages Received For: %@".localized, packet.from.toHex())
					Logger.mesh.info("🥫 \(logString, privacy: .public)")

					let fetchNodeRequest = NodeInfoEntity.fetchRequest()
					fetchNodeRequest.predicate = NSPredicate(format: "num == %lld", Int64(packet.from))

					do {
						let fetchedNode = try context.fetch(fetchNodeRequest)
						if fetchedNode.count == 1 {
							let messages =  String(cmmc.textFormatString())
								.replacingOccurrences(of: "11: ", with: "")
								.replacingOccurrences(of: "\"", with: "")
								.trimmingCharacters(in: .whitespacesAndNewlines)
								.components(separatedBy: "\n").first ?? ""
							fetchedNode[0].cannedMessageConfig?.messages = messages
							do {
								try context.save()
								Logger.data.info("💾 Updated Canned Messages Messages For: \(fetchedNode.first?.num.toHex() ?? "Unknown".localized, privacy: .public)")
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
		} else if adminMessage.payloadVariant == AdminMessage.OneOf_PayloadVariant.getChannelResponse(adminMessage.getChannelResponse) {
			channelPacket(channel: adminMessage.getChannelResponse, fromNum: Int64(packet.from), context: context)
		} else if adminMessage.payloadVariant == AdminMessage.OneOf_PayloadVariant.getDeviceMetadataResponse(adminMessage.getDeviceMetadataResponse) {
			deviceMetadataPacket(metadata: adminMessage.getDeviceMetadataResponse, fromNum: Int64(packet.from), sessionPasskey: adminMessage.sessionPasskey, context: context)
		} else if adminMessage.payloadVariant == AdminMessage.OneOf_PayloadVariant.getConfigResponse(adminMessage.getConfigResponse) {
			let config = adminMessage.getConfigResponse
			if config.payloadVariant == Config.OneOf_PayloadVariant.bluetooth(config.bluetooth) {
				upsertBluetoothConfigPacket(config: config.bluetooth, nodeNum: Int64(packet.from), sessionPasskey: adminMessage.sessionPasskey, context: context)
			} else if config.payloadVariant == Config.OneOf_PayloadVariant.device(config.device) {
				upsertDeviceConfigPacket(config: config.device, nodeNum: Int64(packet.from), sessionPasskey: adminMessage.sessionPasskey, context: context)
			} else if config.payloadVariant == Config.OneOf_PayloadVariant.display(config.display) {
				upsertDisplayConfigPacket(config: config.display, nodeNum: Int64(packet.from), sessionPasskey: adminMessage.sessionPasskey, context: context)
			} else if config.payloadVariant == Config.OneOf_PayloadVariant.lora(config.lora) {
				upsertLoRaConfigPacket(config: config.lora, nodeNum: Int64(packet.from), sessionPasskey: adminMessage.sessionPasskey, context: context)
			} else if config.payloadVariant == Config.OneOf_PayloadVariant.network(config.network) {
				upsertNetworkConfigPacket(config: config.network, nodeNum: Int64(packet.from), sessionPasskey: adminMessage.sessionPasskey, context: context)
			} else if config.payloadVariant == Config.OneOf_PayloadVariant.position(config.position) {
				upsertPositionConfigPacket(config: config.position, nodeNum: Int64(packet.from), sessionPasskey: adminMessage.sessionPasskey, context: context)
			} else if config.payloadVariant == Config.OneOf_PayloadVariant.power(config.power) {
				upsertPowerConfigPacket(config: config.power, nodeNum: Int64(packet.from), sessionPasskey: adminMessage.sessionPasskey, context: context)
			} else if config.payloadVariant == Config.OneOf_PayloadVariant.security(config.security) {
				upsertSecurityConfigPacket(config: config.security, nodeNum: Int64(packet.from), sessionPasskey: adminMessage.sessionPasskey, context: context)
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
			if let rt = try? RTTTLConfig(serializedBytes: packet.decoded.payload) {
				upsertRtttlConfigPacket(ringtone: rt.ringtone, nodeNum: Int64(packet.from), context: context)
			}
		} else {
			Logger.mesh.error("🕸️ MESH PACKET received Admin App UNHANDLED \((try? packet.decoded.jsonString()) ?? "JSON Decode Failure", privacy: .public)")
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
			fetchedMessage[0].relayNode = Int64(packet.relayNode)
			fetchedMessage[0].ackSNR = packet.rxSnr
			if fetchedMessage[0].fromUser != nil {
				fetchedMessage[0].fromUser?.objectWillChange.send()
			}
			do {
				try context.save()
			} catch {
				Logger.data.error("Failed to save admin message response as an ack: \(error.localizedDescription, privacy: .public)")
			}
		}
	} catch {
		Logger.data.error("Failed to fetch admin message by requestID: \(error.localizedDescription, privacy: .public)")
	}
}
func paxCounterPacket (packet: MeshPacket, context: NSManagedObjectContext) {

	let logString = String.localizedStringWithFormat("PAX Counter message received from: %@".localized, String(packet.from))
	Logger.mesh.info("🧑‍🤝‍🧑 \(logString, privacy: .public)")

	let fetchNodeInfoRequest = NodeInfoEntity.fetchRequest()
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(packet.from))

	do {
		let fetchedNode = try context.fetch(fetchNodeInfoRequest)

		if let paxMessage = try? Paxcount(serializedBytes: packet.decoded.payload) {

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
					Logger.data.error("Failed to save pax: \(error.localizedDescription, privacy: .public)")
				}
			} else {
				Logger.data.info("Node Info Not Found")
			}
		}
	} catch {

	}
}

func routingPacket (packet: MeshPacket, connectedNodeNum: Int64, context: NSManagedObjectContext) {

	if let routingMessage = try? Routing(serializedBytes: packet.decoded.payload) {

		let routingError = RoutingError(rawValue: routingMessage.errorReason.rawValue)

		let routingErrorString = routingError?.display ?? "Unknown".localized
		let logString = String.localizedStringWithFormat("Routing received for RequestID: %@ Ack Status: %@".localized, String(packet.decoded.requestID), routingErrorString)
		Logger.mesh.info("🕸️ \(logString, privacy: .public)")

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
				fetchedMessage[0].relayNode = Int64(packet.relayNode)
				fetchedMessage[0].ackError = Int32(routingMessage.errorReason.rawValue)
				if routingMessage.errorReason == Routing.Error.none {
					fetchedMessage[0].receivedACK = true
					fetchedMessage[0].relays += 1
				}
				
				fetchedMessage[0].ackSNR = packet.rxSnr
				if packet.rxTime > 0 {
					fetchedMessage[0].ackTimestamp = Int32(truncatingIfNeeded: packet.rxTime)
				} else {
					fetchedMessage[0].ackTimestamp = Int32(Date().timeIntervalSince1970)
				}

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
			Logger.data.info("💾 ACK Saved for Message: \(packet.decoded.requestID, privacy: .public)")
		} catch {
			context.rollback()
			let nsError = error as NSError
			Logger.data.error("Error Saving ACK for message: \(packet.id, privacy: .public) Error: \(nsError, privacy: .public)")
		}
	}
}

func telemetryPacket(packet: MeshPacket, connectedNode: Int64, context: NSManagedObjectContext) {
	Task { @MainActor in
		if let telemetryMessage = try? Telemetry(serializedBytes: packet.decoded.payload) {
			if telemetryMessage.variant != Telemetry.OneOf_Variant.deviceMetrics(telemetryMessage.deviceMetrics) && telemetryMessage.variant != Telemetry.OneOf_Variant.environmentMetrics(telemetryMessage.environmentMetrics) && telemetryMessage.variant != Telemetry.OneOf_Variant.localStats(telemetryMessage.localStats) && telemetryMessage.variant != Telemetry.OneOf_Variant.powerMetrics(telemetryMessage.powerMetrics) {
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
						Logger.data.info("📈 [Telemetry] Device Metrics Received for Node: \(packet.from.toHex(), privacy: .public)")
						telemetry.airUtilTx = telemetryMessage.deviceMetrics.hasAirUtilTx.then(telemetryMessage.deviceMetrics.airUtilTx)
						telemetry.channelUtilization = telemetryMessage.deviceMetrics.hasChannelUtilization.then(telemetryMessage.deviceMetrics.channelUtilization)
						telemetry.batteryLevel = telemetryMessage.deviceMetrics.hasBatteryLevel.then(Int32(telemetryMessage.deviceMetrics.batteryLevel))
						telemetry.voltage = telemetryMessage.deviceMetrics.hasVoltage.then(telemetryMessage.deviceMetrics.voltage)
						telemetry.uptimeSeconds = telemetryMessage.deviceMetrics.hasUptimeSeconds.then(Int32(telemetryMessage.deviceMetrics.uptimeSeconds))
						telemetry.metricsType = 0
						Logger.statistics.info("📈 [Mesh Statistics] Channel Utilization: \(telemetryMessage.deviceMetrics.channelUtilization, privacy: .public) Airtime: \(telemetryMessage.deviceMetrics.airUtilTx, privacy: .public) for Node: \(packet.from.toHex(), privacy: .public)")
					} else if telemetryMessage.variant == Telemetry.OneOf_Variant.environmentMetrics(telemetryMessage.environmentMetrics) {
						// Environment Metrics
						Logger.data.info("📈 [Telemetry] Environment Metrics Received for Node: \(packet.from.toHex(), privacy: .public)")
						telemetry.barometricPressure = telemetryMessage.environmentMetrics.hasBarometricPressure.then(telemetryMessage.environmentMetrics.barometricPressure)
						telemetry.iaq = telemetryMessage.environmentMetrics.hasIaq.then(Int32(truncatingIfNeeded: telemetryMessage.environmentMetrics.iaq))
						telemetry.gasResistance = telemetryMessage.environmentMetrics.hasGasResistance.then(telemetryMessage.environmentMetrics.gasResistance)
						telemetry.relativeHumidity = telemetryMessage.environmentMetrics.hasRelativeHumidity.then(telemetryMessage.environmentMetrics.relativeHumidity)
						telemetry.temperature = telemetryMessage.environmentMetrics.hasTemperature.then(telemetryMessage.environmentMetrics.temperature)
						telemetry.current = telemetryMessage.environmentMetrics.hasCurrent.then(telemetryMessage.environmentMetrics.current)
						telemetry.voltage = telemetryMessage.environmentMetrics.hasVoltage.then(telemetryMessage.environmentMetrics.voltage)
						telemetry.weight = telemetryMessage.environmentMetrics.hasWeight.then(telemetryMessage.environmentMetrics.weight)
						telemetry.distance = telemetryMessage.environmentMetrics.hasDistance.then(telemetryMessage.environmentMetrics.distance)
						telemetry.windSpeed = telemetryMessage.environmentMetrics.hasWindSpeed.then(telemetryMessage.environmentMetrics.windSpeed)
						telemetry.windGust = telemetryMessage.environmentMetrics.hasWindGust.then(telemetryMessage.environmentMetrics.windGust)
						telemetry.windLull = telemetryMessage.environmentMetrics.hasWindLull.then(telemetryMessage.environmentMetrics.windLull)
						telemetry.windDirection = telemetryMessage.environmentMetrics.hasWindDirection.then(Int32(truncatingIfNeeded: telemetryMessage.environmentMetrics.windDirection))
						telemetry.irLux = telemetryMessage.environmentMetrics.hasIrLux.then(telemetryMessage.environmentMetrics.irLux)
						telemetry.lux = telemetryMessage.environmentMetrics.hasLux.then(telemetryMessage.environmentMetrics.lux)
						telemetry.whiteLux = telemetryMessage.environmentMetrics.hasWhiteLux.then(telemetryMessage.environmentMetrics.whiteLux)
						telemetry.uvLux = telemetryMessage.environmentMetrics.hasUvLux.then(telemetryMessage.environmentMetrics.uvLux)
						telemetry.radiation = telemetryMessage.environmentMetrics.hasRadiation.then(telemetryMessage.environmentMetrics.radiation)
						telemetry.rainfall1H = telemetryMessage.environmentMetrics.hasRainfall1H.then(telemetryMessage.environmentMetrics.rainfall1H)
						telemetry.rainfall24H = telemetryMessage.environmentMetrics.hasRainfall24H.then(telemetryMessage.environmentMetrics.rainfall24H)
						telemetry.soilTemperature = telemetryMessage.environmentMetrics.hasSoilTemperature.then(telemetryMessage.environmentMetrics.soilTemperature)
						telemetry.soilMoisture = telemetryMessage.environmentMetrics.hasSoilMoisture.then(telemetryMessage.environmentMetrics.soilMoisture)
						telemetry.metricsType = 1
					} else if telemetryMessage.variant == Telemetry.OneOf_Variant.localStats(telemetryMessage.localStats) {
						// Local Stats for Live activity
						telemetry.uptimeSeconds = Int32(telemetryMessage.localStats.uptimeSeconds)
						telemetry.channelUtilization = telemetryMessage.localStats.channelUtilization
						telemetry.airUtilTx = telemetryMessage.localStats.airUtilTx
						telemetry.numPacketsTx = Int32(truncatingIfNeeded: telemetryMessage.localStats.numPacketsTx)
						telemetry.numPacketsRx = Int32(truncatingIfNeeded: telemetryMessage.localStats.numPacketsRx)
						telemetry.numPacketsRxBad = Int32(truncatingIfNeeded: telemetryMessage.localStats.numPacketsRxBad)
						telemetry.numRxDupe = Int32(truncatingIfNeeded: telemetryMessage.localStats.numRxDupe)
						telemetry.numTxRelay = Int32(truncatingIfNeeded: telemetryMessage.localStats.numTxRelay)
						telemetry.numTxRelayCanceled = Int32(truncatingIfNeeded: telemetryMessage.localStats.numTxRelayCanceled)
						telemetry.numOnlineNodes = Int32(truncatingIfNeeded: telemetryMessage.localStats.numOnlineNodes)
						telemetry.numTotalNodes = Int32(truncatingIfNeeded: telemetryMessage.localStats.numTotalNodes)
						telemetry.metricsType = 4
						Logger.statistics.info("📈 [Mesh Statistics] Channel Utilization: \(telemetryMessage.localStats.channelUtilization, privacy: .public) Airtime: \(telemetryMessage.localStats.airUtilTx, privacy: .public) Packets Sent: \(telemetryMessage.localStats.numPacketsTx, privacy: .public) Packets Received: \(telemetryMessage.localStats.numPacketsRx, privacy: .public) Bad Packets Received: \(telemetryMessage.localStats.numPacketsRxBad, privacy: .public) Nodes Online: \(telemetryMessage.localStats.numOnlineNodes, privacy: .public) of \(telemetryMessage.localStats.numTotalNodes, privacy: .public) nodes for Node: \(packet.from.toHex(), privacy: .public)")
					} else if telemetryMessage.variant == Telemetry.OneOf_Variant.powerMetrics(telemetryMessage.powerMetrics) {
						Logger.data.info("📈 [Telemetry] Power Metrics Received for Node: \(packet.from.toHex(), privacy: .public)")
						telemetry.powerCh1Voltage = telemetryMessage.powerMetrics.hasCh1Voltage.then(telemetryMessage.powerMetrics.ch1Voltage)
						telemetry.powerCh1Current = telemetryMessage.powerMetrics.hasCh1Current.then(telemetryMessage.powerMetrics.ch1Current)
						telemetry.powerCh2Voltage = telemetryMessage.powerMetrics.hasCh2Voltage.then(telemetryMessage.powerMetrics.ch2Voltage)
						telemetry.powerCh2Current = telemetryMessage.powerMetrics.hasCh2Current.then(telemetryMessage.powerMetrics.ch2Current)
						telemetry.powerCh3Voltage = telemetryMessage.powerMetrics.hasCh3Voltage.then(telemetryMessage.powerMetrics.ch3Voltage)
						telemetry.powerCh3Current = telemetryMessage.powerMetrics.hasCh3Current.then(telemetryMessage.powerMetrics.ch3Current)
						telemetry.metricsType = 2
					}
					telemetry.snr = packet.rxSnr
					telemetry.rssi = packet.rxRssi
					telemetry.time = Date(timeIntervalSince1970: TimeInterval(Int64(truncatingIfNeeded: telemetryMessage.time)))
					guard let mutableTelemetries = fetchedNode[0].telemetries!.mutableCopy() as? NSMutableOrderedSet else {
						return
					}
					mutableTelemetries.add(telemetry)
					if packet.rxTime > 0 {
						fetchedNode[0].lastHeard = Date(timeIntervalSince1970: TimeInterval(packet.rxTime))
					} else {
						fetchedNode[0].lastHeard = Date()
					}
					fetchedNode[0].telemetries = mutableTelemetries.copy() as? NSOrderedSet
				}
				try context.save()
				Logger.data.info("💾 [TelemetryEntity] of type \(MetricsTypes(rawValue: Int(telemetry.metricsType))?.name ?? "Unknown Metrics Type", privacy: .public) Saved for Node: \(packet.from.toHex(), privacy: .public)")
				if telemetry.metricsType == 0 {
					// Connected Device Metrics
					// ------------------------
					// Low Battery notification
					if connectedNode == Int64(packet.from) {
						let batteryLevel = telemetry.batteryLevel ?? 0
						if UserDefaults.lowBatteryNotifications && batteryLevel > 0 && batteryLevel < 4 {
							let manager = LocalNotificationManager()
							manager.notifications = [
								Notification(
									id: ("notification.id.\(UUID().uuidString)"),
									title: "Critically Low Battery!",
									subtitle: "AKA \(telemetry.nodeTelemetry?.user?.shortName ?? "UNK")",
									content: "Time to charge your radio, there is \(telemetry.batteryLevel?.formatted(.number) ?? Constants.nilValueIndicator)% battery remaining.",
									target: "nodes",
									path: "meshtastic:///nodes?nodenum=\(telemetry.nodeTelemetry?.num ?? 0)"
								)
							]
							manager.schedule()
						}
					}
				} else if telemetry.metricsType == 4 {
					// Update our live activity if there is one running, not available on mac
#if !targetEnvironment(macCatalyst)
#if canImport(ActivityKit)

					let fifteenMinutesLater = Calendar.current.date(byAdding: .minute, value: (Int(15) ), to: Date())!
					let date = Date.now...fifteenMinutesLater
					let updatedMeshStatus = MeshActivityAttributes.MeshActivityStatus(uptimeSeconds: telemetry.uptimeSeconds.map { UInt32($0) },
																					  channelUtilization: telemetry.channelUtilization,
																					  airtime: telemetry.airUtilTx,
																					  sentPackets: UInt32(telemetry.numPacketsTx),
																					  receivedPackets: UInt32(telemetry.numPacketsRx),
																					  badReceivedPackets: UInt32(telemetry.numPacketsRxBad),
																					  dupeReceivedPackets: UInt32(telemetry.numRxDupe),
																					  packetsSentRelay: UInt32(telemetry.numTxRelay),
																					  packetsCanceledRelay: UInt32(telemetry.numTxRelayCanceled),
																					  nodesOnline: UInt32(telemetry.numOnlineNodes),
																					  totalNodes: UInt32(telemetry.numTotalNodes),
																					  timerRange: date)

					let alertConfiguration = AlertConfiguration(title: "Mesh activity update", body: "Updated Node Stats Data.", sound: .default)
					let updatedContent = ActivityContent(state: updatedMeshStatus, staleDate: nil)

					let meshActivity = Activity<MeshActivityAttributes>.activities.first(where: { $0.attributes.nodeNum == connectedNode })
					if meshActivity != nil {
						Task {
							// await meshActivity?.update(updatedContent, alertConfiguration: alertConfiguration)
							await meshActivity?.update(updatedContent)
							Logger.services.debug("Updated live activity.")
						}
					}
#endif
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
}

func textMessageAppPacket(
	packet: MeshPacket,
	wantRangeTestPackets: Bool,
	critical: Bool = false,
	connectedNode: Int64,
	storeForward: Bool = false,
	context: NSManagedObjectContext,
	appState: AppState?
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
		if let storeAndForwardMessage = try? StoreAndForward(serializedBytes: packet.decoded.payload) {
			messageText = String(bytes: storeAndForwardMessage.text, encoding: .utf8)
			if storeAndForwardMessage.rr == .routerTextBroadcast {
				storeForwardBroadcast = true
			}
		}
	}

	if messageText?.count ?? 0 > 0 {
		Logger.mesh.info("💬 \("Message received from the text message app.".localized, privacy: .public)")
		let messageUsers = UserEntity.fetchRequest()
		messageUsers.predicate = NSPredicate(format: "num IN %@", [packet.to, packet.from])
		do {
			let fetchedUsers = try context.fetch(messageUsers)
			let newMessage = MessageEntity(context: context)
			newMessage.messageId = Int64(packet.id)
			if packet.rxTime > 0 {
				newMessage.messageTimestamp = Int32(bitPattern: packet.rxTime)
			} else {
				newMessage.messageTimestamp = Int32(Date().timeIntervalSince1970)
			}
			if packet.relayNode != 0 {
				newMessage.relayNode = Int64(packet.relayNode)
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
			// Updated logic for handling toUser
				if fetchedUsers.first(where: { $0.num == packet.to }) != nil && packet.to != Constants.maximumNodeNum {
					if !storeForwardBroadcast {
						newMessage.toUser = fetchedUsers.first(where: { $0.num == packet.to })
					} else if storeForwardBroadcast {
						// For S&F broadcast messages, treat as a channel message (not a DM)
						newMessage.toUser = nil
					} else {
						do {
							let newUser = try createUser(num: Int64(truncatingIfNeeded: packet.to), context: context)
							newMessage.toUser = newUser
						} catch CoreDataError.invalidInput(let message) {
							Logger.data.error("Error Creating a new Core Data UserEntity (Invalid Input) from node number: \(packet.to, privacy: .public) Error:  \(message, privacy: .public)")
						} catch {
							Logger.data.error("Error Creating a new Core Data UserEntity from node number: \(packet.to, privacy: .public) Error:  \(error.localizedDescription, privacy: .public)")
						}
					}
				}
				if fetchedUsers.first(where: { $0.num == packet.from }) != nil {
					newMessage.fromUser = fetchedUsers.first(where: { $0.num == packet.from })
					/// Set the public key for the message
					if newMessage.fromUser?.pkiEncrypted ?? false && packet.pkiEncrypted {
						newMessage.pkiEncrypted = true
						newMessage.publicKey = packet.publicKey
					}
					
					/// Check for key mismatch
					if let nodeKey = newMessage.fromUser?.publicKey {
						if newMessage.toUser != nil && packet.pkiEncrypted && !packet.publicKey.isEmpty {
							if nodeKey != newMessage.publicKey {
								newMessage.fromUser?.keyMatch = false
								newMessage.fromUser?.newPublicKey = newMessage.publicKey
								let nodeKey = String(nodeKey.base64EncodedString()).prefix(8)
								let messageKey = String(newMessage.publicKey?.base64EncodedString() ?? "No Key").prefix(8)
								Logger.data.error("🔑 Key mismatch original key: \(nodeKey, privacy: .public) . . . new key: \(messageKey, privacy: .public) . . .")
							}
						}
					} else if packet.pkiEncrypted {
						/// We have no key, set it if it is not empty
						if !packet.publicKey.isEmpty {
							newMessage.fromUser?.pkiEncrypted = true
							newMessage.fromUser?.publicKey = packet.publicKey
						}
					}
				} else {
					/// Make a new from user if they are unknown
					do {
						let newUser = try createUser(num: Int64(truncatingIfNeeded: packet.from), context: context)
						let newNode = NodeInfoEntity(context: context)
						newNode.id = Int64(newUser.num)
						newNode.num = Int64(newUser.num)
						newNode.user = newUser
						newMessage.fromUser = newUser
					} catch CoreDataError.invalidInput(let message) {
						Logger.data.error("Error Creating a new Core Data UserEntity (Invalid Input) from node number: \(packet.from, privacy: .public) Error:  \(message, privacy: .public)")
					} catch {
						Logger.data.error("Error Creating a new Core Data UserEntity from node number: \(packet.from, privacy: .public) Error:  \(error.localizedDescription, privacy: .public)")
					}
				}
			if packet.rxTime > 0 {
				newMessage.fromUser?.userNode?.lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(packet.rxTime)))
			} else {
				newMessage.fromUser?.userNode?.lastHeard = Date()
			}
			newMessage.messagePayload = messageText
			newMessage.messagePayloadMarkdown = generateMessageMarkdown(message: messageText!)
			if packet.to != Constants.maximumNodeNum && newMessage.fromUser != nil {
				newMessage.fromUser?.lastMessage = Date()
			}
			var messageSaved = false
			do {
				try context.save()
				Logger.data.info("💾 Saved a new message for \(newMessage.messageId, privacy: .public)")
				messageSaved = true
			} catch {
				context.rollback()
				let nsError = error as NSError
				Logger.data.error("Failed to save new MessageEntity \(nsError, privacy: .public)")
			}
			// Send notifications if the message saved properly to core data
			if messageSaved {
				if packet.decoded.portnum == PortNum.detectionSensorApp && !UserDefaults.enableDetectionNotifications {
					return
				}
				if newMessage.fromUser != nil && newMessage.toUser != nil {
					// Set Unread Message Indicators
					if packet.to == connectedNode {
						let unreadCount = newMessage.toUser?.unreadMessages(context: context, skipLastMessageCheck: true) ?? 0 // skipLastMessageCheck=true because we don't update lastMessage on our own connected node
						Task { @MainActor in
							appState?.unreadDirectMessages = unreadCount
						}
					}
					if !(newMessage.fromUser?.mute ?? false) && newMessage.isEmoji == false {
						// Create an iOS Notification for the received DM message
						let manager = LocalNotificationManager()
						manager.notifications = [
							Notification(
								id: ("notification.id.\(newMessage.messageId)"),
								title: "\(newMessage.fromUser?.longName ?? "Unknown".localized)",
								subtitle: "AKA \(newMessage.fromUser?.shortName ?? "?")",
								content: messageText!,
								target: "messages",
								path: "meshtastic:///messages?userNum=\(newMessage.fromUser?.num ?? 0)&messageId=\(newMessage.isEmoji ? newMessage.replyID : newMessage.messageId)",
								messageId: newMessage.messageId,
								channel: newMessage.channel,
								userNum: Int64(packet.from),
								critical: critical
							)
						]
						manager.schedule()
						Logger.services.debug("iOS Notification Scheduled for text message from \(newMessage.fromUser?.longName ?? "Unknown".localized, privacy: .public)")
					}
				} else if newMessage.fromUser != nil && newMessage.toUser == nil {
					let fetchMyInfoRequest = MyInfoEntity.fetchRequest()
					fetchMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", Int64(connectedNode))
					do {
						let fetchedMyInfo = try context.fetch(fetchMyInfoRequest)
						if !fetchedMyInfo.isEmpty {
							appState?.unreadChannelMessages = fetchedMyInfo[0].unreadMessages(context: context)
							for channel in (fetchedMyInfo[0].channels?.array ?? []) as? [ChannelEntity] ?? [] {
								if channel.index == newMessage.channel {
									context.refresh(channel, mergeChanges: true)
								}
								if channel.index == newMessage.channel && !channel.mute && UserDefaults.channelMessageNotifications && newMessage.isEmoji == false {
									// Create an iOS Notification for the received channel message
									let manager = LocalNotificationManager()
									manager.notifications = [
										Notification(
											id: ("notification.id.\(newMessage.messageId)"),
											title: "\(newMessage.fromUser?.longName ?? "Unknown".localized)",
											subtitle: "AKA \(newMessage.fromUser?.shortName ?? "?")",
											content: messageText!,
											target: "messages",
											path: "meshtastic:///messages?channelId=\(newMessage.channel)&messageId=\(newMessage.isEmoji ? newMessage.replyID : newMessage.messageId)",
											messageId: newMessage.messageId,
											channel: newMessage.channel,
											userNum: Int64(newMessage.fromUser?.userId ?? "0"),
											critical: critical
										)
									]
									manager.schedule()
									Logger.services.debug("iOS Notification Scheduled for text message from \(newMessage.fromUser?.longName ?? "Unknown".localized, privacy: .public)")
								}
							}
						}
					} catch {
						// Handle error
					}
				}
			}
		} catch {
			Logger.data.error("Fetch Message To and From Users Error")
		}
	}
}

func waypointPacket (packet: MeshPacket, context: NSManagedObjectContext) {

	let logString = String.localizedStringWithFormat("Waypoint Packet received from node: %@".localized, String(packet.from))
	Logger.mesh.info("📍 \(logString, privacy: .public)")

	do {
		if let waypointMessage = try? Waypoint(serializedBytes: packet.decoded.payload) {
			// Fetch waypoint by waypointMessage.id, not packet.id
			let fetchWaypointRequest = WaypointEntity.fetchRequest()
			fetchWaypointRequest.predicate = NSPredicate(format: "id == %lld", Int64(waypointMessage.id))

			let fetchedWaypoint = try context.fetch(fetchWaypointRequest)
			// Fetch the node info to get the short name
			var nodeShortName: String = "?"
			let fetchNodeRequest = NodeInfoEntity.fetchRequest()
			fetchNodeRequest.predicate = NSPredicate(format: "num == %lld", Int64(packet.from))
			do {
				let fetchedNode = try context.fetch(fetchNodeRequest)
				if let node = fetchedNode.first, let user = node.user {
				nodeShortName = user.shortName ?? node.user?.userId ?? String(packet.from.toHex())
				}
			} catch {
				Logger.data.error("Failed to fetch NodeInfoEntity for node \(packet.from.toHex(), privacy: .public): \(error)")
			}
			if fetchedWaypoint.isEmpty {
				// Create a new waypoint
				let waypoint = WaypointEntity(context: context)
				waypoint.id = Int64(waypointMessage.id) // Use waypointMessage.id
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
					Logger.data.info("💾 Added Node Waypoint App Packet For: \(waypoint.id, privacy: .public)")
					let manager = LocalNotificationManager()
					let icon = String(UnicodeScalar(Int(waypoint.icon)) ?? "📍")
					let latitude = Double(waypoint.latitudeI) / 1e7
					let longitude = Double(waypoint.longitudeI) / 1e7
					manager.notifications = [
						Notification(
							id: ("notification.id.\(waypoint.id)"),
							title: "New Waypoint From \(nodeShortName)",
							subtitle: "\(icon) \(waypoint.name ?? "Dropped Pin")",
							content: "\(waypoint.longDescription ?? "\(latitude), \(longitude)")",
							target: "map",
							path: "meshtastic:///map?waypointid=\(waypoint.id)"
						)
					]
					Logger.data.debug("meshtastic:///map?waypointid=\(waypoint.id, privacy: .public)")
					manager.schedule()
				} catch {
					context.rollback()
					let nsError = error as NSError
					Logger.data.error("Error Saving WaypointEntity from WAYPOINT_APP \(nsError, privacy: .public)")
				}
			} else {
				// Update existing waypoint
				let existingWaypoint = fetchedWaypoint[0]
				if existingWaypoint.locked == 0 || existingWaypoint.locked == packet.from {
					let currentTime = Int64(Date().timeIntervalSince1970)
					if waypointMessage.expire > 0 && waypointMessage.expire <= currentTime {
						context.delete(existingWaypoint)
						do {
							try context.save()
							Logger.data.info("💾 Deleted a waypoint")
						} catch {
							context.rollback()
							let nsError = error as NSError
							Logger.data.error("Error Saving WaypointEntity from WAYPOINT_APP \(nsError, privacy: .public)")
						}
					} else {
						existingWaypoint.name = waypointMessage.name
						existingWaypoint.longDescription = waypointMessage.description_p
						existingWaypoint.latitudeI = waypointMessage.latitudeI
						existingWaypoint.longitudeI = waypointMessage.longitudeI
						existingWaypoint.icon = Int64(waypointMessage.icon)
						existingWaypoint.locked = Int64(waypointMessage.lockedTo)
						if waypointMessage.expire >= 1 {
							existingWaypoint.expire = Date(timeIntervalSince1970: TimeInterval(Int64(waypointMessage.expire)))
						} else {
							existingWaypoint.expire = nil
						}
						existingWaypoint.lastUpdated = Date()
						do {
							try context.save()
							Logger.data.info("💾 Updated Node Waypoint App Packet For: \(existingWaypoint.id, privacy: .public)")
						} catch {
							context.rollback()
							let nsError = error as NSError
							Logger.data.error("Error Saving WaypointEntity from WAYPOINT_APP \(nsError, privacy: .public)")
						}
					}
				}
			}
		}
	} catch {
		Logger.mesh.error("Error Deserializing WAYPOINT_APP packet.")
	}
}
