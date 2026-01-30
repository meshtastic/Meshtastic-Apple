//
//  AccessoryManager+FromRadio.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/18/25.
//

import Foundation
import MeshtasticProtobufs
import CocoaMQTT
import OSLog

extension AccessoryManager {

	func handleMqttClientProxyMessage(_ mqttClientProxyMessage: MqttClientProxyMessage) {
		Logger.services.info("handleMqttClientProxyMessage: \(mqttClientProxyMessage.debugDescription)")
		let message = CocoaMQTTMessage(topic: mqttClientProxyMessage.topic,
									   payload: [UInt8](mqttClientProxyMessage.data),
									   retained: mqttClientProxyMessage.retained)
		MqttClientProxyManager.shared.mqttClientProxy?.publish(message)
	}

	func handleClientNotification(_ clientNotification: ClientNotification) {
		Logger.services.info("handleClientNotification: \(clientNotification.debugDescription)")
		var path = "meshtastic:///settings/debugLogs"
		if clientNotification.hasReplyID {
			/// Set Sent bool on TraceRouteEntity to false if we got rate limited
			if clientNotification.message.starts(with: "TraceRoute") {
				// CoreData operation happens on the Main Actor

				let traceRoute = getTraceRoute(id: Int64(clientNotification.replyID), context: context)
				traceRoute?.sent = false
				do {
					try context.save()
					Logger.data.info("💾 [TraceRouteEntity] Trace Route Rate Limited")
				} catch {
					context.rollback()
					let nsError = error as NSError
					Logger.data.error("💥 [TraceRouteEntity] Error Updating Core Data: \(nsError, privacy: .public)")
				}

			}

			switch clientNotification.payloadVariant {
			case .lowEntropyKey, .duplicatedPublicKey:
				path = "meshtastic:///settings/security"
			default:
				break
			}
		}

		// TODO: Look at this to see if LocationManager should be singleton
		let manager = LocalNotificationManager()
		manager.notifications = [
			Notification(
				id: UUID().uuidString,
				title: "Firmware Notification".localized,
				subtitle: "\(clientNotification.level)".capitalized,
				content: clientNotification.message,
				target: "settings",
				path: path
			)
		]
		manager.schedule()
		Logger.services.error("⚠️ Client Notification: \(clientNotification.message, privacy: .public)")
	}

	func handleMyInfo(_ myNodeInfo: MyNodeInfo) async {
		// TODO: this works for connections like BLE that have a uniqueId, but what about ones like serial?
		guard let connectedDeviceId = activeConnection?.device.id.uuidString else {
			Logger.services.error("⚠️ Failed to decode MyInfo, no connected device ID")
			return
		}
		Logger.services.info("handleMyInfo: \(myNodeInfo.debugDescription)")

		updateDevice(key: \.num, value: Int64(myNodeInfo.myNodeNum))

		if let myInfoId = await MeshPackets.shared.myInfoPacket(myInfo: myNodeInfo, peripheralId: connectedDeviceId),
		   let myInfo = try? context.existingObject(with: myInfoId) as? MyInfoEntity {
			if let bleName = myInfo.bleName {
				updateDevice(key: \.name, value: bleName)
				updateDevice(key: \.longName, value: bleName)
			}
			
			if myNodeInfo.nodedbCount > 0 {
				expectedNodeDBSize = Int(myNodeInfo.nodedbCount)
			}
			
			UserDefaults.preferredPeripheralNum = Int(myInfo.myNodeNum)
			let newConnection = Int64(UserDefaults.preferredPeripheralNum) != Int64(myInfo.myNodeNum)
			if newConnection {
				// Onboard a new device connection here
			}
		}
		tryClearExistingChannels()

		// Initialize TAK bridge for TAK integration
		initializeTAKBridge()
	}

