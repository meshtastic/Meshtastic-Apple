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
			disconnectPeripheral()
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
	
	func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
		
		if let error {
			
			Logger.services.error("🚫 [BLE] didUpdateValueFor Characteristic error \(error.localizedDescription, privacy: .public)")
			let errorCode = (error as NSError).code
			if errorCode == 5 || errorCode == 15 {
				// BLE PIN connection errors
				// 5 CBATTErrorDomain Code=5 "Authentication is insufficient."
				// 15 CBATTErrorDomain Code=15 "Encryption is insufficient."
				lastConnectionError = "🚨" + String.localizedStringWithFormat("ble.errorcode.pin %@".localized, error.localizedDescription)
				Logger.services.error("🚫 [BLE] \(error.localizedDescription, privacy: .public) Please try connecting again and check the PIN carefully.")
				self.disconnectPeripheral(reconnect: false)
			}
			return
		}
		
		switch characteristic.uuid {
		case BluetoothUUID.logRadio:
			if characteristic.value == nil || characteristic.value!.isEmpty {
				return
			}
			do {
				let logRecord = try LogRecord(serializedData: characteristic.value!)
				var message = logRecord.source.isEmpty ? logRecord.message : "[\(logRecord.source)] \(logRecord.message)"
				switch logRecord.level {
				case .debug:
					message = "DEBUG | \(message)"
				case .info:
					message = "INFO  | \(message)"
				case .warning:
					message = "WARN  | \(message)"
				case .error:
					message = "ERROR | \(message)"
				case .critical:
					message = "CRIT  | \(message)"
				default:
					message = "DEBUG | \(message)"
				}
				handleRadioLog(radioLog: message)
			} catch {
				// Ignore fail to parse as LogRecord
			}
			
		case BluetoothUUID.logRadioLegacy:
			if characteristic.value == nil || characteristic.value!.isEmpty {
				return
			}
			if let log = String(data: characteristic.value!, encoding: .utf8) {
				handleRadioLog(radioLog: log)
			}
			
		case BluetoothUUID.fromRadio:
			
			if characteristic.value == nil || characteristic.value!.isEmpty {
				return
			}
			var decodedInfo = FromRadio()
			
			do {
				decodedInfo = try FromRadio(serializedData: characteristic.value!)
				
			} catch {
				Logger.services.error("💥 \(error.localizedDescription, privacy: .public) \(characteristic.value!, privacy: .public)")
			}
			
			// Publish mqttClientProxyMessages received on the from radio
			if decodedInfo.payloadVariant == FromRadio.OneOf_PayloadVariant.mqttClientProxyMessage(decodedInfo.mqttClientProxyMessage) {
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
				var nowKnown = false
				
				// MyInfo from initial connection
				if decodedInfo.myInfo.isInitialized && decodedInfo.myInfo.myNodeNum > 0 {
					let myInfo = myInfoPacket(myInfo: decodedInfo.myInfo, peripheralId: self.connectedPeripheral.id, context: context)
					
					if myInfo != nil {
						UserDefaults.preferredPeripheralNum = Int(myInfo?.myNodeNum ?? 0)
						connectedPeripheral.num = myInfo?.myNodeNum ?? 0
						connectedPeripheral.name = myInfo?.bleName ?? "unknown".localized
						connectedPeripheral.longName = myInfo?.bleName ?? "unknown".localized
						let newConnection = Int64(UserDefaults.preferredPeripheralNum) != Int64(decodedInfo.myInfo.myNodeNum)
						if newConnection {
							let container = NSPersistentContainer(name: "Meshtastic")
							if let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
								let databasePath = url.appendingPathComponent("backup")
									.appendingPathComponent("\(UserDefaults.preferredPeripheralNum)")
									.appendingPathComponent("Meshtastic.sqlite")
								if FileManager.default.fileExists(atPath: databasePath.path) {
									do {
										disconnectPeripheral(reconnect: false)
										try container.restorePersistentStore(from: databasePath)
										context.refreshAllObjects()
										let request = MyInfoEntity.fetchRequest()
										try context.fetch(request)
										UserDefaults.preferredPeripheralNum = Int(myInfo?.myNodeNum ?? 0)
										connectTo(peripheral: peripheral)
										Logger.data.notice("🗂️ Restored Core data for /\(UserDefaults.preferredPeripheralNum, privacy: .public)")
									} catch {
										Logger.data.error("🗂️ Restore Core data copy error: \(error, privacy: .public)")
									}
								}
							}
						}
					}
					tryClearExistingChannels()
				}
				// NodeInfo
				if decodedInfo.nodeInfo.num > 0 {
					nowKnown = true
					if let nodeInfo = nodeInfoPacket(nodeInfo: decodedInfo.nodeInfo, channel: decodedInfo.packet.channel, context: context) {
						if self.connectedPeripheral != nil && self.connectedPeripheral.num == nodeInfo.num {
							if nodeInfo.user != nil {
								connectedPeripheral.shortName = nodeInfo.user?.shortName ?? "?"
								connectedPeripheral.longName = nodeInfo.user?.longName ?? "unknown".localized
							}
						}
					}
				}
				// Channels
				if decodedInfo.channel.isInitialized && connectedPeripheral != nil {
					nowKnown = true
					channelPacket(channel: decodedInfo.channel, fromNum: Int64(truncatingIfNeeded: connectedPeripheral.num), context: context)
				}
				// Config
				if decodedInfo.config.isInitialized && !invalidVersion && connectedPeripheral != nil {
					nowKnown = true
					localConfig(config: decodedInfo.config, context: context, nodeNum: Int64(truncatingIfNeeded: self.connectedPeripheral.num), nodeLongName: self.connectedPeripheral.longName)
				}
				// Module Config
				if decodedInfo.moduleConfig.isInitialized && !invalidVersion && self.connectedPeripheral?.num != 0 {
					nowKnown = true
					moduleConfig(config: decodedInfo.moduleConfig, context: context, nodeNum: Int64(truncatingIfNeeded: self.connectedPeripheral?.num ?? 0), nodeLongName: self.connectedPeripheral.longName)
					if decodedInfo.moduleConfig.payloadVariant == ModuleConfig.OneOf_PayloadVariant.cannedMessage(decodedInfo.moduleConfig.cannedMessage) {
						if decodedInfo.moduleConfig.cannedMessage.enabled {
							_ = self.getCannedMessageModuleMessages(destNum: self.connectedPeripheral.num, wantResponse: true)
						}
					}
				}
				// Device Metadata
				if decodedInfo.metadata.firmwareVersion.count > 0 && !invalidVersion {
					nowKnown = true
					deviceMetadataPacket(metadata: decodedInfo.metadata, fromNum: connectedPeripheral.num, context: context)
					connectedPeripheral.firmwareVersion = decodedInfo.metadata.firmwareVersion
					let lastDotIndex = decodedInfo.metadata.firmwareVersion.lastIndex(of: ".")
					if lastDotIndex == nil {
						invalidVersion = true
						connectedVersion = "0.0.0"
					} else {
						let version = decodedInfo.metadata.firmwareVersion[...(lastDotIndex ?? String.Index(utf16Offset: 6, in: decodedInfo.metadata.firmwareVersion))]
						nowKnown = true
						connectedVersion = String(version.dropLast())
						UserDefaults.firmwareVersion = connectedVersion
					}
					let supportedVersion = connectedVersion == "0.0.0" ||  self.minimumVersion.compare(connectedVersion, options: .numeric) == .orderedAscending || minimumVersion.compare(connectedVersion, options: .numeric) == .orderedSame
					if !supportedVersion {
						invalidVersion = true
						lastConnectionError = "🚨" + "update.firmware".localized
						return
					}
				}
				// Log any other unknownApp calls
				if !nowKnown { MeshLogger.log("🕸️ MESH PACKET received for Unknown App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure")") }
			case .textMessageApp, .detectionSensorApp:
				textMessageAppPacket(
					packet: decodedInfo.packet,
					wantRangeTestPackets: wantRangeTestPackets,
					connectedNode: (self.connectedPeripheral != nil ? connectedPeripheral.num : 0),
					context: context,
					appState: appState
				)
			case .remoteHardwareApp:
				MeshLogger.log("🕸️ MESH PACKET received for Remote Hardware App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure")")
			case .positionApp:
				upsertPositionPacket(packet: decodedInfo.packet, context: context)
			case .waypointApp:
				waypointPacket(packet: decodedInfo.packet, context: context)
			case .nodeinfoApp:
				if !invalidVersion { upsertNodeInfoPacket(packet: decodedInfo.packet, context: context) }
			case .routingApp:
				if !invalidVersion { routingPacket(packet: decodedInfo.packet, connectedNodeNum: self.connectedPeripheral.num, context: context) }
			case .adminApp:
				adminAppPacket(packet: decodedInfo.packet, context: context)
			case .replyApp:
				MeshLogger.log("🕸️ MESH PACKET received for Reply App handling as a text message")
				textMessageAppPacket(
					packet: decodedInfo.packet,
					wantRangeTestPackets: wantRangeTestPackets,
					connectedNode: (self.connectedPeripheral != nil ? connectedPeripheral.num : 0),
					context: context,
					appState: appState
				)
			case .ipTunnelApp:
				// MeshLogger.log("🕸️ MESH PACKET received for IP Tunnel App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure")")
				MeshLogger.log("🕸️ MESH PACKET received for IP Tunnel App UNHANDLED UNHANDLED")
			case .serialApp:
				// MeshLogger.log("🕸️ MESH PACKET received for Serial App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure")")
				MeshLogger.log("🕸️ MESH PACKET received for Serial App UNHANDLED UNHANDLED")
			case .storeForwardApp:
				if wantStoreAndForwardPackets {
					storeAndForwardPacket(packet: decodedInfo.packet, connectedNodeNum: (self.connectedPeripheral != nil ? connectedPeripheral.num : 0), context: context)
				} else {
					MeshLogger.log("🕸️ MESH PACKET received for Store and Forward App - Store and Forward is disabled.")
				}
			case .rangeTestApp:
				if wantRangeTestPackets {
					textMessageAppPacket(
						packet: decodedInfo.packet,
						wantRangeTestPackets: true,
						connectedNode: (self.connectedPeripheral != nil ? connectedPeripheral.num : 0),
						context: context,
						appState: appState
					)
				} else {
					MeshLogger.log("🕸️ MESH PACKET received for Range Test App Range testing is disabled.")
				}
			case .telemetryApp:
				if !invalidVersion { telemetryPacket(packet: decodedInfo.packet, connectedNode: (self.connectedPeripheral != nil ? connectedPeripheral.num : 0), context: context) }
			case .textMessageCompressedApp:
				// MeshLogger.log("🕸️ MESH PACKET received for Text Message Compressed App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure")")
				MeshLogger.log("🕸️ MESH PACKET received for Text Message Compressed App UNHANDLED")
			case .zpsApp:
				// MeshLogger.log("🕸️ MESH PACKET received for Zero Positioning System App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure")")
				MeshLogger.log("🕸️ MESH PACKET received for Zero Positioning System App UNHANDLED")
			case .privateApp:
				// MeshLogger.log("🕸️ MESH PACKET received for Private App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure")")
				MeshLogger.log("🕸️ MESH PACKET received for Private App UNHANDLED UNHANDLED")
			case .atakForwarder:
				// MeshLogger.log("🕸️ MESH PACKET received for ATAK Forwarder App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure")")
				MeshLogger.log("🕸️ MESH PACKET received for ATAK Forwarder App UNHANDLED UNHANDLED")
			case .simulatorApp:
				// MeshLogger.log("🕸️ MESH PACKET received for Simulator App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure")")
				MeshLogger.log("🕸️ MESH PACKET received for Simulator App UNHANDLED UNHANDLED")
			case .audioApp:
				// MeshLogger.log("🕸️ MESH PACKET received for Audio App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure")")
				MeshLogger.log("🕸️ MESH PACKET received for Audio App UNHANDLED UNHANDLED")
			case .tracerouteApp:
				if let routingMessage = try? RouteDiscovery(serializedData: decodedInfo.packet.decoded.payload) {
					let traceRoute = getTraceRoute(id: Int64(decodedInfo.packet.decoded.requestID), context: context)
					traceRoute?.response = true
					traceRoute?.route = routingMessage.route
					if routingMessage.route.count == 0 {
						let logString = String.localizedStringWithFormat("mesh.log.traceroute.received.direct %@".localized, String(decodedInfo.packet.from))
						MeshLogger.log("🪧 \(logString)")
						
					} else {
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
							if hopNode != nil {
								if decodedInfo.packet.rxTime > 0 {
									hopNode?.lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(decodedInfo.packet.rxTime)))
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
			case .neighborinfoApp:
				if let neighborInfo = try? NeighborInfo(serializedData: decodedInfo.packet.decoded.payload) {
					// MeshLogger.log("🕸️ MESH PACKET received for Neighbor Info App UNHANDLED")
					MeshLogger.log("🕸️ MESH PACKET received for Neighbor Info App UNHANDLED \(neighborInfo)")
				}
			case .paxcounterApp:
				paxCounterPacket(packet: decodedInfo.packet, context: context)
			case .mapReportApp:
				MeshLogger.log("🕸️ MESH PACKET received Map Report App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure")")
			case .UNRECOGNIZED:
				MeshLogger.log("🕸️ MESH PACKET received UNRECOGNIZED App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure")")
			case .max:
				Logger.services.info("MAX PORT NUM OF 511")
			case .atakPlugin:
				MeshLogger.log("🕸️ MESH PACKET received for ATAK Plugin App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure")")
			case .powerstressApp:
				MeshLogger.log("🕸️ MESH PACKET received for Power Stress App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure")")
			}
			
			if decodedInfo.configCompleteID != 0 && decodedInfo.configCompleteID == configNonce {
				invalidVersion = false
				lastConnectionError = ""
				isSubscribed = true
				Logger.mesh.info("🤜 [BLE] Want Config Complete. ID:\(decodedInfo.configCompleteID)")
				peripherals.removeAll(where: { $0.peripheral.state == CBPeripheralState.disconnected })
				// Config conplete returns so we don't read the characteristic again
				
				/// MQTT Client Proxy and RangeTest and Store and Forward interest
				if connectedPeripheral.num > 0 {
					
					let fetchNodeInfoRequest = NodeInfoEntity.fetchRequest()
					fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(connectedPeripheral.num))
					do {
						let fetchedNodeInfo = try context.fetch(fetchNodeInfoRequest)
						if fetchedNodeInfo.count == 1 {
							// Subscribe to Mqtt Client Proxy if enabled
							if fetchedNodeInfo[0].mqttConfig != nil && fetchedNodeInfo[0].mqttConfig?.enabled ?? false && fetchedNodeInfo[0].mqttConfig?.proxyToClientEnabled ?? false {
								mqttManager.connectFromConfigSettings(node: fetchedNodeInfo[0])
							} else {
								if mqttProxyConnected {
									mqttManager.mqttClientProxy?.disconnect()
								}
							}
							// Set initial unread message badge states
							appState.unreadChannelMessages = fetchedNodeInfo[0].myInfo?.unreadMessages ?? 0
							appState.unreadDirectMessages = fetchedNodeInfo[0].user?.unreadMessages ?? 0
						}
						if fetchedNodeInfo.count == 1 && fetchedNodeInfo[0].rangeTestConfig?.enabled == true {
							wantRangeTestPackets = true
						}
						if fetchedNodeInfo.count == 1 && fetchedNodeInfo[0].storeForwardConfig?.enabled == true {
							wantStoreAndForwardPackets = true
						}
						
					} catch {
						Logger.data.error("Failed to find a node info for the connected node \(error.localizedDescription)")
					}
				}
				
				// MARK: Share Location Position Update Timer
				// Use context to pass the radio name with the timer
				// Use a RunLoop to prevent the timer from running on the main UI thread
				if UserDefaults.provideLocation {
					let interval = UserDefaults.provideLocationInterval >= 10 ? UserDefaults.provideLocationInterval : 30
					positionTimer = Timer.scheduledTimer(timeInterval: TimeInterval(interval), target: self, selector: #selector(positionTimerFired), userInfo: context, repeats: true)
					if positionTimer != nil {
						RunLoop.current.add(positionTimer!, forMode: .common)
					}
				}
				return
			}
			
		case BluetoothUUID.fromNum:
			Logger.services.info("🗞️ [BLE] (Notify) characteristic value will be read next")
		default:
			Logger.services.error("🚫 Unhandled Characteristic UUID: \(characteristic.uuid, privacy: .public)")
		}
		if characteristicFromRadio != nil {
			// Either Read the config complete value or from num notify value
			peripheral.readValue(for: characteristicFromRadio)
		}
	}
}
// swiftlint:enable all
