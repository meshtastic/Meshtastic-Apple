import CocoaMQTT
import CoreBluetooth
import CoreData
import MeshtasticProtobufs
import OSLog

extension BLEManager: CBPeripheralDelegate {
	func peripheral(
		_ peripheral: CBPeripheral,
		didDiscoverServices error: Error?
	) {
		guard let services = peripheral.services else {
			AnalyticEvents.trackPeripheralEvent(
				for: .didDiscoverServices,
				status: .failureProcess
			)

			return
		}

		for service in services where service.uuid == BluetoothUUID.meshtasticService {
			peripheral.discoverCharacteristics(
				[
					BluetoothUUID.toRadio,
					BluetoothUUID.fromRadio,
					BluetoothUUID.fromNum,
					BluetoothUUID.logRadioLegacy,
					BluetoothUUID.logRadio
				],
				for: service
			)
		}

		if let error {
			AnalyticEvents.trackPeripheralEvent(
				for: .didDiscoverServices,
				status: .error(error.localizedDescription)
			)
		}
		else {
			AnalyticEvents.trackPeripheralEvent(
				for: .didDiscoverServices,
				status: .success
			)
		}
	}

	// swiftlint:disable:next cyclomatic_complexity
	func peripheral(
		_ peripheral: CBPeripheral,
		didDiscoverCharacteristicsFor service: CBService,
		error: Error?
	) {
		if let error {
			Logger.services.error(
				"🚫 [BLE] Discover Characteristics error for \(peripheral.name ?? "Unknown", privacy: .public) \(error.localizedDescription, privacy: .public) disconnecting device"
			)

			disconnectDevice()

			AnalyticEvents.trackPeripheralEvent(
				for: .didDiscoverCharacteristics,
				status: .error(error.localizedDescription)
			)

			return
		}

		guard let characteristics = service.characteristics else {
			AnalyticEvents.trackPeripheralEvent(
				for: .didDiscoverCharacteristics,
				status: .failureProcess
			)

			return
		}

		for characteristic in characteristics {
			switch characteristic.uuid {
			case BluetoothUUID.toRadio:
				characteristicToRadio = characteristic

			case BluetoothUUID.fromRadio:
				characteristicFromRadio = characteristic
				peripheral.readValue(for: characteristicFromRadio)

			case BluetoothUUID.fromNum:
				characteristicFromNum = characteristic
				peripheral.setNotifyValue(true, for: characteristic)

			case BluetoothUUID.logRadioLegacy:
				characteristicLogRadioLegacy = characteristic
				peripheral.setNotifyValue(true, for: characteristic)

			case BluetoothUUID.logRadio:
				characteristicLogRadio = characteristic
				peripheral.setNotifyValue(true, for: characteristic)

			default:
				break
			}
		}

		if ![characteristicFromNum, characteristicToRadio].contains(nil) {
			if mqttConnected {
				mqttManager.client?.disconnect()
			}

			let nodeConfig = NodeConfig(bleManager: self, context: context)
			lastConfigNonce = nodeConfig.sendWantConfig()
		}

		AnalyticEvents.trackPeripheralEvent(
			for: .didDiscoverCharacteristics,
			status: .success
		)
	}