	func handleNodeInfo(_ nodeInfo: NodeInfo) async {
		if let continuation = self.firstDatabaseNodeInfoContinuation {
			continuation.resume()
			self.firstDatabaseNodeInfoContinuation = nil
		}
		
		guard nodeInfo.num > 0 else {
			Logger.services.error("NodeInfo packet with a zero nodeNum")
			return
		}

		// Check if we're in database retrieval mode to defer saves for performance
		// Commented out: No need to defer save when nodeInfoPacket is now happening off the main thread
		// let isRetrievingDatabase = if case .retrievingDatabase = self.state { true } else { false }
		
		// TODO: nodeInfoPacket's channel: parameter is not used
		// deferSave hard coded: No need to defer save when nodeInfoPacket is now happening off the main thread
		if let nodeInfoId = await MeshPackets.shared.nodeInfoPacket(nodeInfo: nodeInfo, channel: 0, deferSave: false),
		   let nodeInfo = try? context.existingObject(with: nodeInfoId) as? NodeInfoEntity {
			if let activeDevice = activeConnection?.device, activeDevice.num == nodeInfo.num {
				if let user = nodeInfo.user {
					updateDevice(deviceId: activeDevice.id, key: \.shortName, value: user.shortName ?? "?")
					updateDevice(deviceId: activeDevice.id, key: \.longName, value: user.longName ?? "Unknown".localized)
					updateDevice(deviceId: activeDevice.id, key: \.hardwareModel, value: user.hwModel)
					
					if activeDevice.isManualConnection {
						// We just received a NodeInfo for the currently connected node and this is a
						// manual connection.  Update the metadata for the device entry in UserDefaults
						// with this information for better display later
						ManualConnectionList.shared.updateDevice(deviceId: activeDevice.id, key: \.shortName, value: user.shortName)
						ManualConnectionList.shared.updateDevice(deviceId: activeDevice.id, key: \.longName, value: user.longName)
						ManualConnectionList.shared.updateDevice(deviceId: activeDevice.id, key: \.hardwareModel, value: user.hwModel)
					}
				}
			}
		}
		
		// Bump the nodeCount
		if case let .retrievingDatabase(nodeCount: nodeCount) = self.state {
			updateState(.retrievingDatabase(nodeCount: nodeCount+1))
		}

	}

	func handleChannel(_ channel: Channel) async {
		guard let deviceNum = activeConnection?.device.num else {
			Logger.data.error("Attempt to process channel information when no connected device.")
			return
		}

		await MeshPackets.shared.channelPacket(channel: channel, fromNum: Int64(truncatingIfNeeded: deviceNum))

	}

	func handleConfig(_ config: Config) async {
		guard let device = activeConnection?.device, let deviceNum = device.num, let longName = device.longName else {
			Logger.data.error("Attempt to process channel information when no connected device.")
			return
		}

		// Local config parses out the variants.  Should we do that here maybe?
		await MeshPackets.shared.localConfig(config: config, nodeNum: Int64(truncatingIfNeeded: deviceNum), nodeLongName: longName)

		// Handle Timezone
		if config.payloadVariant == Config.OneOf_PayloadVariant.device(config.device) {
			var dc = config.device
			if dc.tzdef.isEmpty {
				dc.tzdef =  TimeZone.current.posixDescription
				Task {
					try? await saveTimeZone(config: dc, user: deviceNum)
				}
			}
		}
	}

	func handleModuleConfig(_ moduleConfigPacket: ModuleConfig) async {
		guard let device = activeConnection?.device, let deviceNum = device.num, let longName = device.longName else {
			Logger.services.error("Attempt to process channel information when no connected device.")
			return
		}
		await MeshPackets.shared.moduleConfig(config: moduleConfigPacket, nodeNum: Int64(truncatingIfNeeded: deviceNum), nodeLongName: longName)
		// Get Canned Message Message List if the Module is Canned Messages
		if moduleConfigPacket.payloadVariant == ModuleConfig.OneOf_PayloadVariant.cannedMessage(moduleConfigPacket.cannedMessage) {
			try? getCannedMessageModuleMessages(destNum: deviceNum, wantResponse: true)
		}
		// Get the Ringtone if the Module is External Notifications
		if moduleConfigPacket.payloadVariant == ModuleConfig.OneOf_PayloadVariant.externalNotification(moduleConfigPacket.externalNotification) {
			try? getRingtone(destNum: deviceNum, wantResponse: true)
		}
	}

	func handleDeviceMetadata(_ metadata: DeviceMetadata) async {
		// Note: moved firmware version check to be inline with connection process
		guard let device = activeConnection?.device, let deviceNum = device.num else {
			Logger.services.error("Attempt to process device metadata information when no connected device.")
			return
		}

		Logger.transport.debug("[Version] handleDeviceMetadata returned version: \(metadata.firmwareVersion)")

		updateDevice(key: \.firmwareVersion, value: metadata.firmwareVersion)

		await MeshPackets.shared.deviceMetadataPacket(metadata: metadata, fromNum: deviceNum)
	}

