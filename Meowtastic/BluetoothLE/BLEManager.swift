import CocoaMQTT
import CoreBluetooth
import CoreData
import Foundation
import MapKit
import MeshtasticProtobufs
import OSLog
import SwiftUI

// swiftlint:disable all
class BLEManager: NSObject, ObservableObject {
	let appState: AppState
	let context: NSManagedObjectContext
	let centralManager: CBCentralManager
	let mqttManager: MqttClientProxyManager
	let minimumVersion = "2.0.0"

	@Published
	var devices: [Device] = []
	@Published
	var deviceConnected: Device!
	@Published
	var lastConnectionError: String
	@Published
	var isInvalidFwVersion = false
	@Published
	var isSwitchedOn = false
	@Published
	var automaticallyReconnect = true
	@Published
	var mqttProxyConnected = false
	@Published
	var mqttError = ""
	
	var connectedVersion: String
	var isConnecting = false
	var isConnected = false
	var isSubscribed = false
	var configNonce: UInt32 = 1
	var timeoutTimer: Timer?
	var timeoutCount = 0
	var positionTimer: Timer?
	var wantRangeTestPackets = false
	var wantStoreAndForwardPackets = false
	var characteristicToRadio: CBCharacteristic!
	var characteristicFromRadio: CBCharacteristic!
	var characteristicFromNum: CBCharacteristic!
	var characteristicLogRadio: CBCharacteristic!
	var characteristicLogRadioLegacy: CBCharacteristic!

	init(
		appState: AppState,
		context: NSManagedObjectContext
	) {
		self.appState = appState
		self.context = context
		self.centralManager = CBCentralManager()
		self.mqttManager = MqttClientProxyManager.shared

		self.lastConnectionError = ""
		self.connectedVersion = "0.0.0"

		super.init()

		centralManager.delegate = self
		mqttManager.delegate = self
	}

	func getConnectedDevice() -> Device? {
		guard let deviceConnected, deviceConnected.peripheral.state == .connected else {
			return nil
		}

		return deviceConnected
	}

	func startScanning() {
		guard isSwitchedOn else {
			return
		}

		centralManager.scanForPeripherals(
			withServices: [BluetoothUUID.meshtasticService],
			options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
		)

		Logger.services.info("✅ [BLE] Scanning Started")
	}

	func stopScanning() {
		guard centralManager.isScanning else {
			return
		}

		centralManager.stopScan()

		Logger.services.info("🛑 [BLE] Stopped Scanning")
	}

	@objc
	private func timeoutTimerFired(timer: Timer) {
		timeoutCount += 1
		lastConnectionError = ""

		if timeoutCount >= 10 {
			if let deviceConnected {
				centralManager.cancelPeripheralConnection(deviceConnected.peripheral)
			}

			deviceConnected = nil
			isConnected = false
			isConnecting = false
			timeoutCount = 0
			timeoutTimer?.invalidate()
			lastConnectionError = "Bluetooth connection timed out"

			MeshLogger.log(lastConnectionError)

			startScanning()
		}
	}

	func connectTo(peripheral: CBPeripheral) {
		isConnecting = true
		lastConnectionError = ""
		automaticallyReconnect = true
		timeoutTimer?.invalidate()

		disconnectDevice()

		centralManager.connect(peripheral)

		let timer = Timer.scheduledTimer(
			timeInterval: 1.5,
			target: self,
			selector: #selector(timeoutTimerFired),
			userInfo: ["name": "\(peripheral.name ?? "Unknown")"],
			repeats: true
		)
		RunLoop.current.add(timer, forMode: .common)
		timeoutTimer = timer

		Logger.services.info("ℹ️ BLE Connecting: \(peripheral.name ?? "Unknown", privacy: .public)")
	}
	
