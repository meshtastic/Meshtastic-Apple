import CocoaMQTT
import CoreBluetooth
import CoreData
import MeshtasticProtobufs
import OSLog

// swiftlint:disable all
extension BLEManager: CBPeripheralDelegate {
	func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
		if let error {
			Logger.services.error("🚫 [BLE] Discover Services error \(error.localizedDescription, privacy: .public)")
		}
		guard let services = peripheral.services else { return }
		for service in services where service.uuid == BluetoothUUID.meshtasticService {
			peripheral.discoverCharacteristics([BluetoothUUID.toRadio, BluetoothUUID.fromRadio, BluetoothUUID.fromNum, BluetoothUUID.logRadioLegacy, BluetoothUUID.logRadio], for: service)
			Logger.services.info("✅ [BLE] Service for Meshtastic discovered by \(peripheral.name ?? "Unknown", privacy: .public)")
		}
	}
	
	func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
		if let error {
			Logger.services.error("💥 [BLE] didUpdateNotificationStateFor error: \(characteristic.uuid, privacy: .public) \(error.localizedDescription, privacy: .public)")
		} else {
			Logger.services.info("ℹ️ [BLE] peripheral didUpdateNotificationStateFor \(characteristic.uuid, privacy: .public)")
		}
	}
	
	// MARK: Discover Characteristics Event
	func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
		
		if let error {
			Logger.services.error("🚫 [BLE] Discover Characteristics error for \(peripheral.name ?? "Unknown", privacy: .public) \(error.localizedDescription, privacy: .public) disconnecting device")
			// Try and stop crashes when this error occurs
			disconnectDevice()
			return
		}
		
		guard let characteristics = service.characteristics else { return }
		
		for characteristic in characteristics {
			switch characteristic.uuid {
				
			case BluetoothUUID.toRadio:
				Logger.services.info("✅ [BLE] did discover TORADIO characteristic for Meshtastic by \(peripheral.name ?? "Unknown", privacy: .public)")
				characteristicToRadio = characteristic
				
			case BluetoothUUID.fromRadio:
				Logger.services.info("✅ [BLE] did discover FROMRADIO characteristic for Meshtastic by \(peripheral.name ?? "Unknown", privacy: .public)")
				characteristicFromRadio = characteristic
				peripheral.readValue(for: characteristicFromRadio)
				
			case BluetoothUUID.fromNum:
				Logger.services.info("✅ [BLE] did discover FROMNUM (Notify) characteristic for Meshtastic by \(peripheral.name ?? "Unknown", privacy: .public)")
				characteristicFromNum = characteristic
				peripheral.setNotifyValue(true, for: characteristic)
				
			case BluetoothUUID.logRadioLegacy:
				Logger.services.info("✅ [BLE] did discover legacy LOGRADIO (Notify) characteristic for Meshtastic by \(peripheral.name ?? "Unknown", privacy: .public)")
				characteristicLogRadioLegacy = characteristic
				peripheral.setNotifyValue(true, for: characteristic)
				
			case BluetoothUUID.logRadio:
				Logger.services.info("✅ [BLE] did discover LOGRADIO (Notify) characteristic for Meshtastic by \(peripheral.name ?? "Unknown", privacy: .public)")
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
			sendWantConfig()
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
			guard let value = characteristic.value, !value.isEmpty else {
				return
			}

			if let logRecord = try? LogRecord(serializedData: value) {
				handleRadioLog(
					"\(logRecord.level.rawValue) | [\(logRecord.source)] \(logRecord.message)"
				)
			}

		case BluetoothUUID.logRadioLegacy:
			guard let value = characteristic.value, !value.isEmpty else {
				return
			}

			if let log = String(data: value, encoding: .utf8) {
				handleRadioLog(log)
			}

		case BluetoothUUID.fromRadio:
			guard
				let value = characteristic.value,
				!value.isEmpty,
				let decodedInfo = try? FromRadio(serializedData: value),
				var connectedDevice = getConnectedDevice()
			else {
				Logger.services.error("Failed to decode `fromRadio` data")

				return
			}

			// Publish mqttClientProxyMessages received on the from radio
			if decodedInfo.payloadVariant == FromRadio.OneOf_PayloadVariant.mqttClientProxyMessage(decodedInfo.mqttClientProxyMessage)
			{
				let message = CocoaMQTTMessage(
					topic: decodedInfo.mqttClientProxyMessage.topic,
					payload: [UInt8](decodedInfo.mqttClientProxyMessage.data),
					retained: decodedInfo.mqttClientProxyMessage.retained
				)

				mqttManager.mqttClientProxy?.publish(message)
			}

			switch decodedInfo.packet.decoded.portnum {
			// Handle Any local only packets we get over BLE
			case .unknownApp:
				// MyInfo from initial connection
				if decodedInfo.myInfo.isInitialized, decodedInfo.myInfo.myNodeNum > 0 {
					if let myInfo = myInfoPacket(
						myInfo: decodedInfo.myInfo,
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
				if decodedInfo.nodeInfo.num > 0 {
					if
						let nodeInfo = nodeInfoPacket(
							nodeInfo: decodedInfo.nodeInfo,
							channel: decodedInfo.packet.channel,
							context: context
						),
						connectedDevice.num == nodeInfo.num,
						let user = nodeInfo.user
					{
						connectedDevice.shortName = user.shortName ?? "?"
						connectedDevice.longName = user.longName ?? "unknown".localized
					}
				}

				// Channels
				if decodedInfo.channel.isInitialized {
					channelPacket(
						channel: decodedInfo.channel,
						fromNum: Int64(truncatingIfNeeded: connectedDevice.num),
						context: context
					)
				}

				// Config
				if decodedInfo.config.isInitialized, !isInvalidFwVersion {
					localConfig(
						config: decodedInfo.config,
						context: context,
						nodeNum: Int64(truncatingIfNeeded: connectedDevice.num),
						nodeLongName: self.deviceConnected.longName
					)
				}

				// Module Config
				if decodedInfo.moduleConfig.isInitialized, !isInvalidFwVersion, connectedDevice.num != 0 {
					moduleConfig(
						config: decodedInfo.moduleConfig,
						context: context,
						nodeNum: Int64(truncatingIfNeeded: connectedDevice.num),
						nodeLongName: self.deviceConnected.longName
					)

					if
						decodedInfo.moduleConfig.payloadVariant == ModuleConfig.OneOf_PayloadVariant.cannedMessage(decodedInfo.moduleConfig.cannedMessage)
					{
						if decodedInfo.moduleConfig.cannedMessage.enabled {
							_ = getCannedMessageModuleMessages(
								destNum: connectedDevice.num,
								wantResponse: true
							)
						}
					}
				}

				// Device Metadata
				if decodedInfo.metadata.firmwareVersion.count > 0, !isInvalidFwVersion {
					deviceConnected?.firmwareVersion = decodedInfo.metadata.firmwareVersion

					deviceMetadataPacket(
						metadata: decodedInfo.metadata,
						fromNum: connectedDevice.num,
						context: context
					)

					let lastDotIndex = decodedInfo.metadata.firmwareVersion.lastIndex(of: ".")
					if lastDotIndex == nil {
						isInvalidFwVersion = true
						connectedVersion = "0.0.0"
					}
					else {
						let version = decodedInfo.metadata.firmwareVersion[
							...(lastDotIndex ?? String.Index(utf16Offset: 6, in: decodedInfo.metadata.firmwareVersion))
						]

						connectedVersion = String(version.dropLast())
						UserDefaults.firmwareVersion = connectedVersion
					}

					let supportedVersion = connectedVersion == "0.0.0"
					|| self.minimumVersion.compare(connectedVersion, options: .numeric) == .orderedAscending
					|| minimumVersion.compare(connectedVersion, options: .numeric) == .orderedSame

					if !supportedVersion {
						isInvalidFwVersion = true
						lastConnectionError = "🚨" + "update.firmware".localized

						return
					}
				}

			case .textMessageApp, .detectionSensorApp:
				textMessageAppPacket(
					packet: decodedInfo.packet,
					wantRangeTestPackets: wantRangeTestPackets,
					connectedNode: (connectedDevice.num),
					context: context,
					appState: appState
				)

			case .positionApp:
				upsertPositionPacket(packet: decodedInfo.packet, context: context)

			case .waypointApp:
				waypointPacket(packet: decodedInfo.packet, context: context)

			case .nodeinfoApp:
				if !isInvalidFwVersion {
					upsertNodeInfoPacket(packet: decodedInfo.packet, context: context)
				}

			case .routingApp:
				if !isInvalidFwVersion {
					routingPacket(
						packet: decodedInfo.packet,
						connectedNodeNum: connectedDevice.num,
						context: context
					)
				}

			case .adminApp:
				adminAppPacket(packet: decodedInfo.packet, context: context)

			case .replyApp:
				MeshLogger.log("🕸️ MESH PACKET received for Reply App handling as a text message")

				textMessageAppPacket(
					packet: decodedInfo.packet,
					wantRangeTestPackets: wantRangeTestPackets,
					connectedNode: connectedDevice.num,
					context: context,
					appState: appState
				)

			case .storeForwardApp:
				if wantStoreAndForwardPackets {
					storeAndForwardPacket(
						packet: decodedInfo.packet,
						connectedNodeNum: connectedDevice.num,
						context: context
					)
				}
				else {
					MeshLogger.log(
						"🕸️ MESH PACKET received for Store and Forward App - Store and Forward is disabled."
					)
				}

			case .rangeTestApp:
				if wantRangeTestPackets {
					textMessageAppPacket(
						packet: decodedInfo.packet,
						wantRangeTestPackets: true,
						connectedNode: connectedDevice.num,
						context: context,
						appState: appState
					)
				} else {
					MeshLogger.log(
						"🕸️ MESH PACKET received for Range Test App Range testing is disabled."
					)
				}

			case .telemetryApp:
				if !isInvalidFwVersion {
					telemetryPacket(
						packet: decodedInfo.packet,
						connectedNode: connectedDevice.num,
						context: context
					)
				}

			case .tracerouteApp:
				if let routingMessage = try? RouteDiscovery(serializedData: decodedInfo.packet.decoded.payload) {
					let traceRoute = getTraceRoute(id: Int64(decodedInfo.packet.decoded.requestID), context: context)
					traceRoute?.response = true
					traceRoute?.route = routingMessage.route

					if routingMessage.route.count == 0 {
						let logString = String.localizedStringWithFormat("mesh.log.traceroute.received.direct %@".localized, String(decodedInfo.packet.from))
						MeshLogger.log("🪧 \(logString)")
					}
					else {
						var routeString = "You --> "
						var hopNodes: [TraceRouteHopEntity] = []

						for node in routingMessage.route {
							var hopNode = getNodeInfo(id: Int64(node), context: context)

							if hopNode == nil && hopNode?.num ?? 0 > 0 && node != 4294967295 {
								hopNode = createNodeInfo(num: Int64(node), context: context)
							}

							let traceRouteHop = TraceRouteHopEntity(context: context)
							traceRouteHop.time = Date()

							if hopNode?.hasPositions ?? false {
								traceRoute?.hasPositions = true
								if let mostRecent = hopNode?.positions?.lastObject as? PositionEntity, mostRecent.time! >= Calendar.current.date(byAdding: .minute, value: -60, to: Date())! {
									traceRouteHop.altitude = mostRecent.altitude
									traceRouteHop.latitudeI = mostRecent.latitudeI
									traceRouteHop.longitudeI = mostRecent.longitudeI
									traceRouteHop.name = hopNode?.user?.longName ?? "unknown".localized
								} else {
									traceRoute?.hasPositions = false
								}
							} else {
								traceRoute?.hasPositions = false
							}

							traceRouteHop.num = hopNode?.num ?? 0

							if let hopNode {
								if decodedInfo.packet.rxTime > 0 {
									hopNode.lastHeard = Date(
										timeIntervalSince1970: TimeInterval(Int64(decodedInfo.packet.rxTime))
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
							Logger.data.info("💾 Saved Trace Route")
						} catch {
							context.rollback()

							let nsError = error as NSError
							Logger.data.error("Error Updating Core Data TraceRouteHOp: \(nsError, privacy: .public)")
						}

						let logString = String.localizedStringWithFormat("mesh.log.traceroute.received.route %@".localized, routeString)
						MeshLogger.log("🪧 \(logString)")
					}
				}

			case .paxcounterApp:
				paxCounterPacket(packet: decodedInfo.packet, context: context)
				
			default:
				MeshLogger.log("Received unhandled packet")
			}

			if decodedInfo.configCompleteID != 0, decodedInfo.configCompleteID == configNonce {
				Logger.mesh.info("🤜 [BLE] Want Config Complete. ID:\(decodedInfo.configCompleteID)")

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
						else {
							if mqttProxyConnected {
								mqttManager.mqttClientProxy?.disconnect()
							}
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
}
// swiftlint:enable all