	internal func tryClearExistingChannels() {
		guard let device = activeConnection?.device, let deviceNum = device.num else {
			Logger.services.error("Attempt to clear existing channels when no connected device.")
			return
		}

		// Before we get started delete the existing channels from the myNodeInfo
		let fetchMyInfoRequest = MyInfoEntity.fetchRequest()
		fetchMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", Int64(deviceNum))

		do {
			let fetchedMyInfo = try context.fetch(fetchMyInfoRequest)
			if fetchedMyInfo.count == 1 {
				let mutableChannels = fetchedMyInfo[0].channels?.mutableCopy() as? NSMutableOrderedSet
				mutableChannels?.removeAllObjects()
				fetchedMyInfo[0].channels = mutableChannels
				do {
					try context.save()
				} catch {
					Logger.data.error("Failed to clear existing channels from local app database: \(error.localizedDescription, privacy: .public)")
				}
			}
		} catch {
			Logger.data.error("Failed to find a node MyInfo to save these channels to: \(error.localizedDescription, privacy: .public)")
		}

	}

	func handleTextMessageAppPacket(_ packet: MeshPacket) async {
		guard let device = activeConnection?.device, let deviceNum = device.num else {
			Logger.services.error("Attempt to handle text message when no connected device.")
			return
		}

		await MeshPackets.shared.textMessageAppPacket(
			packet: packet,
			wantRangeTestPackets: wantRangeTestPackets,
			connectedNode: deviceNum,
			appState: appState
		)

	}

	func storeAndForwardPacket(packet: MeshPacket, connectedNodeNum: Int64) {
		if let storeAndForwardMessage = try? StoreAndForward(serializedBytes: packet.decoded.payload) {
			// Handle each of the store and forward request / response messages
			switch storeAndForwardMessage.rr {
			case .unset:
				Logger.mesh.info("\("📮 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")")
			case .routerError:
				Logger.mesh.info("\("☠️ Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")")
			case .routerHeartbeat:
				/// When we get a router heartbeat we know there is a store and forward node on the network
				/// Check if it is the primary S&F Router and save the timestamp of the last heartbeat so that we can show the request message history menu item on node long press if the router has been seen recently
				if storeAndForwardMessage.heartbeat.secondary == 0 {

					guard let routerNode = getNodeInfo(id: Int64(packet.from), context: context) else {
						return
					}
					if routerNode.storeForwardConfig != nil {
						routerNode.storeForwardConfig?.enabled = true
						routerNode.storeForwardConfig?.isRouter = storeAndForwardMessage.heartbeat.secondary == 0
						routerNode.storeForwardConfig?.lastHeartbeat = Date()
					} else {
						let newConfig = StoreForwardConfigEntity(context: context)
						newConfig.enabled = true
						newConfig.isRouter = storeAndForwardMessage.heartbeat.secondary == 0
						newConfig.lastHeartbeat = Date()
						routerNode.storeForwardConfig = newConfig
					}

					do {
						try context.save()
					} catch {
						context.rollback()
						Logger.data.error("Save Store and Forward Router Error")
					}
				}
				Logger.mesh.info("\("💓 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")")
			case .routerPing:
				Logger.mesh.info("\("🏓 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")")
			case .routerPong:
				Logger.mesh.info("\("🏓 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")")
			case .routerBusy:
				Logger.mesh.info("\("🐝 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")")
			case .routerHistory:
				/// Set the Router History Last Request Value
				guard let routerNode = getNodeInfo(id: Int64(packet.from), context: context) else {
					return
				}
				if routerNode.storeForwardConfig != nil {
					routerNode.storeForwardConfig?.lastRequest = Int32(storeAndForwardMessage.history.lastRequest)
				} else {
					let newConfig = StoreForwardConfigEntity(context: context)
					newConfig.lastRequest = Int32(storeAndForwardMessage.history.lastRequest)
					routerNode.storeForwardConfig = newConfig
				}

				do {
					try context.save()
				} catch {
					context.rollback()
					Logger.data.error("Save Store and Forward Router Error")
				}
				Logger.mesh.info("\("📜 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")")
			case .routerStats:
				Logger.mesh.info("\("📊 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")")
			case .clientError:
				Logger.mesh.info("\("☠️ Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")")
			case .clientHistory:
				Logger.mesh.info("\("📜 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")")
			case .clientStats:
				Logger.mesh.info("\("📊 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")")
			case .clientPing:
				Logger.mesh.info("\("🏓 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")")
			case .clientPong:
				Logger.mesh.info("\("🏓 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")")
			case .clientAbort:
				Logger.mesh.info("\("🛑 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")")
			case .UNRECOGNIZED:
				Logger.mesh.info("\("📮 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")")
			case .routerTextDirect:
				Task {
					Logger.mesh.info("\("💬 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")")
					await MeshPackets.shared.textMessageAppPacket(
						packet: packet,
						wantRangeTestPackets: false,
						connectedNode: connectedNodeNum,
						storeForward: true,
						appState: appState
					)
				}
			case .routerTextBroadcast:
				Task {
					Logger.mesh.info("\("✉️ Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")")
					await MeshPackets.shared.textMessageAppPacket(
						packet: packet,
						wantRangeTestPackets: false,
						connectedNode: connectedNodeNum,
						storeForward: true,
						appState: appState
					)
				}
			}
		}
	}

