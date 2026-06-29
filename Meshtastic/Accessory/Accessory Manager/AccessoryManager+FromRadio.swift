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
@preconcurrency import SwiftData

extension AccessoryManager {

	func handleMqttClientProxyMessage(_ mqttClientProxyMessage: MqttClientProxyMessage) {
		Logger.services.info("handleMqttClientProxyMessage topic: \(mqttClientProxyMessage.topic, privacy: .public)")

		// MqttClientProxyMessage carries its payload in a oneof — either binary
		// `data` (service envelope / map report protobuf) or `text` (JSON / stat
		// topics).  Previously this always read `.data`, which silently produced
		// an empty payload whenever the firmware used the `.text` variant — the
		// root cause of map-report packets never reaching the MQTT broker.
		let payload: [UInt8]
		switch mqttClientProxyMessage.payloadVariant {
		case .data(let bytes):
			payload = [UInt8](bytes)
		case .text(let string):
			payload = [UInt8](string.utf8)
		case .none:
			Logger.services.warning("📲 [MQTT Client Proxy] received proxy message with no payload on topic: \(mqttClientProxyMessage.topic, privacy: .public)")
			return
		}

		let message = CocoaMQTTMessage(topic: mqttClientProxyMessage.topic,
									   payload: payload,
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
				id: "client.notification",
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

		// Resolve on a throwaway context, NOT the long-lived main context. After a database clear
		// (manual reset, or the clear inside a device switch) the main context can still hold an
		// invalidated instance registered under a rowid that SwiftData then reuses for the
		// freshly-inserted row — model(for:) would hand that dead instance back and accessing it
		// traps with "destroyed by ModelContext.reset". A fresh context has no such registrations,
		// so it faults the current row from the store.
		let myInfoResolveContext = ModelContext(context.container)
		if let myInfoId = await MeshPackets.shared.myInfoPacket(myInfo: myNodeInfo, peripheralId: connectedDeviceId),
		   let myInfo = try? myInfoResolveContext.model(for: myInfoId) as? MyInfoEntity {
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

		// Auto-disable new-node notifications for event firmware editions
		applyEventFirmwareNotificationDefaults(myNodeInfo.firmwareEdition)
		firmwareEdition = FirmwareEditions(from: myNodeInfo.firmwareEdition)

		// Initialize TAK bridge for TAK integration
		initializeTAKBridge()
	}

	/// When event firmware is detected (DEFCON, BURNING_MAN, OPEN_SAUCE, etc.),
	/// auto-disable new-node notifications on first connection.
	/// Reconnecting to vanilla firmware re-enables and resets the flag.
	private func applyEventFirmwareNotificationDefaults(_ edition: FirmwareEdition) {
		if edition != .vanilla {
			if !UserDefaults.nodeNotificationsAutoDisabledForEvent {
				UserDefaults.newNodeNotifications = false
				UserDefaults.nodeNotificationsAutoDisabledForEvent = true
				Logger.services.info("Event firmware detected (\(String(describing: edition))), auto-disabled new node notifications")
			}
		} else {
			if UserDefaults.nodeNotificationsAutoDisabledForEvent {
				UserDefaults.newNodeNotifications = true
				UserDefaults.nodeNotificationsAutoDisabledForEvent = false
				Logger.services.info("Vanilla firmware detected, re-enabled new node notifications")
			}
		}
	}

	func handleNodeInfo(_ nodeInfo: NodeInfo) async {
		if let continuation = self.firstDatabaseNodeInfoContinuation {
			self.firstDatabaseNodeInfoContinuation = nil
			continuation.resume()
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
		// Resolve on a throwaway context (see handleMyInfo): the long-lived main context can return
		// a stale instance registered under a rowid reused after a database clear, which traps with
		// "destroyed by ModelContext.reset". A fresh context faults the current row from the store.
		let nodeInfoResolveContext = ModelContext(context.container)
		if let nodeInfoId = await MeshPackets.shared.nodeInfoPacket(nodeInfo: nodeInfo, channel: 0, deferSave: false),
		   let nodeInfo = try? nodeInfoResolveContext.model(for: nodeInfoId) as? NodeInfoEntity {
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

	/// Decode the region → legal-preset map the radio advertises during the
	/// want_config handshake (2.8+). Stored on the AccessoryManager so the LoRa
	/// config screen can constrain its preset picker to the selected region's
	/// legal set. Older firmware never sends this; the map simply stays empty and
	/// the UI falls back to its unconstrained behavior.
	func handleRegionPresets(_ regionPresets: LoRaRegionPresetMap) {
		let decoded = regionPresets.decoded()
		loRaRegionPresets = decoded
		Logger.services.info("✅ [handleRegionPresets] decoded \(decoded.count, privacy: .public) region(s) from \(regionPresets.groups.count, privacy: .public) preset group(s)")
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
		Logger.transport.info("✅ [handleDeviceMetadata] deviceMetadataPacket completed for \(deviceNum.toHex(), privacy: .public)")
	}

	internal func tryClearExistingChannels() {
		guard let device = activeConnection?.device, let deviceNum = device.num else {
			Logger.services.error("Attempt to clear existing channels when no connected device.")
			return
		}

		// Before we get started delete the existing channels from the myNodeInfo
		let num = Int64(deviceNum)
		let fetchMyInfoRequest = FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == num })

		do {
			let fetchedMyInfo = try context.fetch(fetchMyInfoRequest)
			if fetchedMyInfo.count == 1 {
				let channelsToDelete = fetchedMyInfo[0].channels
				for channel in channelsToDelete {
					context.delete(channel)
				}
				fetchedMyInfo[0].channels.removeAll()

				// Clean orphaned channels from older app versions where channels were
				// detached but not deleted, which can create duplicate rows in queries.
				let allChannels = try context.fetch(FetchDescriptor<ChannelEntity>())
				for channel in allChannels where channel.myInfoChannel == nil {
					context.delete(channel)
				}
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
				Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
			case .routerError:
				Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
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
						let newConfig = StoreForwardConfigEntity()
						newConfig.enabled = true
						newConfig.isRouter = storeAndForwardMessage.heartbeat.secondary == 0
						newConfig.lastHeartbeat = Date()
						context.insert(newConfig)
						routerNode.storeForwardConfig = newConfig
					}

					do {
						try context.save()
					} catch {
						Logger.data.error("Save Store and Forward Router Error")
					}
				}
				Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
			case .routerPing:
				Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
			case .routerPong:
				Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
			case .routerBusy:
				Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
			case .routerHistory:
				/// Set the Router History Last Request Value
				guard let routerNode = getNodeInfo(id: Int64(packet.from), context: context) else {
					return
				}
				if routerNode.storeForwardConfig != nil {
					routerNode.storeForwardConfig?.lastRequest = Int32(storeAndForwardMessage.history.lastRequest)
				} else {
					let newConfig = StoreForwardConfigEntity()
					newConfig.lastRequest = Int32(storeAndForwardMessage.history.lastRequest)
					context.insert(newConfig)
					routerNode.storeForwardConfig = newConfig
				}

				do {
					try context.save()
				} catch {
					Logger.data.error("Save Store and Forward Router Error")
				}
				Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
			case .routerStats:
				Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
			case .clientError:
				Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
			case .clientHistory:
				Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
			case .clientStats:
				Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
			case .clientPing:
				Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
			case .clientPong:
				Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
			case .clientAbort:
				Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
			case .UNRECOGNIZED:
				Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
			case .routerTextDirect:
				Task {
					Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
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
					Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
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
			Logger.services.error("Attempt to handle trace route when no connected device.")
			return
		}

		if let routingMessage = try? RouteDiscovery(serializedBytes: packet.decoded.payload) {
			// Full responses only: a trace route response always carries the originating request id.
			// A zero request id means this is an in-flight request (or a request targeting us), which
			// we don't persist.
			guard packet.decoded.requestID != 0 else {
				Logger.mesh.info("🪧 Ignoring trace route request (no response) from \(packet.from.toHex(), privacy: .public)")
				return
			}

			// Resolve the originator (request sender) and target (responder). For routes we initiated
			// the originator is our connected node and a TraceRouteEntity already exists. For routes
			// observed on the mesh the response is addressed back to the original requester
			// (`packet.to`) and sent by the responder (`packet.from`); we create a new record for those.
			// A record only counts as "initiated by us" when we sent the request. Observed routes we
			// previously stored (and may now be re-seeing as a rebroadcast) are updated in place.
			let existingTraceRoute = getTraceRoute(id: Int64(packet.decoded.requestID), context: context)
			let initiatedByUs = existingTraceRoute?.sent == true
			let originatorNum: Int64
			let targetNum: Int64
			let traceRoute: TraceRouteEntity
			if initiatedByUs, let existingTraceRoute {
				traceRoute = existingTraceRoute
				originatorNum = deviceNum
				targetNum = existingTraceRoute.node?.num ?? Int64(packet.from)
			} else {
				if let existingTraceRoute {
					traceRoute = existingTraceRoute
				} else {
					traceRoute = TraceRouteEntity()
					context.insert(traceRoute)
					traceRoute.id = Int64(packet.decoded.requestID)
				}
				traceRoute.sent = false
				originatorNum = Int64(packet.to)
				targetNum = Int64(packet.from)
			}
			traceRoute.response = true
			traceRoute.fromNum = originatorNum
			traceRoute.toNum = targetNum

			// Used for display/position lookups. The `node` relationship stays set only for routes we
			// initiated; observed routes are surfaced in the global trace route log instead.
			let originatorNode = getNodeInfo(id: originatorNum, context: context)
			let targetNodeInfo = (initiatedByUs ? existingTraceRoute?.node : nil) ?? getNodeInfo(id: targetNum, context: context)

			// Reprocessing an existing record (e.g. a rebroadcast we re-observe): drop the previous
			// hops before rebuilding so we don't accumulate orphaned/duplicate hop rows.
			for hop in traceRoute.hops {
				context.delete(hop)
			}

			var hopNodes: [TraceRouteHopEntity] = []
			let connectedHop = TraceRouteHopEntity()
			context.insert(connectedHop)
			connectedHop.time = Date()
			connectedHop.num = originatorNum
			connectedHop.name = originatorNode?.user?.longName ?? "???"
			connectedHop.index = 0
			// If nil, set to unknown, INT8_MIN (-128) then divide by 4
			connectedHop.snr = Float(routingMessage.snrBack.last ?? -128) / 4
			var routeString = "\(originatorNode?.user?.longName ?? "???") --> "
			hopNodes.append(connectedHop)
			traceRoute.hopsTowards = Int32(routingMessage.route.count)
			for (index, node) in routingMessage.route.enumerated() {
				var hopNode = getNodeInfo(id: Int64(node), context: context)
				if hopNode == nil && hopNode?.num ?? 0 > 0 && node != 4294967295 {
					hopNode = findOrCreateNode(num: Int64(node), context: context)
				}
				let traceRouteHop = TraceRouteHopEntity()
				context.insert(traceRouteHop)
				traceRouteHop.time = Date()
				if routingMessage.snrTowards.count >= index + 1 {
					traceRouteHop.snr = Float(routingMessage.snrTowards[index]) / 4
				} else {
					// If no snr in route, set unknown
					traceRouteHop.snr = -32
				}
				traceRouteHop.num = hopNode?.num ?? 0
				traceRouteHop.index = Int32(index + 1)
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
			let destinationHop = TraceRouteHopEntity()
			context.insert(destinationHop)
			destinationHop.name = targetNodeInfo?.user?.longName ?? "Unknown".localized
			destinationHop.time = Date()
			// If nil, set to unknown, INT8_MIN (-128) then divide by 4
			destinationHop.snr = Float(routingMessage.snrTowards.last ?? -128) / 4
			destinationHop.num = targetNum
			destinationHop.index = Int32(routingMessage.route.count + 1)
			hopNodes.append(destinationHop)
			/// Add the destination node to the end of the route towards string and the beginning of the route back string
			routeString += "\(targetNodeInfo?.user?.longName ?? "Unknown".localized) \(targetNum.toHex()) (\(destinationHop.snr != -32 ? String(destinationHop.snr) : "unknown ".localized)dB)"
			traceRoute.routeText = routeString
			// Default to -1 only fill in if routeBack is valid below
			traceRoute.hopsBack = -1
			// Only if hopStart is set and there is an SNR entry
			if packet.hopStart > 0 && routingMessage.snrBack.count > 0 {
				traceRoute.hopsBack = Int32(routingMessage.routeBack.count)
				var routeBackString = "\(targetNodeInfo?.user?.longName ?? "Unknown".localized) \(targetNum.toHex()) --> "
				for (index, node) in routingMessage.routeBack.enumerated() {
					var hopNode = getNodeInfo(id: Int64(node), context: context)
					if hopNode == nil && hopNode?.num ?? 0 > 0 && node != 4294967295 {
						hopNode = findOrCreateNode(num: Int64(node), context: context)
					}
					let traceRouteHop = TraceRouteHopEntity()
					context.insert(traceRouteHop)
					traceRouteHop.time = Date()
					traceRouteHop.back = true
					if routingMessage.snrBack.count >= index + 1 {
						traceRouteHop.snr = Float(routingMessage.snrBack[index]) / 4
					} else {
						// If no snr in route, set to unknown
						traceRouteHop.snr = -32
					}
					traceRouteHop.num = hopNode?.num ?? 0
					traceRouteHop.index = Int32(index)
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
				routeBackString += "\(originatorNode?.user?.longName ?? originatorNum.toHex()) (\(snrBackLast != -32 ? String(snrBackLast) : "unknown ".localized)dB)"
				traceRoute.routeBackText = routeBackString
			}
			traceRoute.hops = hopNodes
			traceRoute.time = Date()

			// Snapshot each involved node's current position so the route can later be mapped using
			// the positions nodes had when the trace route ran, rather than wherever they've drifted
			// to since. One snapshot per unique node num (originator, target, and every hop).
			snapshotTraceRoutePositions(for: traceRoute, packet: packet, routingMessage: routingMessage)

			// Only notify for trace routes we initiated; observed routes shouldn't generate alerts.
			if traceRoute.sent {
				let manager = LocalNotificationManager()
				manager.notifications = [
					Notification(
						id: (UUID().uuidString),
						title: "Traceroute Complete",
						subtitle: "TR received back from \(destinationHop.name ?? "unknown")",
						content: "Hops from: \(traceRoute.hopsTowards), Hops back: \(traceRoute.hopsBack)\n\(traceRoute.routeText ?? "Unknown".localized)\n\(traceRoute.routeBackText ?? "Unknown".localized)",
						target: "nodes",
						path: "meshtastic:///nodes?nodenum=\(traceRoute.node?.num ?? targetNum)"
					)
				]
				manager.schedule()
			}

			do {
				try context.save()
				Logger.data.info("💾 Saved Trace Route")
			} catch {
				let nsError = error as NSError
				Logger.data.error("Error Updating Core Data TraceRouteHop: \(nsError, privacy: .public)")
			}
			let logString = String.localizedStringWithFormat("Trace Route request returned: %@".localized, routeString)
			Logger.mesh.info("🪧 \(logString, privacy: .public)")
		}
	}

	/// Captures a point-in-time snapshot of the current position of every node involved in a trace
	/// route (originator, target, and all forward/return hops), deduplicated by node num. Rebuilds
	/// from scratch so reprocessing a rebroadcast doesn't accumulate stale snapshots.
	private func snapshotTraceRoutePositions(for traceRoute: TraceRouteEntity, packet: MeshPacket, routingMessage: RouteDiscovery) {
		for existing in traceRoute.nodePositions {
			context.delete(existing)
		}

		// 0xFFFFFFFF is the "unknown node" sentinel used for repeater hops — skip it.
		let broadcastNum: UInt32 = 4294967295
		var nums = Set<Int64>([traceRoute.fromNum, traceRoute.toNum])
		for node in routingMessage.route where node != broadcastNum { nums.insert(Int64(node)) }
		for node in routingMessage.routeBack where node != broadcastNum { nums.insert(Int64(node)) }
		nums = nums.filter { $0 > 0 }

		var snapshotted = false
		for num in nums {
			guard let node = getNodeInfo(id: num, context: context),
				  let position = node.latestPosition,
				  position.nodeCoordinate != nil else {
				continue
			}
			let snapshot = TraceRouteNodePositionEntity()
			context.insert(snapshot)
			snapshot.num = num
			snapshot.latitudeI = position.latitudeI
			snapshot.longitudeI = position.longitudeI
			snapshot.altitude = position.altitude
			snapshot.precisionBits = position.precisionBits
			snapshot.satsInView = position.satsInView
			snapshot.speed = position.speed
			snapshot.heading = position.heading
			snapshot.seqNo = position.seqNo
			snapshot.snr = position.snr
			snapshot.time = position.time
			snapshot.traceRoute = traceRoute
			snapshotted = true
		}
		traceRoute.hasPositions = snapshotted
	}
}