	// swiftlint:disable:next cyclomatic_complexity
	func peripheral(
		_ peripheral: CBPeripheral,
		didUpdateValueFor characteristic: CBCharacteristic,
		error: Error?
	) {
		if let error {
			Logger.services.error(
				"🚫 [BLE] didUpdateValueFor Characteristic error \(error.localizedDescription, privacy: .public)"
			)

			let errorCode = (error as NSError).code
			if errorCode == 5 || errorCode == 15 {
				// BLE PIN connection errors
				// 5 CBATTErrorDomain Code=5 "Authentication is insufficient."
				// 15 CBATTErrorDomain Code=15 "Encryption is insufficient."
				lastConnectionError = "Bluetooth authentication or encryption is insufficient. Please check connecting again and pay attention to the PIN code."
				disconnectDevice(reconnect: false)
			}

			AnalyticEvents.trackPeripheralEvent(
				for: .didUpdate,
				status: .error(error.localizedDescription)
			)

			return
		}

		switch characteristic.uuid {
		case BluetoothUUID.logRadio:
			guard
				let value = characteristic.value,
				let logRecord = try? LogRecord(serializedData: value)
			else {
				return
			}

			handleRadioLog(
				"\(logRecord.level.rawValue) | [\(logRecord.source)] \(logRecord.message)"
			)

			AnalyticEvents.trackPeripheralEvent(
				for: .didUpdate,
				status: .success,
				characteristic: .logRadio
			)

		case BluetoothUUID.logRadioLegacy:
			guard
				let value = characteristic.value,
				let log = String(data: value, encoding: .utf8)
			else {
				return
			}

			handleRadioLog(log)

			AnalyticEvents.trackPeripheralEvent(
				for: .didUpdate,
				status: .success,
				characteristic: .logRadioLegacy
			)

		case BluetoothUUID.fromRadio:
			guard
				let value = characteristic.value,
				let info = try? FromRadio(serializedData: value),
				let connectedDevice = getConnectedDevice()
			else {
				return
			}

			// Publish mqttClientProxyMessages received on the from radio
			if info.payloadVariant == FromRadio.OneOf_PayloadVariant.mqttClientProxyMessage(
				info.mqttClientProxyMessage
			)
			{
				let message = CocoaMQTTMessage(
					topic: info.mqttClientProxyMessage.topic,
					payload: [UInt8](info.mqttClientProxyMessage.data),
					retained: info.mqttClientProxyMessage.retained
				)

				mqttManager.client?.publish(message)
			}

			switch info.packet.decoded.portnum {
			case .unknownApp:
				// MyInfo from initial connection
				if info.myInfo.isInitialized, info.myInfo.myNodeNum > 0 {
					if let myInfo = myInfoPacket(
						myInfo: info.myInfo,
						peripheralId: deviceConnected.id,
						context: context
					) {
						UserDefaults.preferredPeripheralNum = Int(myInfo.myNodeNum)

						deviceConnected?.num = myInfo.myNodeNum
						deviceConnected?.name = myInfo.bleName ?? "unknown".localized
						deviceConnected?.longName = myInfo.bleName ?? "unknown".localized
					}

					tryClearExistingChannels()
				}

				// NodeInfo
				if info.nodeInfo.num > 0 {
					if
						let nodeInfo = nodeInfoPacket(
							nodeInfo: info.nodeInfo,
							channel: info.packet.channel,
							context: context
						),
						let user = nodeInfo.user,
						connectedDevice.num == nodeInfo.num
					{
						deviceConnected?.shortName = user.shortName ?? "?"
						deviceConnected?.longName = user.longName ?? "unknown".localized
					}
				}

				// Channels
				if info.channel.isInitialized {
					channelPacket(
						channel: info.channel,
						fromNum: Int64(truncatingIfNeeded: connectedDevice.num),
						context: context
					)
				}

				// Config
				if info.config.isInitialized, !isInvalidFwVersion {
					localConfig(
						config: info.config,
						context: context,
						nodeNum: Int64(truncatingIfNeeded: connectedDevice.num),
						nodeLongName: deviceConnected.longName
					)
				}

				// Module Config
				if info.moduleConfig.isInitialized, !isInvalidFwVersion, connectedDevice.num != 0 {
					moduleConfig(
						config: info.moduleConfig,
						context: context,
						nodeNum: Int64(truncatingIfNeeded: connectedDevice.num),
						nodeLongName: deviceConnected.longName
					)
				}

				// Device Metadata
				if info.metadata.firmwareVersion.count > 0, !isInvalidFwVersion {
					deviceConnected?.firmwareVersion = info.metadata.firmwareVersion

					deviceMetadataPacket(
						metadata: info.metadata,
						fromNum: connectedDevice.num,
						context: context
					)

					if let lastDotIndex = info.metadata.firmwareVersion.lastIndex(of: ".") {
						let version = info.metadata.firmwareVersion[...lastDotIndex]
						connectedVersion = String(version.dropLast())
						UserDefaults.firmwareVersion = connectedVersion
					}
					else {
						isInvalidFwVersion = true
						connectedVersion = "0.0.0"
					}

					let supportedVersion = connectedVersion == "0.0.0"
					|| [.orderedAscending, .orderedSame].contains(minimumVersion.compare(connectedVersion, options: .numeric))

					if !supportedVersion {
						isInvalidFwVersion = true
						lastConnectionError = "🚨" + "update.firmware".localized

						return
					}
				}

				AnalyticEvents.trackPeripheralEvent(
					for: .didUpdate,
					status: .success,
					characteristic: .fromRadio,
					app: .unknown
				)

			case .textMessageApp, .detectionSensorApp:
				textMessageAppPacket(
					packet: info.packet,
					wantRangeTestPackets: wantRangeTestPackets,
					connectedNode: (connectedDevice.num),
					context: context,
					appState: appState
				)

				AnalyticEvents.trackPeripheralEvent(
					for: .didUpdate,
					status: .success,
					characteristic: .fromRadio,
					app: .message
				)

			case .positionApp:
				upsertPositionPacket(packet: info.packet, context: context)

				AnalyticEvents.trackPeripheralEvent(
					for: .didUpdate,
					status: .success,
					characteristic: .fromRadio,
					app: .position
				)

			case .waypointApp:
				waypointPacket(packet: info.packet, context: context)

				AnalyticEvents.trackPeripheralEvent(
					for: .didUpdate,
					status: .success,
					characteristic: .fromRadio,
					app: .waypoint
				)

			case .nodeinfoApp:
				guard !isInvalidFwVersion else {
					break
				}

				upsertNodeInfoPacket(packet: info.packet, context: context)

				AnalyticEvents.trackPeripheralEvent(
					for: .didUpdate,
					status: .success,
					characteristic: .fromRadio,
					app: .nodeInfo
				)

			case .routingApp:
				guard !isInvalidFwVersion else {
					break
				}

				routingPacket(
					packet: info.packet,
					connectedNodeNum: connectedDevice.num,
					context: context
				)

				AnalyticEvents.trackPeripheralEvent(
					for: .didUpdate,
					status: .success,
					characteristic: .fromRadio,
					app: .routing
				)

			case .adminApp:
				adminAppPacket(packet: info.packet, context: context)

				AnalyticEvents.trackPeripheralEvent(
					for: .didUpdate,
					status: .success,
					characteristic: .fromRadio,
					app: .admin
				)

			case .replyApp:
				textMessageAppPacket(
					packet: info.packet,
					wantRangeTestPackets: wantRangeTestPackets,
					connectedNode: connectedDevice.num,
					context: context,
					appState: appState
				)

				AnalyticEvents.trackPeripheralEvent(
					for: .didUpdate,
					status: .success,
					characteristic: .fromRadio,
					app: .reply
				)

			case .storeForwardApp:
				guard wantStoreAndForwardPackets else {
					break
				}

				storeAndForwardPacket(
					packet: info.packet,
					connectedNodeNum: connectedDevice.num,
					context: context
				)

				AnalyticEvents.trackPeripheralEvent(
					for: .didUpdate,
					status: .success,
					characteristic: .fromRadio,
					app: .storeAndForward
				)

			case .rangeTestApp:
				guard wantRangeTestPackets else {
					break
				}

				textMessageAppPacket(
					packet: info.packet,
					wantRangeTestPackets: true,
					connectedNode: connectedDevice.num,
					context: context,
					appState: appState
				)

				AnalyticEvents.trackPeripheralEvent(
					for: .didUpdate,
					status: .success,
					characteristic: .fromRadio,
					app: .rangeTest
				)

			case .telemetryApp:
				guard !isInvalidFwVersion else {
					break
				}

				telemetryPacket(
					packet: info.packet,
					connectedNode: connectedDevice.num,
					context: context
				)

				AnalyticEvents.trackPeripheralEvent(
					for: .didUpdate,
					status: .success,
					characteristic: .fromRadio,
					app: .telemetry
				)

			case .tracerouteApp:
				guard
					let routingMessage = try? RouteDiscovery(serializedData: info.packet.decoded.payload),
					!routingMessage.route.isEmpty
				else {
					break
				}

				var routeString = "You --> "
				var hopNodes: [TraceRouteHopEntity] = []

				let traceRoute = getTraceRoute(id: Int64(info.packet.decoded.requestID), context: context)
				traceRoute?.response = true
				traceRoute?.route = routingMessage.route

				for node in routingMessage.route {
					var hopNode = getNodeInfo(id: Int64(node), context: context)

					if hopNode == nil && hopNode?.num ?? 0 > 0 && node != 4294967295 {
						hopNode = createNodeInfo(num: Int64(node), context: context)
					}

					let traceRouteHop = TraceRouteHopEntity(context: context)
					traceRouteHop.time = Date.now

					if hopNode?.hasPositions ?? false {
						if
							let mostRecent = hopNode?.positions?.lastObject as? PositionEntity,
							let time = mostRecent.time,
							time >= Calendar.current.date(byAdding: .minute, value: -60, to: Date.now)!
						{
							traceRouteHop.altitude = mostRecent.altitude
							traceRouteHop.latitudeI = mostRecent.latitudeI
							traceRouteHop.longitudeI = mostRecent.longitudeI
							traceRouteHop.name = hopNode?.user?.longName ?? "unknown".localized
							
							traceRoute?.hasPositions = true
						}
						else {
							traceRoute?.hasPositions = false
						}
					}
					else {
						traceRoute?.hasPositions = false
					}

					traceRouteHop.num = hopNode?.num ?? 0

					if let hopNode {
						if info.packet.rxTime > 0 {
							hopNode.lastHeard = Date(
								timeIntervalSince1970: TimeInterval(Int64(info.packet.rxTime))
							)
						}

						hopNodes.append(traceRouteHop)
					}

					routeString += "\(hopNode?.user?.longName ?? (node == 4294967295 ? "Repeater" : String(hopNode?.num.toHex() ?? "unknown".localized))) \(hopNode?.viaMqtt ?? false ? "MQTT" : "") --> "
				}
				routeString += traceRoute?.node?.user?.longName ?? "unknown".localized
				traceRoute?.routeText = routeString
				traceRoute?.hops = NSOrderedSet(array: hopNodes)

				do {
					try context.save()
				} catch {
					context.rollback()
				}

				AnalyticEvents.trackPeripheralEvent(
					for: .didUpdate,
					status: .success,
					characteristic: .fromRadio,
					app: .traceRoute
				)

			case .paxcounterApp:
				paxCounterPacket(packet: info.packet, context: context)

				AnalyticEvents.trackPeripheralEvent(
					for: .didUpdate,
					status: .success,
					characteristic: .fromRadio,
					app: .paxCounter
				)

			default:
				AnalyticEvents.trackPeripheralEvent(
					for: .didUpdate,
					status: .success,
					characteristic: .fromRadio,
					app: .unhandled
				)
			}

			let id = info.configCompleteID
			if id != UInt32.min, id == lastConfigNonce {
				isInvalidFwVersion = false
				lastConnectionError = ""
				isSubscribed = true

				devices.removeAll(where: {
					$0.peripheral.state == .disconnected
				})

				if deviceConnected.num > 0 {
					let fetchNodeInfoRequest = NodeInfoEntity.fetchRequest()
					fetchNodeInfoRequest.predicate = NSPredicate(
						format: "num == %lld",
						Int64(deviceConnected.num)
					)

					if
						let fetchedNodeInfo = try? context.fetch(fetchNodeInfoRequest),
						!fetchedNodeInfo.isEmpty
					{
						let node = fetchedNodeInfo[0]

						if
							let mqttConfig = node.mqttConfig,
							mqttConfig.enabled,
							mqttConfig.proxyToClientEnabled
						{
							mqttManager.connectFromConfigSettings(node: node)
						}
						else if mqttConnected {
							mqttManager.client?.disconnect()
						}

						// Set initial unread message badge states
						appState.unreadChannelMessages = node.myInfo?.unreadMessages ?? 0
						appState.unreadDirectMessages = node.user?.unreadMessages ?? 0

						if let rtConf = node.rangeTestConfig, rtConf.enabled {
							wantRangeTestPackets = true
						}

						if let sfConf = node.storeForwardConfig, sfConf.enabled {
							wantStoreAndForwardPackets = true
						}
					}
				}

				if UserDefaults.provideLocation {
					let timer = Timer.scheduledTimer(
						timeInterval: TimeInterval(UserDefaults.provideLocationInterval),
						target: self,
						selector: #selector(positionTimerFired),
						userInfo: context,
						repeats: true
					)
					RunLoop.current.add(timer, forMode: .common)

					positionTimer = timer
				}

				AnalyticEvents.trackBLEEvent(for: .wantConfigComplete, status: .success)

				return
			}

		default:
			Logger.services.error("Unhandled characteristic UUID: \(characteristic.uuid, privacy: .public)")
		}

		if let characteristicFromRadio {
			peripheral.readValue(for: characteristicFromRadio)
		}
	}