	func cancelPeripheralConnection() {
		if let mqttClientProxy = mqttManager.mqttClientProxy, mqttProxyConnected {
			mqttClientProxy.disconnect()
		}

		characteristicFromRadio = nil
		isConnecting = false
		isConnected = false
		isSubscribed = false
		deviceConnected = nil
		isInvalidFwVersion = false
		connectedVersion = "0.0.0"
		deviceConnected = nil
		timeoutTimer?.invalidate()
		automaticallyReconnect = false

		stopScanning()
		startScanning()
	}

	func disconnectDevice(reconnect: Bool = true) {
		guard let deviceConnected else {
			return
		}

		if let mqttClientProxy = mqttManager.mqttClientProxy, mqttProxyConnected {
			mqttClientProxy.disconnect()
		}

		automaticallyReconnect = reconnect
		centralManager.cancelPeripheralConnection(deviceConnected.peripheral)
		characteristicFromRadio = nil
		isConnected = false
		isSubscribed = false
		isInvalidFwVersion = false
		connectedVersion = "0.0.0"

		stopScanning()
		startScanning()
	}

	@discardableResult
	func sendTraceRouteRequest(destNum: Int64, wantResponse: Bool) -> Bool {
		guard let connectedDevice = getConnectedDevice() else {
			return false
		}

		guard let serializedData = try? RouteDiscovery().serializedData() else {
			return false
		}

		var dataMessage = DataMessage()
		dataMessage.payload = serializedData
		dataMessage.portnum = PortNum.tracerouteApp
		dataMessage.wantResponse = true

		var meshPacket = MeshPacket()
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.to = UInt32(destNum)
		meshPacket.from = UInt32(connectedDevice.num)
		meshPacket.wantAck = true
		meshPacket.decoded = dataMessage

		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket

		guard let binaryData = try? toRadio.serializedData() else {
			return false
		}

		if let connectedDevice = getConnectedDevice() {
			connectedDevice.peripheral.writeValue(
				binaryData,
				for: characteristicToRadio,
				type: .withResponse
			)

			let nodeRequest = NodeInfoEntity.fetchRequest()
			nodeRequest.predicate = NSPredicate(
				format: "num IN %@",
				[destNum, connectedDevice.num]
			)

			guard let nodes = try? context.fetch(nodeRequest) else {
				return false
			}

			let receivingNode = nodes.first(where: {
				$0.num == destNum
			})
			let connectedNode = nodes.first(where: {
				$0.num == connectedDevice.num
			})

			let traceRoute = TraceRouteEntity(context: context)
			traceRoute.id = Int64(meshPacket.id)
			traceRoute.time = Date()
			traceRoute.node = receivingNode

			let lastDay = Calendar.current.date(byAdding: .hour, value: -24, to: Date.now)!
			if
				let positions = connectedNode?.positions,
				let mostRecent = positions.lastObject as? PositionEntity,
				let time = mostRecent.time,
				time >= lastDay
			{
				traceRoute.altitude = mostRecent.altitude
				traceRoute.latitudeI = mostRecent.latitudeI
				traceRoute.longitudeI = mostRecent.longitudeI
				traceRoute.hasPositions = true
			}

			do {
				try context.save()

				Logger.data.info(
					"💾 Saved TraceRoute sent to node: \(String(receivingNode?.user?.longName ?? "unknown".localized), privacy: .public)"
				)

				return true
			} catch {
				context.rollback()

				let nsError = error as NSError
				Logger.data.error("Error Updating Core Data BluetoothConfigEntity: \(nsError, privacy: .public)")
			}
		}

		return false
	}

	func sendWantConfig() {
		guard let connectedDevice = getConnectedDevice() else {
			return
		}

		guard let characteristicFromRadio else {
			MeshLogger.log("🚨 \("firmware.version.unsupported".localized)")
			isInvalidFwVersion = true
			return
		}

		var toRadio = ToRadio()
		configNonce += 1
		toRadio.wantConfigID = configNonce

		guard let binaryData: Data = try? toRadio.serializedData() else {
			return
		}

		connectedDevice.peripheral.writeValue(
			binaryData,
			for: characteristicToRadio,
			type: .withResponse
		)

		connectedDevice.peripheral.readValue(for: characteristicFromRadio)
	}