	func handleTraceRouteApp(_ packet: MeshPacket) {
		guard let device = activeConnection?.device, let deviceNum = device.num else {
			Logger.services.error("Attempt to handle text message when no connected device.")
			return
		}

		if let routingMessage = try? RouteDiscovery(serializedBytes: packet.decoded.payload) {
			let traceRoute = getTraceRoute(id: Int64(packet.decoded.requestID), context: context)
			traceRoute?.response = true
			guard let connectedNode = getNodeInfo(id: Int64(deviceNum), context: context) else {
				return
			}
			var hopNodes: [TraceRouteHopEntity] = []
			let connectedHop = TraceRouteHopEntity(context: context)
			connectedHop.time = Date()
			connectedHop.num = deviceNum
			connectedHop.name = connectedNode.user?.longName ?? "???"
			// If nil, set to unknown, INT8_MIN (-128) then divide by 4
			connectedHop.snr = Float(routingMessage.snrBack.last ?? -128) / 4
			if let mostRecent = traceRoute?.node?.positions?.lastObject as? PositionEntity, mostRecent.time! >= Calendar.current.date(byAdding: .hour, value: -24, to: Date())! {
				connectedHop.altitude = mostRecent.altitude
				connectedHop.latitudeI = mostRecent.latitudeI
				connectedHop.longitudeI = mostRecent.longitudeI
				traceRoute?.hasPositions = true
			}
			var routeString = "\(connectedNode.user?.longName ?? "???") --> "
			hopNodes.append(connectedHop)
			traceRoute?.hopsTowards = Int32(routingMessage.route.count)
			for (index, node) in routingMessage.route.enumerated() {
				var hopNode = getNodeInfo(id: Int64(node), context: context)
				if hopNode == nil && hopNode?.num ?? 0 > 0 && node != 4294967295 {
					hopNode = createNodeInfo(num: Int64(node), context: context)
				}
				let traceRouteHop = TraceRouteHopEntity(context: context)
				traceRouteHop.time = Date()
				if routingMessage.snrTowards.count >= index + 1 {
					traceRouteHop.snr = Float(routingMessage.snrTowards[index]) / 4
				} else {
					// If no snr in route, set unknown
					traceRouteHop.snr = -32
				}
				if let hn = hopNode, hn.hasPositions {
					if let mostRecent = hn.positions?.lastObject as? PositionEntity, mostRecent.time! >= Calendar.current.date(byAdding: .hour, value: -24, to: Date())! {
						traceRouteHop.altitude = mostRecent.altitude
						traceRouteHop.latitudeI = mostRecent.latitudeI
						traceRouteHop.longitudeI = mostRecent.longitudeI
						traceRoute?.hasPositions = true
					}
				}
				traceRouteHop.num = hopNode?.num ?? 0
				if hopNode != nil {
					if packet.rxTime > 0 {
						hopNode?.lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(packet.rxTime)))
					}
				}
				hopNodes.append(traceRouteHop)

				let hopName = hopNode?.user?.longName ?? (node == 4294967295 ? "Repeater" : String(hopNode?.num.toHex() ?? "Unknown".localized))
				let mqttLabel = hopNode?.viaMqtt ?? false ? "MQTT " : ""
				let snrLabel = (traceRouteHop.snr != -32) ? String(traceRouteHop.snr) : "unknown ".localized
				routeString += "\(hopName) \(mqttLabel)(\(snrLabel)dB) --> "
			}
			let destinationHop = TraceRouteHopEntity(context: context)
			destinationHop.name = traceRoute?.node?.user?.longName ?? "Unknown".localized
			destinationHop.time = Date()
			// If nil, set to unknown, INT8_MIN (-128) then divide by 4
			destinationHop.snr = Float(routingMessage.snrTowards.last ?? -128) / 4
			destinationHop.num = traceRoute?.node?.num ?? 0
			if let mostRecent = traceRoute?.node?.positions?.lastObject as? PositionEntity, mostRecent.time! >= Calendar.current.date(byAdding: .hour, value: -24, to: Date())! {
				destinationHop.altitude = mostRecent.altitude
				destinationHop.latitudeI = mostRecent.latitudeI
				destinationHop.longitudeI = mostRecent.longitudeI
				traceRoute?.hasPositions = true
			}
			hopNodes.append(destinationHop)
			/// Add the destination node to the end of the route towards string and the beginning of the route back string
			routeString += "\(traceRoute?.node?.user?.longName ?? "Unknown".localized) \((traceRoute?.node?.num ?? 0).toHex()) (\(destinationHop.snr != -32 ? String(destinationHop.snr) : "unknown ".localized)dB)"
			traceRoute?.routeText = routeString
			// Default to -1 only fill in if routeBack is valid below
			traceRoute?.hopsBack = -1
			// Only if hopStart is set and there is an SNR entry
			if packet.hopStart > 0 && routingMessage.snrBack.count > 0 {
				traceRoute?.hopsBack = Int32(routingMessage.routeBack.count)
				var routeBackString = "\(traceRoute?.node?.user?.longName ?? "Unknown".localized) \((traceRoute?.node?.num ?? 0).toHex()) --> "
				for (index, node) in routingMessage.routeBack.enumerated() {
					var hopNode = getNodeInfo(id: Int64(node), context: context)
					if hopNode == nil && hopNode?.num ?? 0 > 0 && node != 4294967295 {
						hopNode = createNodeInfo(num: Int64(node), context: context)
					}
					let traceRouteHop = TraceRouteHopEntity(context: context)
					traceRouteHop.time = Date()
					traceRouteHop.back = true
					if routingMessage.snrBack.count >= index + 1 {
						traceRouteHop.snr = Float(routingMessage.snrBack[index]) / 4
					} else {
						// If no snr in route, set to unknown
						traceRouteHop.snr = -32
					}
					if let hn = hopNode, hn.hasPositions {
						if let mostRecent = hn.positions?.lastObject as? PositionEntity, mostRecent.time! >= Calendar.current.date(byAdding: .hour, value: -24, to: Date())! {
							traceRouteHop.altitude = mostRecent.altitude
							traceRouteHop.latitudeI = mostRecent.latitudeI
							traceRouteHop.longitudeI = mostRecent.longitudeI
							traceRoute?.hasPositions = true
						}
					}
					traceRouteHop.num = hopNode?.num ?? 0
					if hopNode != nil {
						if packet.rxTime > 0 {
							hopNode?.lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(packet.rxTime)))
						}
					}
					hopNodes.append(traceRouteHop)