	private func storeAndForwardPacket(
		packet: MeshPacket,
		connectedNodeNum: Int64,
		context: NSManagedObjectContext
	) {
		if let storeAndForwardMessage = try? StoreAndForward(serializedData: packet.decoded.payload) {
			MeshLogger.log(
				"Store & Forward: Message \(storeAndForwardMessage.rr.rawValue) received from \(packet.from.toHex())"
			)

			switch storeAndForwardMessage.rr {
			case .routerHeartbeat:
				/// When we get a router heartbeat we know there is a store and forward node on the network
				/// Check if it is the primary S&F Router and save the timestamp of the last
				/// heartbeat so that we can show the request message history menu item on node
				/// long press if the router has been seen recently
				guard
					storeAndForwardMessage.heartbeat.secondary != 0,
					let router = getNodeInfo(
						id: Int64(packet.from),
						context: context
					)
				else {
					return
				}

				if router.storeForwardConfig != nil {
					router.storeForwardConfig?.enabled = true
					router.storeForwardConfig?.isRouter = storeAndForwardMessage.heartbeat.secondary == 0
					router.storeForwardConfig?.lastHeartbeat = Date.now
				} else {
					let newConfig = StoreForwardConfigEntity(context: context)
					newConfig.enabled = true
					newConfig.isRouter = storeAndForwardMessage.heartbeat.secondary == 0
					newConfig.lastHeartbeat = Date.now

					router.storeForwardConfig = newConfig
				}

				do {
					try context.save()
				} catch {
					context.rollback()
				}

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
				}

			case .routerTextDirect:
				textMessageAppPacket(
					packet: packet,
					wantRangeTestPackets: false,
					connectedNode: connectedNodeNum,
					storeForward: true,
					context: context,
					appState: appState
				)

			case .routerTextBroadcast:
				textMessageAppPacket(
					packet: packet,
					wantRangeTestPackets: false,
					connectedNode: connectedNodeNum,
					storeForward: true,
					context: context,
					appState: appState
				)

			default:
				return
			}
		}
	}

	private func handleRadioLog(_ message: String) {
		Logger.radio.info("\(message, privacy: .public)")
	}

	private func tryClearExistingChannels() {
		guard let connectedDevice = getConnectedDevice() else {
			return
		}
		
		let fetchMyInfoRequest = MyInfoEntity.fetchRequest()
		fetchMyInfoRequest.predicate = NSPredicate(
			format: "myNodeNum == %lld",
			Int64(connectedDevice.num)
		)
		
		if
			let myInfo = try? context.fetch(fetchMyInfoRequest),
			!myInfo.isEmpty
		{
			myInfo[0].channels = NSOrderedSet()
			try? context.save()
		}
	}

	@objc
	private func positionTimerFired(timer: Timer) {
		guard
			let connectedDevice = getConnectedDevice(),
			UserDefaults.provideLocation
		else {
			return
		}

		sendPosition(
			channel: 0,
			destNum: connectedDevice.num,
			wantResponse: false
		)
	}
}