	func sendMessage(
		message: String,
		toUserNum: Int64,
		channel: Int32,
		isEmoji: Bool,
		replyID: Int64
	) -> Bool {
		var success = false

		// Return false if we are not properly connected to a device, handle retry logic in the view for now
		if deviceConnected == nil || deviceConnected!.peripheral.state != .connected {
			disconnectDevice()
			startScanning()
			
			// Try and connect to the preferredPeripherial first
			let preferredPeripheral = devices.filter({ $0.peripheral.identifier.uuidString == UserDefaults.preferredPeripheralId as String }).first
			if preferredPeripheral != nil && preferredPeripheral?.peripheral != nil {
				connectTo(peripheral: preferredPeripheral!.peripheral)
			}
			let nodeName = deviceConnected?.peripheral.name ?? "unknown".localized
			let logString = String.localizedStringWithFormat("mesh.log.textmessage.send.failed %@".localized, nodeName)
			MeshLogger.log("🚫 \(logString)")
			
			success = false
		} else if message.count < 1 {
			
			// Don't send an empty message
			Logger.mesh.info("🚫 Don't Send an Empty Message")
			success = false
			
		} else {
			let fromUserNum: Int64 = self.deviceConnected.num
			
			let messageUsers = UserEntity.fetchRequest()
			messageUsers.predicate = NSPredicate(format: "num IN %@", [fromUserNum, Int64(toUserNum)])
			
			do {
				
				let fetchedUsers = try context.fetch(messageUsers)
				if fetchedUsers.isEmpty {
					
					Logger.data.error("🚫 Message Users Not Found, Fail")
					success = false
				} else if fetchedUsers.count >= 1 {
					
					let newMessage = MessageEntity(context: context)
					newMessage.messageId = Int64(UInt32.random(in: UInt32(UInt8.max)..<UInt32.max))
					newMessage.messageTimestamp =  Int32(Date().timeIntervalSince1970)
					newMessage.receivedACK = false
					newMessage.read = true
					if toUserNum > 0 {
						newMessage.toUser = fetchedUsers.first(where: { $0.num == toUserNum })
						newMessage.toUser?.lastMessage = Date()
					}
					newMessage.fromUser = fetchedUsers.first(where: { $0.num == fromUserNum })
					newMessage.isEmoji = isEmoji
					newMessage.admin = false
					newMessage.channel = channel
					if replyID > 0 {
						newMessage.replyID = replyID
					}
					newMessage.messagePayload = message
					newMessage.messagePayloadMarkdown = generateMessageMarkdown(message: message)
					newMessage.read = true
					
					let dataType = PortNum.textMessageApp
					var messageQuotesReplaced = message.replacingOccurrences(of: "’", with: "'")
					messageQuotesReplaced = message.replacingOccurrences(of: "”", with: "\"")
					let payloadData: Data = messageQuotesReplaced.data(using: String.Encoding.utf8)!
					
					var dataMessage = DataMessage()
					dataMessage.payload = payloadData
					dataMessage.portnum = dataType
					
					var meshPacket = MeshPacket()
					meshPacket.id = UInt32(newMessage.messageId)
					if toUserNum > 0 {
						meshPacket.to = UInt32(toUserNum)
					} else {
						meshPacket.to = Constants.maximumNodeNum
					}
					meshPacket.channel = UInt32(channel)
					meshPacket.from	= UInt32(fromUserNum)
					meshPacket.decoded = dataMessage
					meshPacket.decoded.emoji = isEmoji ? 1 : 0
					if replyID > 0 {
						meshPacket.decoded.replyID = UInt32(replyID)
					}
					meshPacket.wantAck = true
					
					var toRadio: ToRadio!
					toRadio = ToRadio()
					toRadio.packet = meshPacket
					guard let binaryData: Data = try? toRadio.serializedData() else {
						return false
					}
					if let connectedDevice = getConnectedDevice() {
						connectedDevice.peripheral.writeValue(
							binaryData,
							for: characteristicToRadio,
							type: .withResponse
						)

						do {
							try context.save()
							Logger.data.info("💾 Saved a new sent message from \(self.deviceConnected.num.toHex(), privacy: .public) to \(toUserNum.toHex(), privacy: .public)")
							success = true
						} catch {
							context.rollback()
							let nsError = error as NSError
							Logger.data.error("Unresolved Core Data error in Send Message Function your database is corrupted running a node db reset should clean up the data. Error: \(nsError, privacy: .public)")
						}
					}
				}
			} catch {
				Logger.data.error("💥 Send message failure \(self.deviceConnected.num.toHex(), privacy: .public) to \(toUserNum.toHex(), privacy: .public)")
			}
		}
		return success
	}
	