					let hopName = hopNode?.user?.longName ?? (node == 4294967295 ? "Repeater" : String(hopNode?.num.toHex() ?? "Unknown".localized))
					let mqttLabel = hopNode?.viaMqtt ?? false ? "MQTT " : ""
					let snrLabel = (traceRouteHop.snr != -32) ? String(traceRouteHop.snr) : "unknown ".localized
					routeBackString += "\(hopName) \(mqttLabel)(\(snrLabel)dB) --> "
				}
				// If nil, set to unknown, INT8_MIN (-128) then divide by 4
				let snrBackLast = Float(routingMessage.snrBack.last ?? -128) / 4
				routeBackString += "\(connectedNode.user?.longName ?? String(connectedNode.num.toHex())) (\(snrBackLast != -32 ? String(snrBackLast) : "unknown ".localized)dB)"
				traceRoute?.routeBackText = routeBackString
			}
			traceRoute?.hops = NSOrderedSet(array: hopNodes)
			traceRoute?.time = Date()

			if let tr = traceRoute {
				let manager = LocalNotificationManager()
				manager.notifications = [
					Notification(
						id: (UUID().uuidString),
						title: "Traceroute Complete",
						subtitle: "TR received back from \(destinationHop.name ?? "unknown")",
						content: "Hops from: \(tr.hopsTowards), Hops back: \(tr.hopsBack)\n\(tr.routeText ?? "Unknown".localized)\n\(tr.routeBackText ?? "Unknown".localized)",
						target: "nodes",
						path: "meshtastic:///nodes?nodenum=\(tr.node?.num ?? 0)"
					)
				]
				manager.schedule()
			}

			do {
				try context.save()
				Logger.data.info("💾 Saved Trace Route")
			} catch {
				context.rollback()
				let nsError = error as NSError
				Logger.data.error("Error Updating Core Data TraceRouteHop: \(nsError, privacy: .public)")
			}
			let logString = String.localizedStringWithFormat("Trace Route request returned: %@".localized, routeString)
			Logger.mesh.info("🪧 \(logString, privacy: .public)")
		}
	}
}
