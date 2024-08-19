import CocoaMQTT
import CoreBluetooth
import CoreData
import MeshtasticProtobufs
import OSLog

// swiftlint:disable all
extension BLEManager: CBPeripheralDelegate {
	func peripheral(
		_ peripheral: CBPeripheral,
		didDiscoverServices error: Error?
	) {
		if let error {
			Logger.services.error("🚫 [BLE] Discover Services error \(error.localizedDescription, privacy: .public)")
		}

		guard let services = peripheral.services else {
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
	}

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

			return
		}

		guard let characteristics = service.characteristics else {
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
			if mqttProxyConnected {
				mqttManager.mqttClientProxy?.disconnect()
			}

			let nodeConfig = NodeConfig(bleManager: self, context: context)
			lastConfigNonce = nodeConfig.sendWantConfig()
		}
	}

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

		case BluetoothUUID.logRadioLegacy:
			guard
				let value = characteristic.value,
				let log = String(data: value, encoding: .utf8)
			else {
				return
			}

			handleRadioLog(log)

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

				mqttManager.mqttClientProxy?.publish(message)
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

			case .textMessageApp, .detectionSensorApp:
				textMessageAppPacket(
					packet: info.packet,
					wantRangeTestPackets: wantRangeTestPackets,
					connectedNode: (connectedDevice.num),
					context: context,
					appState: appState
				)

			case .positionApp:
				upsertPositionPacket(packet: info.packet, context: context)

			case .waypointApp:
				waypointPacket(packet: info.packet, context: context)

			case .nodeinfoApp:
				if !isInvalidFwVersion {
					upsertNodeInfoPacket(packet: info.packet, context: context)
				}

			case .routingApp:
				if !isInvalidFwVersion {
					routingPacket(
						packet: info.packet,
						connectedNodeNum: connectedDevice.num,
						context: context
					)
				}

			case .adminApp:
				adminAppPacket(packet: info.packet, context: context)

			case .replyApp:
				MeshLogger.log("🕸️ MESH PACKET received for Reply App handling as a text message")

				textMessageAppPacket(
					packet: info.packet,
					wantRangeTestPackets: wantRangeTestPackets,
					connectedNode: connectedDevice.num,
					context: context,
					appState: appState
				)

			case .storeForwardApp:
				if wantStoreAndForwardPackets {
					storeAndForwardPacket(
						packet: info.packet,
						connectedNodeNum: connectedDevice.num,
						context: context
					)
				}

			case .rangeTestApp:
				if wantRangeTestPackets {
					textMessageAppPacket(
						packet: info.packet,
						wantRangeTestPackets: true,
						connectedNode: connectedDevice.num,
						context: context,
						appState: appState
					)
				}

			case .telemetryApp:
				if !isInvalidFwVersion {
					telemetryPacket(
						packet: info.packet,
						connectedNode: connectedDevice.num,
						context: context
					)
				}

			case .tracerouteApp:
				if
					let routingMessage = try? RouteDiscovery(serializedData: info.packet.decoded.payload),
					!routingMessage.route.isEmpty
				{
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
				}

			case .paxcounterApp:
				paxCounterPacket(packet: info.packet, context: context)

			default:
				MeshLogger.log("Received unhandled packet")
			}

			let id = info.configCompleteID
			if id != UInt32.min, id == lastConfigNonce {
				Logger.mesh.info("🤜 [BLE] Want Config Complete. ID: \(id)")
				
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
						else if mqttProxyConnected {
							mqttManager.mqttClientProxy?.disconnect()
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
				
				// MARK: Share Location Position Update Timer
				// Use context to pass the radio name with the timer
				// Use a RunLoop to prevent the timer from running on the main UI thread
				if UserDefaults.provideLocation {
					let interval = UserDefaults.provideLocationInterval >= 10 ? UserDefaults.provideLocationInterval : 30
					
					let timer = Timer.scheduledTimer(
						timeInterval: TimeInterval(interval),
						target: self,
						selector: #selector(positionTimerFired),
						userInfo: context,
						repeats: true
					)
					RunLoop.current.add(timer, forMode: .common)
					
					positionTimer = timer
				}
				return
			}
			
		default:
			Logger.services.error("Unhandled characteristic UUID: \(characteristic.uuid, privacy: .public)")
		}
		
		if let characteristicFromRadio {
			peripheral.readValue(for: characteristicFromRadio)
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
}
// swiftlint:enable all