	func sendWaypoint(waypoint: Waypoint) -> Bool {
		if waypoint.latitudeI == 373346000 && waypoint.longitudeI == -1220090000 {
			return false
		}
		var success = false
		let fromNodeNum = UInt32(deviceConnected.num)
		var meshPacket = MeshPacket()
		meshPacket.to = Constants.maximumNodeNum
		meshPacket.from	= fromNodeNum
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		do {
			dataMessage.payload = try waypoint.serializedData()
		} catch {
			// Could not serialiaze the payload
			return false
		}
		
		dataMessage.portnum = PortNum.waypointApp
		meshPacket.decoded = dataMessage
		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket
		guard let binaryData: Data = try? toRadio.serializedData() else {
			return false
		}
		let logString = String.localizedStringWithFormat("mesh.log.waypoint.sent %@".localized, String(fromNodeNum))
		MeshLogger.log("📍 \(logString)")
		if let connectedDevice = getConnectedDevice() {
			connectedDevice.peripheral.writeValue(
				binaryData,
				for: characteristicToRadio,
				type: .withResponse
			)

			success = true

			let wayPointEntity = getWaypoint(id: Int64(waypoint.id), context: context)
			wayPointEntity.id = Int64(waypoint.id)
			wayPointEntity.name = waypoint.name.count >= 1 ? waypoint.name : "Dropped Pin"
			wayPointEntity.longDescription = waypoint.description_p
			wayPointEntity.icon	= Int64(waypoint.icon)
			wayPointEntity.latitudeI = waypoint.latitudeI
			wayPointEntity.longitudeI = waypoint.longitudeI
			if waypoint.expire > 1 {
				wayPointEntity.expire = Date.init(timeIntervalSince1970: Double(waypoint.expire))
			} else {
				wayPointEntity.expire = nil
			}
			if waypoint.lockedTo > 0 {
				wayPointEntity.locked = Int64(waypoint.lockedTo)
			} else {
				wayPointEntity.locked = 0
			}
			if wayPointEntity.created == nil {
				wayPointEntity.created = Date()
			} else {
				wayPointEntity.lastUpdated = Date()
			}
			do {
				try context.save()
				Logger.data.info("💾 Updated Waypoint from Waypoint App Packet From: \(fromNodeNum.toHex(), privacy: .public)")
			} catch {
				context.rollback()
				let nsError = error as NSError
				Logger.data.error("Error Saving NodeInfoEntity from WAYPOINT_APP \(nsError, privacy: .public)")
			}
		}
		return success
	}
	
	func getPhonePosition() -> Position? {
		guard let lastLocation = LocationsHandler.shared.locationsArray.last else {
			return nil
		}

		let timestamp = lastLocation.timestamp

		var positionPacket = Position()
		positionPacket.time = UInt32(timestamp.timeIntervalSince1970)
		positionPacket.timestamp = UInt32(timestamp.timeIntervalSince1970)
		positionPacket.latitudeI = Int32(lastLocation.coordinate.latitude * 1e7)
		positionPacket.longitudeI = Int32(lastLocation.coordinate.longitude * 1e7)
		positionPacket.altitude = Int32(lastLocation.altitude)
		positionPacket.satsInView = UInt32(0)

		let currentSpeed = lastLocation.speed
		if currentSpeed > 0, !currentSpeed.isNaN || !currentSpeed.isInfinite {
			positionPacket.groundSpeed = UInt32(currentSpeed)
		}

		let currentHeading = lastLocation.course
		if currentHeading > 0, currentHeading <= 360, !currentHeading.isNaN || !currentHeading.isInfinite {
			positionPacket.groundTrack = UInt32(currentHeading)
		}

		return positionPacket
	}

	@discardableResult
	func sendPosition(channel: Int32, destNum: Int64, wantResponse: Bool) -> Bool {
		guard
			let connectedDevice = getConnectedDevice(),
			let positionPacket = getPhonePosition()
		else {
			return false
		}

		var meshPacket = MeshPacket()
		meshPacket.to = UInt32(destNum)
		meshPacket.channel = UInt32(channel)
		meshPacket.from = UInt32(connectedDevice.num)

		var dataMessage = DataMessage()
		if let serializedData: Data = try? positionPacket.serializedData() {
			dataMessage.payload = serializedData
			dataMessage.portnum = PortNum.positionApp
			dataMessage.wantResponse = wantResponse
			meshPacket.decoded = dataMessage
		} else {
			Logger.services.error("Failed to serialize position packet data")
			return false
		}
		
		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket

		guard let binaryData: Data = try? toRadio.serializedData() else {
			Logger.services.error("Failed to serialize position packet")
			return false
		}

		connectedDevice.peripheral.writeValue(
			binaryData,
			for: characteristicToRadio,
			type: .withResponse
		)

		Logger.services.debug("📍 Location shared from \(connectedDevice.num)")

		return true
	}

	@objc
	func positionTimerFired(timer: Timer) {
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

	func connectToPreferredPeripheral() -> Bool {
		if getConnectedDevice() != nil {
			disconnectDevice()
			startScanning()

			// Try and connect to the preferredPeripherial first
			let preferredPeripheral = devices.first(where: { device in
				guard let preferred = UserDefaults.standard.object(forKey: "preferredPeripheralId") as? String else {
					return false
				}

				return device.peripheral.identifier.uuidString == preferred
			})

			if let peripheral = preferredPeripheral?.peripheral {
				connectTo(peripheral: peripheral)

				return true
			}
		} else if deviceConnected != nil, isSubscribed {
			return true
		}

		return false
	}

	func saveChannelSet(base64UrlString: String, addChannels: Bool = false) -> Bool {
		if isConnected {
			var i: Int32 = 0
			var myInfo: MyInfoEntity
			// Before we get started delete the existing channels from the myNodeInfo
			if !addChannels {
				tryClearExistingChannels()
			}
			
			let decodedString = base64UrlString.base64urlToBase64()
			if let decodedData = Data(base64Encoded: decodedString) {
				do {
					let channelSet: ChannelSet = try ChannelSet(serializedData: decodedData)
					for cs in channelSet.settings {
						if addChannels {
							// We are trying to add a channel so lets get the last index
							let fetchMyInfoRequest = MyInfoEntity.fetchRequest()
							fetchMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", Int64(deviceConnected.num))
							do {
								let fetchedMyInfo = try context.fetch(fetchMyInfoRequest)
								if fetchedMyInfo.count == 1 {
									i = Int32(fetchedMyInfo[0].channels?.count ?? -1)
									myInfo = fetchedMyInfo[0]
									// Bail out if the index is negative or bigger than our max of 8
									if i < 0 || i > 8 {
										return false
									}
									// Bail out if there are no channels or if the same channel name already exists
									guard let mutableChannels = myInfo.channels!.mutableCopy() as? NSMutableOrderedSet else {
										return false
									}
									if mutableChannels.first(where: {($0 as AnyObject).name == cs.name }) is ChannelEntity {
										return false
									}
								}
							} catch {
								Logger.data.error("Failed to find a node MyInfo to save these channels to: \(error.localizedDescription)")
							}
						}
						
						var chan = Channel()
						if i == 0 {
							chan.role = Channel.Role.primary
						} else {
							chan.role = Channel.Role.secondary
						}
						chan.settings = cs
						chan.index = i
						i += 1
						
						var adminPacket = AdminMessage()
						adminPacket.setChannel = chan
						var meshPacket: MeshPacket = MeshPacket()
						meshPacket.to = UInt32(deviceConnected.num)
						meshPacket.from	= UInt32(deviceConnected.num)
						meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
						meshPacket.priority =  MeshPacket.Priority.reliable
						meshPacket.wantAck = true
						meshPacket.channel = 0
						var dataMessage = DataMessage()
						guard let adminData: Data = try? adminPacket.serializedData() else {
							return false
						}
						dataMessage.payload = adminData
						dataMessage.portnum = PortNum.adminApp
						meshPacket.decoded = dataMessage
						var toRadio: ToRadio!
						toRadio = ToRadio()
						toRadio.packet = meshPacket
						guard let binaryData: Data = try? toRadio.serializedData() else {
							return false
						}
						if let connectedDevice = getConnectedDevice() {
							connectedDevice.peripheral.writeValue(
								binaryData,
								for: characteristicToRadio,
								type: .withResponse
							)
						}
					}

					// Save the LoRa Config and the device will reboot
					var adminPacket = AdminMessage()
					adminPacket.setConfig.lora = channelSet.loraConfig
					var meshPacket: MeshPacket = MeshPacket()
					meshPacket.to = UInt32(deviceConnected.num)
					meshPacket.from	= UInt32(deviceConnected.num)
					meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
					meshPacket.priority =  MeshPacket.Priority.reliable
					meshPacket.wantAck = true
					meshPacket.channel = 0
					var dataMessage = DataMessage()
					guard let adminData: Data = try? adminPacket.serializedData() else {
						return false
					}
					dataMessage.payload = adminData
					dataMessage.portnum = PortNum.adminApp
					meshPacket.decoded = dataMessage
					var toRadio: ToRadio!
					toRadio = ToRadio()
					toRadio.packet = meshPacket
					guard let binaryData: Data = try? toRadio.serializedData() else {
						return false
					}
					if let connectedDevice = getConnectedDevice() {
						connectedDevice.peripheral.writeValue(
							binaryData,
							for: characteristicToRadio,
							type: .withResponse
						)
					}
					
					if deviceConnected != nil {
						sendWantConfig()
						return true
					}
				} catch {
					return false
				}
			}
		}
		return false
	}
	
	func removeNode(node: NodeInfoEntity, connectedNodeNum: Int64) -> Bool {
		var adminPacket = AdminMessage()
		adminPacket.removeByNodenum = UInt32(node.num)
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(connectedNodeNum)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		if let serializedData: Data = try? adminPacket.serializedData() {
			dataMessage.payload = serializedData
			dataMessage.portnum = PortNum.adminApp
			meshPacket.decoded = dataMessage
		} else {
			return false
		}
		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket
		guard let binaryData: Data = try? toRadio.serializedData() else {
			return false
		}
		
		if let connectedDevice = getConnectedDevice() {
			connectedDevice.peripheral.writeValue(
				binaryData,
				for: characteristicToRadio,
				type: .withResponse
			)

			connectedDevice.peripheral.writeValue(
				binaryData,
				for: characteristicToRadio,
				type: .withResponse
			)

			context.delete(node.user!)
			context.delete(node)

			do {
				try context.save()
				return true
			} catch {
				context.rollback()
				let nsError = error as NSError
				Logger.data.error("🚫 Error deleting node from core data: \(nsError)")
			}
		}
		return false
	}
	
	func storeAndForwardPacket(
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
	
	func tryClearExistingChannels() {
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
