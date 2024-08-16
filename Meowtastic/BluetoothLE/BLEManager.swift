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
	
	@Published var peripherals: [Peripheral] = []
	@Published var connectedPeripheral: Peripheral!
	@Published var lastConnectionError: String
	@Published var invalidVersion = false
	@Published var isSwitchedOn: Bool = false
	@Published var automaticallyReconnect: Bool = true
	@Published var mqttProxyConnected: Bool = false
	@Published var mqttError: String = ""
	
	var minimumVersion = "2.0.0"
	var connectedVersion: String
	var isConnecting: Bool = false
	var isConnected: Bool = false
	var isSubscribed: Bool = false
	var configNonce: UInt32 = 1
	var timeoutTimer: Timer?
	var timeoutTimerCount = 0
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
	
	func startScanning() {
		if isSwitchedOn {
			centralManager.scanForPeripherals(withServices: [BluetoothUUID.meshtasticService], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
			Logger.services.info("✅ [BLE] Scanning Started")
		}
	}
	
	func stopScanning() {
		if centralManager.isScanning {
			centralManager.stopScan()
			Logger.services.info("🛑 [BLE] Stopped Scanning")
		}
	}
	
	@objc
	func timeoutTimerFired(timer: Timer) {
		guard let timerContext = timer.userInfo as? [String: String] else { return }
		let name: String = timerContext["name", default: "Unknown"]
		
		self.timeoutTimerCount += 1
		self.lastConnectionError = ""
		
		if timeoutTimerCount == 10 {
			if connectedPeripheral != nil {
				self.centralManager.cancelPeripheralConnection(connectedPeripheral.peripheral)
			}
			connectedPeripheral = nil
			if self.timeoutTimer != nil {
				
				self.timeoutTimer!.invalidate()
			}
			self.isConnected = false
			self.isConnecting = false
			self.lastConnectionError = "🚨 " + String.localizedStringWithFormat("ble.connection.timeout %d %@".localized, timeoutTimerCount, name)
			MeshLogger.log(lastConnectionError)
			self.timeoutTimerCount = 0
			self.startScanning()
		} else {
			Logger.services.info("🚨 [BLE] Connecting 2 Second Timeout Timer Fired \(self.timeoutTimerCount, privacy: .public) Time(s): \(name, privacy: .public)")
		}
	}
	
	func connectTo(peripheral: CBPeripheral) {
		DispatchQueue.main.async {
			self.isConnecting = true
			self.lastConnectionError = ""
			self.automaticallyReconnect = true
		}
		if connectedPeripheral != nil {
			Logger.services.info("ℹ️ [BLE] Disconnecting from: \(self.connectedPeripheral.name, privacy: .public) to connect to \(peripheral.name ?? "Unknown", privacy: .public)")
			disconnectPeripheral()
		}
		
		centralManager.connect(peripheral)
		// Invalidate any existing timer
		if timeoutTimer != nil {
			timeoutTimer!.invalidate()
		}
		// Use a timer to keep track of connecting peripherals, context to pass the radio name with the timer and the RunLoop to prevent
		// the timer from running on the main UI thread
		let context = ["name": "\(peripheral.name ?? "Unknown")"]
		timeoutTimer = Timer.scheduledTimer(timeInterval: 1.5, target: self, selector: #selector(timeoutTimerFired), userInfo: context, repeats: true)
		RunLoop.current.add(timeoutTimer!, forMode: .common)
		Logger.services.info("ℹ️ BLE Connecting: \(peripheral.name ?? "Unknown", privacy: .public)")
	}
	
	func cancelPeripheralConnection() {
		
		if mqttProxyConnected {
			mqttManager.mqttClientProxy?.disconnect()
		}
		characteristicFromRadio = nil
		isConnecting = false
		isConnected = false
		isSubscribed = false
		self.connectedPeripheral = nil
		invalidVersion = false
		connectedVersion = "0.0.0"
		connectedPeripheral = nil
		if timeoutTimer != nil {
			timeoutTimer!.invalidate()
		}
		automaticallyReconnect = false
		stopScanning()
		startScanning()
	}
	
	func disconnectPeripheral(reconnect: Bool = true) {
		
		guard let connectedPeripheral = connectedPeripheral else { return }
		if mqttProxyConnected {
			mqttManager.mqttClientProxy?.disconnect()
		}
		automaticallyReconnect = reconnect
		centralManager.cancelPeripheralConnection(connectedPeripheral.peripheral)
		characteristicFromRadio = nil
		isConnected = false
		isSubscribed = false
		invalidVersion = false
		connectedVersion = "0.0.0"
		stopScanning()
		startScanning()
	}
	
	func requestDeviceMetadata(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32, context: NSManagedObjectContext) -> Int64 {
		
		guard connectedPeripheral?.peripheral.state ?? .disconnected == .connected else { return 0 }
		
		var adminPacket = AdminMessage()
		adminPacket.getDeviceMetadataRequest = true
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		if let serializedData: Data = try? adminPacket.serializedData() {
			dataMessage.payload = serializedData
			dataMessage.portnum = PortNum.adminApp
			dataMessage.wantResponse = true
			meshPacket.decoded = dataMessage
		} else {
			return 0
		}
		
		let messageDescription = "🛎️ [Device Metadata] Requested for node \(toUser.longName ?? "unknown".localized) by \(fromUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			return Int64(meshPacket.id)
		}
		return 0
	}
	
	func sendTraceRouteRequest(destNum: Int64, wantResponse: Bool) -> Bool {
		
		var success = false
		guard connectedPeripheral?.peripheral.state ?? .disconnected == .connected else { return success }
		
		let fromNodeNum = connectedPeripheral.num
		let routePacket = RouteDiscovery()
		var meshPacket = MeshPacket()
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.to = UInt32(destNum)
		meshPacket.from	= UInt32(fromNodeNum)
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		if let serializedData: Data = try? routePacket.serializedData() {
			dataMessage.payload = serializedData
			dataMessage.portnum = PortNum.tracerouteApp
			dataMessage.wantResponse = true
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
		if connectedPeripheral?.peripheral.state ?? .disconnected == .connected {
			connectedPeripheral.peripheral.writeValue(binaryData, for: characteristicToRadio, type: .withResponse)
			success = true
			
			let traceRoute = TraceRouteEntity(context: context)
			let nodes = NodeInfoEntity.fetchRequest()
			nodes.predicate = NSPredicate(format: "num IN %@", [destNum, self.connectedPeripheral.num])
			do {
				let fetchedNodes = try context.fetch(nodes)
				let receivingNode = fetchedNodes.first(where: { $0.num == destNum })
				let connectedNode = fetchedNodes.first(where: { $0.num == self.connectedPeripheral.num })
				traceRoute.id = Int64(meshPacket.id)
				traceRoute.time = Date()
				traceRoute.node = receivingNode
				// Grab the most recent postion, within the last hour
				if connectedNode?.positions?.count ?? 0 > 0, let mostRecent = connectedNode?.positions?.lastObject as? PositionEntity {
					if mostRecent.time! >= Calendar.current.date(byAdding: .hour, value: -24, to: Date())! {
						traceRoute.altitude = mostRecent.altitude
						traceRoute.latitudeI = mostRecent.latitudeI
						traceRoute.longitudeI = mostRecent.longitudeI
						traceRoute.hasPositions = true
					}
				}
				do {
					try context.save()
					Logger.data.info("💾 Saved TraceRoute sent to node: \(String(receivingNode?.user?.longName ?? "unknown".localized), privacy: .public)")
				} catch {
					context.rollback()
					let nsError = error as NSError
					Logger.data.error("Error Updating Core Data BluetoothConfigEntity: \(nsError, privacy: .public)")
				}
				
				let logString = String.localizedStringWithFormat("mesh.log.traceroute.sent %@".localized, destNum.toHex())
				MeshLogger.log("🪧 \(logString)")
				
			} catch {
				
			}
		}
		return success
	}
	
	func sendWantConfig() {
		guard connectedPeripheral?.peripheral.state ?? .disconnected == .connected else { return }
		
		if characteristicFromRadio == nil {
			MeshLogger.log("🚨 \("firmware.version.unsupported".localized)")
			invalidVersion = true
			return
		} else {
			
			let nodeName = connectedPeripheral?.peripheral.name ?? "unknown".localized
			let logString = String.localizedStringWithFormat("mesh.log.wantconfig %@".localized, nodeName)
			MeshLogger.log("🛎️ \(logString)")
			// BLE Characteristics discovered, issue wantConfig
			var toRadio: ToRadio = ToRadio()
			configNonce += 1
			toRadio.wantConfigID = configNonce
			guard let binaryData: Data = try? toRadio.serializedData() else {
				return
			}
			connectedPeripheral!.peripheral.writeValue(binaryData, for: characteristicToRadio, type: .withResponse)
			// Either Read the config complete value or from num notify value
			guard connectedPeripheral != nil else { return }
			connectedPeripheral!.peripheral.readValue(for: characteristicFromRadio)
		}
	}
	
	func handleRadioLog(radioLog: String) {
		var log = radioLog
		/// Debug Log Level
		if log.starts(with: "DEBUG |") {
			do {
				let logString = log
				if let coordsMatch = try CommonRegex.coordinateRegex.firstMatch(in: logString) {
					log = "\(log.replacingOccurrences(of: "DEBUG |", with: "").trimmingCharacters(in: .whitespaces))"
					log = log.replacingOccurrences(of: "[,]", with: "", options: .regularExpression)
					Logger.radio.debug("🛰️ \(log.prefix(upTo: coordsMatch.range.lowerBound), privacy: .public) \(coordsMatch.0.replacingOccurrences(of: "[,]", with: "", options: .regularExpression), privacy: .private) \(log.suffix(from: coordsMatch.range.upperBound), privacy: .public)")
				} else {
					log = log.replacingOccurrences(of: "[,]", with: "", options: .regularExpression)
					Logger.radio.debug("🕵🏻‍♂️ \(log.replacingOccurrences(of: "DEBUG |", with: "").trimmingCharacters(in: .whitespaces), privacy: .public)")
				}
			} catch {
				log = log.replacingOccurrences(of: "[,]", with: "", options: .regularExpression)
				Logger.radio.debug("🕵🏻‍♂️ \(log.replacingOccurrences(of: "DEBUG |", with: "").trimmingCharacters(in: .whitespaces), privacy: .public)")
			}
		} else if log.starts(with: "INFO  |") {
			do {
				let logString = log
				if let coordsMatch = try CommonRegex.coordinateRegex.firstMatch(in: logString) {
					log = "\(log.replacingOccurrences(of: "INFO  |", with: "").trimmingCharacters(in: .whitespaces))"
					log = log.replacingOccurrences(of: "[,]", with: "", options: .regularExpression)
					Logger.radio.info("🛰️ \(log.prefix(upTo: coordsMatch.range.lowerBound), privacy: .public) \(coordsMatch.0.replacingOccurrences(of: "[,]", with: "", options: .regularExpression), privacy: .private) \(log.suffix(from: coordsMatch.range.upperBound), privacy: .public)")
				} else {
					log = log.replacingOccurrences(of: "[,]", with: "", options: .regularExpression)
					Logger.radio.info("📢 \(log.replacingOccurrences(of: "INFO  |", with: "").trimmingCharacters(in: .whitespaces), privacy: .public)")
				}
			} catch {
				log = log.replacingOccurrences(of: "[,]", with: "", options: .regularExpression)
				Logger.radio.info("📢 \(log.replacingOccurrences(of: "INFO  |", with: "").trimmingCharacters(in: .whitespaces), privacy: .public)")
			}
		} else if log.starts(with: "WARN  |") {
			log = log.replacingOccurrences(of: "[,]", with: "", options: .regularExpression)
			Logger.radio.warning("⚠️ \(log.replacingOccurrences(of: "WARN  |", with: "").trimmingCharacters(in: .whitespaces), privacy: .public)")
		} else if log.starts(with: "ERROR |") {
			log = log.replacingOccurrences(of: "[,]", with: "", options: .regularExpression)
			Logger.radio.error("💥 \(log.replacingOccurrences(of: "ERROR |", with: "").trimmingCharacters(in: .whitespaces), privacy: .public)")
		} else if log.starts(with: "CRIT  |") {
			log = log.replacingOccurrences(of: "[,]", with: "", options: .regularExpression)
			Logger.radio.critical("🧨 \(log.replacingOccurrences(of: "CRIT  |", with: "").trimmingCharacters(in: .whitespaces), privacy: .public)")
		} else {
			log = log.replacingOccurrences(of: "[,]", with: "", options: .regularExpression)
			Logger.radio.debug("📟 \(log, privacy: .public)")
		}
	}
	
	func sendMessage(message: String, toUserNum: Int64, channel: Int32, isEmoji: Bool, replyID: Int64) -> Bool {
		var success = false
		
		// Return false if we are not properly connected to a device, handle retry logic in the view for now
		if connectedPeripheral == nil || connectedPeripheral!.peripheral.state != .connected {
			
			self.disconnectPeripheral()
			self.startScanning()
			
			// Try and connect to the preferredPeripherial first
			let preferredPeripheral = peripherals.filter({ $0.peripheral.identifier.uuidString == UserDefaults.preferredPeripheralId as String }).first
			if preferredPeripheral != nil && preferredPeripheral?.peripheral != nil {
				connectTo(peripheral: preferredPeripheral!.peripheral)
			}
			let nodeName = connectedPeripheral?.peripheral.name ?? "unknown".localized
			let logString = String.localizedStringWithFormat("mesh.log.textmessage.send.failed %@".localized, nodeName)
			MeshLogger.log("🚫 \(logString)")
			
			success = false
		} else if message.count < 1 {
			
			// Don't send an empty message
			Logger.mesh.info("🚫 Don't Send an Empty Message")
			success = false
			
		} else {
			let fromUserNum: Int64 = self.connectedPeripheral.num
			
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
					if connectedPeripheral?.peripheral.state ?? .disconnected == .connected {
						connectedPeripheral.peripheral.writeValue(binaryData, for: characteristicToRadio, type: .withResponse)
						let logString = String.localizedStringWithFormat("mesh.log.textmessage.sent %@ %@ %@".localized, String(newMessage.messageId), fromUserNum.toHex(), toUserNum.toHex())
						
						MeshLogger.log("💬 \(logString)")
						do {
							try context.save()
							Logger.data.info("💾 Saved a new sent message from \(self.connectedPeripheral.num.toHex(), privacy: .public) to \(toUserNum.toHex(), privacy: .public)")
							success = true
							
						} catch {
							context.rollback()
							let nsError = error as NSError
							Logger.data.error("Unresolved Core Data error in Send Message Function your database is corrupted running a node db reset should clean up the data. Error: \(nsError, privacy: .public)")
						}
					}
				}
			} catch {
				Logger.data.error("💥 Send message failure \(self.connectedPeripheral.num.toHex(), privacy: .public) to \(toUserNum.toHex(), privacy: .public)")
			}
		}
		return success
	}
	
	func sendWaypoint(waypoint: Waypoint) -> Bool {
		if waypoint.latitudeI == 373346000 && waypoint.longitudeI == -1220090000 {
			return false
		}
		var success = false
		let fromNodeNum = UInt32(connectedPeripheral.num)
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
		if connectedPeripheral?.peripheral.state ?? .disconnected == .connected {
			connectedPeripheral.peripheral.writeValue(binaryData, for: characteristicToRadio, type: .withResponse)
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
	
	@MainActor
	func getPositionFromPhoneGPS(destNum: Int64) -> Position? {
		var positionPacket = Position()
		guard let lastLocation = LocationsHandler.shared.locationsArray.last else {
			return nil
		}
		positionPacket.latitudeI = Int32(lastLocation.coordinate.latitude * 1e7)
		positionPacket.longitudeI = Int32(lastLocation.coordinate.longitude * 1e7)
		let timestamp = lastLocation.timestamp
		positionPacket.time = UInt32(timestamp.timeIntervalSince1970)
		positionPacket.timestamp = UInt32(timestamp.timeIntervalSince1970)
		positionPacket.altitude = Int32(lastLocation.altitude)
		positionPacket.satsInView = UInt32(0)
		
		let currentSpeed = lastLocation.speed
		if currentSpeed > 0 && (!currentSpeed.isNaN || !currentSpeed.isInfinite) {
			positionPacket.groundSpeed = UInt32(currentSpeed)
		}
		let currentHeading = lastLocation.course
		if (currentHeading > 0  && currentHeading <= 360) && (!currentHeading.isNaN || !currentHeading.isInfinite) {
			positionPacket.groundTrack = UInt32(currentHeading)
		}
		
		return positionPacket
	}
	
	@MainActor
	func setFixedPosition(fromUser: UserEntity, channel: Int32) -> Bool {
		var adminPacket = AdminMessage()
		guard let positionPacket = getPositionFromPhoneGPS(destNum: fromUser.num) else {
			return false
		}
		adminPacket.setFixedPosition = positionPacket
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(fromUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		meshPacket.channel = UInt32(channel)
		var dataMessage = DataMessage()
		meshPacket.decoded = dataMessage
		if let serializedData: Data = try? adminPacket.serializedData() {
			dataMessage.payload = serializedData
			dataMessage.portnum = PortNum.adminApp
			meshPacket.decoded = dataMessage
		} else {
			return false
		}
		let messageDescription = "🚀 Sent Set Fixed Postion Admin Message to: \(fromUser.longName ?? "unknown".localized) from: \(fromUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			return true
		}
		return false
	}
	
	func removeFixedPosition(fromUser: UserEntity, channel: Int32) -> Bool {
		var adminPacket = AdminMessage()
		adminPacket.removeFixedPosition = true
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(fromUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		meshPacket.channel = UInt32(channel)
		var dataMessage = DataMessage()
		if let serializedData: Data = try? adminPacket.serializedData() {
			dataMessage.payload = serializedData
			dataMessage.portnum = PortNum.adminApp
			meshPacket.decoded = dataMessage
		} else {
			return false
		}
		let messageDescription = "🚀 Sent Remove Fixed Position Admin Message to: \(fromUser.longName ?? "unknown".localized) from: \(fromUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			return true
		}
		return false
	}
	
	@MainActor
	func sendPosition(channel: Int32, destNum: Int64, wantResponse: Bool) -> Bool {
		let fromNodeNum = connectedPeripheral.num
		guard let positionPacket = getPositionFromPhoneGPS(destNum: destNum) else {
			Logger.services.error("Unable to get position data from device GPS to send to node")
			return false
		}
		
		var meshPacket = MeshPacket()
		meshPacket.to = UInt32(destNum)
		meshPacket.channel = UInt32(channel)
		meshPacket.from	= UInt32(fromNodeNum)
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
		if connectedPeripheral?.peripheral.state ?? .disconnected == .connected {
			connectedPeripheral.peripheral.writeValue(binaryData, for: characteristicToRadio, type: .withResponse)
			let logString = String.localizedStringWithFormat("mesh.log.sharelocation %@".localized, String(fromNodeNum))
			Logger.services.debug("📍 \(logString)")
			return true
		} else {
			Logger.services.error("Device no longer connected. Unable to send position information.")
			return false
		}
	}
	
	@MainActor
	@objc
	func positionTimerFired(timer: Timer) {
		// Check for connected node
		if connectedPeripheral != nil {
			// Send a position out to the mesh if "share location with the mesh" is enabled in settings
			if UserDefaults.provideLocation {
				_ = sendPosition(channel: 0, destNum: connectedPeripheral.num, wantResponse: false)
			}
		}
	}
	
	func sendShutdown(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		var adminPacket = AdminMessage()
		adminPacket.shutdownSeconds = 5
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		meshPacket.channel = UInt32(adminIndex)
		var dataMessage = DataMessage()
		if let serializedData: Data = try? adminPacket.serializedData() {
			dataMessage.payload = serializedData
			dataMessage.portnum = PortNum.adminApp
			meshPacket.decoded = dataMessage
		} else {
			return false
		}
		let messageDescription = "🚀 Sent Shutdown Admin Message to: \(toUser.longName ?? "unknown".localized) from: \(fromUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			return true
		}
		return false
	}
	
	func sendReboot(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		var adminPacket = AdminMessage()
		adminPacket.rebootSeconds = 5
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		meshPacket.channel = UInt32(adminIndex)
		var dataMessage = DataMessage()
		if let serializedData: Data = try? adminPacket.serializedData() {
			dataMessage.payload = serializedData
			dataMessage.portnum = PortNum.adminApp
			meshPacket.decoded = dataMessage
		} else {
			return false
		}
		let messageDescription = "🚀 Sent Reboot Admin Message to: \(toUser.longName ?? "unknown".localized) from: \(fromUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			return true
		}
		return false
	}
	
	func sendRebootOta(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		var adminPacket = AdminMessage()
		adminPacket.rebootOtaSeconds = 5
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		meshPacket.channel = UInt32(adminIndex)
		var dataMessage = DataMessage()
		if let serializedData: Data = try? adminPacket.serializedData() {
			dataMessage.payload = serializedData
			dataMessage.portnum = PortNum.adminApp
			meshPacket.decoded = dataMessage
		} else {
			return false
		}
		let messageDescription = "🚀 Sent Reboot OTA Admin Message to: \(toUser.longName ?? "unknown".localized) from: \(fromUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			return true
		}
		return false
	}
	
	func sendEnterDfuMode(fromUser: UserEntity, toUser: UserEntity) -> Bool {
		var adminPacket = AdminMessage()
		adminPacket.enterDfuModeRequest = true
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		meshPacket.channel = UInt32(0)
		var dataMessage = DataMessage()
		if let serializedData: Data = try? adminPacket.serializedData() {
			dataMessage.payload = serializedData
			dataMessage.portnum = PortNum.adminApp
			meshPacket.decoded = dataMessage
		} else {
			return false
		}
		automaticallyReconnect = false
		let messageDescription = "🚀 Sent enter DFU mode Admin Message to: \(toUser.longName ?? "unknown".localized) from: \(fromUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			return true
		}
		return false
	}
	
	func sendFactoryReset(fromUser: UserEntity, toUser: UserEntity) -> Bool {
		var adminPacket = AdminMessage()
		adminPacket.factoryResetDevice = 5
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	=  UInt32(fromUser.num)
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
		
		let messageDescription = "🚀 Sent Factory Reset Admin Message to: \(toUser.longName ?? "unknown".localized) from: \(fromUser.longName ??  "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			return true
		}
		return false
	}
	
	func sendNodeDBReset(fromUser: UserEntity, toUser: UserEntity) -> Bool {
		var adminPacket = AdminMessage()
		adminPacket.nodedbReset = 5
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= 0 // UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return false
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		
		meshPacket.decoded = dataMessage
		let messageDescription = "🚀 Sent NodeDB Reset Admin Message to: \(toUser.longName ?? "unknown".localized) from: \(fromUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			return true
		}
		return false
	}
	
	func connectToPreferredPeripheral() -> Bool {
		var success = false
		// Return false if we are not properly connected to a device, handle retry logic in the view for now
		if connectedPeripheral == nil || connectedPeripheral!.peripheral.state != .connected {
			self.disconnectPeripheral()
			self.startScanning()
			// Try and connect to the preferredPeripherial first
			let preferredPeripheral = peripherals.filter({ $0.peripheral.identifier.uuidString == UserDefaults.standard.object(forKey: "preferredPeripheralId") as? String ?? "" }).first
			if preferredPeripheral != nil && preferredPeripheral?.peripheral != nil {
				connectTo(peripheral: preferredPeripheral!.peripheral)
				success = true
			}
		} else if connectedPeripheral != nil && isSubscribed {
			success = true
		}
		return success
	}
	
	func getChannel(channel: Channel, fromUser: UserEntity, toUser: UserEntity) -> Int64 {
		
		var adminPacket = AdminMessage()
		adminPacket.getChannelRequest = UInt32(channel.index + 1)
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return 0
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🎛️ Requested Channel \(channel.index) for \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			return Int64(meshPacket.id)
		}
		return 0
	}
	func saveChannel(channel: Channel, fromUser: UserEntity, toUser: UserEntity) -> Int64 {
		
		var adminPacket = AdminMessage()
		adminPacket.setChannel = channel
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return 0
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛟 Saved Channel \(channel.index) for \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			return Int64(meshPacket.id)
		}
		return 0
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
							fetchMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", Int64(connectedPeripheral.num))
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
						meshPacket.to = UInt32(connectedPeripheral.num)
						meshPacket.from	= UInt32(connectedPeripheral.num)
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
						if connectedPeripheral?.peripheral.state ?? .disconnected == .connected {
							self.connectedPeripheral.peripheral.writeValue(binaryData, for: self.characteristicToRadio, type: .withResponse)
							let logString = String.localizedStringWithFormat("mesh.log.channel.sent %@ %d".localized, String(connectedPeripheral.num), chan.index)
							MeshLogger.log("🎛️ \(logString)")
						}
					}
					// Save the LoRa Config and the device will reboot
					var adminPacket = AdminMessage()
					adminPacket.setConfig.lora = channelSet.loraConfig
					var meshPacket: MeshPacket = MeshPacket()
					meshPacket.to = UInt32(connectedPeripheral.num)
					meshPacket.from	= UInt32(connectedPeripheral.num)
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
					if connectedPeripheral?.peripheral.state ?? .disconnected == .connected {
						self.connectedPeripheral.peripheral.writeValue(binaryData, for: self.characteristicToRadio, type: .withResponse)
						let logString = String.localizedStringWithFormat("mesh.log.lora.config.sent %@".localized, String(connectedPeripheral.num))
						MeshLogger.log("📻 \(logString)")
					}
					
					if self.connectedPeripheral != nil {
						self.sendWantConfig()
						return true
					}
					
				} catch {
					return false
				}
			}
		}
		return false
	}
	
	func saveUser(config: User, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		var adminPacket = AdminMessage()
		adminPacket.setOwner = config
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		if let serializedData: Data = try? adminPacket.serializedData() {
			dataMessage.payload = serializedData
			dataMessage.portnum = PortNum.adminApp
			meshPacket.decoded = dataMessage
		} else {
			return 0
		}
		let messageDescription = "🛟 Saved User Config for \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			return Int64(meshPacket.id)
		}
		return 0
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
		
		if connectedPeripheral?.peripheral.state ?? .disconnected == .connected {
			do {
				connectedPeripheral.peripheral.writeValue(binaryData, for: characteristicToRadio, type: .withResponse)
				context.delete(node.user!)
				context.delete(node)
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
	
	func setFavoriteNode(node: NodeInfoEntity, connectedNodeNum: Int64) -> Bool {
		var adminPacket = AdminMessage()
		adminPacket.setFavoriteNode = UInt32(node.num)
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(connectedNodeNum)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
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
		
		if connectedPeripheral?.peripheral.state ?? .disconnected == .connected {
			connectedPeripheral.peripheral.writeValue(binaryData, for: characteristicToRadio, type: .withResponse)
			return true
		}
		return false
	}
	
	func removeFavoriteNode(node: NodeInfoEntity, connectedNodeNum: Int64) -> Bool {
		var adminPacket = AdminMessage()
		adminPacket.removeFavoriteNode = UInt32(node.num)
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(connectedNodeNum)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
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
		
		if connectedPeripheral?.peripheral.state ?? .disconnected == .connected {
			connectedPeripheral.peripheral.writeValue(binaryData, for: characteristicToRadio, type: .withResponse)
			return true
		}
		return false
	}
	
	func saveLicensedUser(ham: HamParameters, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		var adminPacket = AdminMessage()
		adminPacket.setHamMode = ham
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return 0
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		let messageDescription = "🛟 Saved Ham Parameters for \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			return Int64(meshPacket.id)
		}
		return 0
	}
	func saveBluetoothConfig(config: Config.BluetoothConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		var adminPacket = AdminMessage()
		adminPacket.setConfig.bluetooth = config
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return 0
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		let messageDescription = "🛟 Saved Bluetooth Config for \(toUser.longName ?? "unknown".localized)"
		
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			upsertBluetoothConfigPacket(config: config, nodeNum: toUser.num, context: context)
			return Int64(meshPacket.id)
		}
		
		return 0
	}
	
	func saveDeviceConfig(config: Config.DeviceConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
		var adminPacket = AdminMessage()
		adminPacket.setConfig.device = config
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return 0
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		let messageDescription = "🛟 Saved Device Config for \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			upsertDeviceConfigPacket(config: config, nodeNum: toUser.num, context: context)
			return Int64(meshPacket.id)
		}
		return 0
	}
	
	func saveDisplayConfig(config: Config.DisplayConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		var adminPacket = AdminMessage()
		adminPacket.setConfig.display = config
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		if adminIndex > 0 {
			meshPacket.channel = UInt32(adminIndex)
		}
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return 0
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		let messageDescription = "🛟 Saved Display Config for \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			upsertDisplayConfigPacket(config: config, nodeNum: toUser.num, context: context)
			return Int64(meshPacket.id)
		}
		return 0
	}
	
	func saveLoRaConfig(config: Config.LoRaConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
		var adminPacket = AdminMessage()
		adminPacket.setConfig.lora = config
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return 0
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		let messageDescription = "🛟 Saved LoRa Config for \(toUser.longName ?? "unknown".localized)"
		
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			upsertLoRaConfigPacket(config: config, nodeNum: toUser.num, context: context)
			return Int64(meshPacket.id)
		}
		
		return 0
	}
	
	func savePositionConfig(config: Config.PositionConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
		var adminPacket = AdminMessage()
		adminPacket.setConfig.position = config
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return 0
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛟 Saved Position Config for \(toUser.longName ?? "unknown".localized)"
		
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			upsertPositionConfigPacket(config: config, nodeNum: toUser.num, context: context)
			return Int64(meshPacket.id)
		}
		
		return 0
	}
	
	func savePowerConfig(config: Config.PowerConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
		var adminPacket = AdminMessage()
		adminPacket.setConfig.power = config
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return 0
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛟 Saved Power Config for \(toUser.longName ?? "unknown".localized)"
		
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			upsertPowerConfigPacket(config: config, nodeNum: toUser.num, context: context)
			return Int64(meshPacket.id)
		}
		
		return 0
	}
	
	func saveNetworkConfig(config: Config.NetworkConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
		var adminPacket = AdminMessage()
		adminPacket.setConfig.network = config
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return 0
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛟 Saved Network Config for \(toUser.longName ?? "unknown".localized)"
		
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			upsertNetworkConfigPacket(config: config, nodeNum: toUser.num, context: context)
			return Int64(meshPacket.id)
		}
		
		return 0
	}
	
	func saveAmbientLightingModuleConfig(config: ModuleConfig.AmbientLightingConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.ambientLighting = config
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return 0
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛟 Saved Ambient Lighting Module Config for \(toUser.longName ?? "unknown".localized)"
		
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			upsertAmbientLightingModuleConfigPacket(config: config, nodeNum: toUser.num, context: context)
			return Int64(meshPacket.id)
		}
		
		return 0
	}
	
	func saveCannedMessageModuleConfig(config: ModuleConfig.CannedMessageConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.cannedMessage = config
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return 0
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛟 Saved Canned Message Module Config for \(toUser.longName ?? "unknown".localized)"
		
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			upsertCannedMessagesModuleConfigPacket(config: config, nodeNum: toUser.num, context: context)
			return Int64(meshPacket.id)
		}
		
		return 0
	}
	
	func saveCannedMessageModuleMessages(messages: String, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
		var adminPacket = AdminMessage()
		adminPacket.setCannedMessageModuleMessages = messages
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return 0
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛟 Saved Canned Message Module Messages for \(toUser.longName ?? "unknown".localized)"
		
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			
			return Int64(meshPacket.id)
		}
		
		return 0
	}
	
	func saveDetectionSensorModuleConfig(config: ModuleConfig.DetectionSensorConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.detectionSensor = config
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return 0
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛟 Saved Detection Sensor Module Config for \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			upsertDetectionSensorModuleConfigPacket(config: config, nodeNum: toUser.num, context: context)
			return Int64(meshPacket.id)
		}
		return 0
	}
	
	func saveExternalNotificationModuleConfig(config: ModuleConfig.ExternalNotificationConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.externalNotification = config
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return 0
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛟 Saved External Notification Module Config for \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			upsertExternalNotificationModuleConfigPacket(config: config, nodeNum: toUser.num, context: context)
			return Int64(meshPacket.id)
		}
		return 0
	}
	
	func savePaxcounterModuleConfig(config: ModuleConfig.PaxcounterConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.paxcounter = config
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return 0
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛟 Saved PAX Counter Module Config for \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			upsertPaxCounterModuleConfigPacket(config: config, nodeNum: toUser.num, context: context)
			return Int64(meshPacket.id)
		}
		
		return 0
	}
	
	func saveRtttlConfig(ringtone: String, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
		var adminPacket = AdminMessage()
		adminPacket.setRingtoneMessage = ringtone
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return 0
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛟 Saved RTTTL Ringtone Config for \(toUser.longName ?? "unknown".localized)"
		
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			upsertRtttlConfigPacket(ringtone: ringtone, nodeNum: toUser.num, context: context)
			return Int64(meshPacket.id)
		}
		
		return 0
	}
	
	func saveMQTTConfig(config: ModuleConfig.MQTTConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.mqtt = config
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return 0
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛟 Saved MQTT Config for \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			upsertMqttModuleConfigPacket(config: config, nodeNum: toUser.num, context: context)
			return Int64(meshPacket.id)
		}
		return 0
	}
	
	func saveRangeTestModuleConfig(config: ModuleConfig.RangeTestConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.rangeTest = config
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return 0
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛟 Saved Range Test Module Config for \(toUser.longName ?? "unknown".localized)"
		
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			upsertRangeTestModuleConfigPacket(config: config, nodeNum: toUser.num, context: context)
			return Int64(meshPacket.id)
		}
		
		return 0
	}
	
	func saveSerialModuleConfig(config: ModuleConfig.SerialConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.serial = config
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return 0
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛟 Saved Serial Module Config for \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			upsertSerialModuleConfigPacket(config: config, nodeNum: toUser.num, context: context)
			return Int64(meshPacket.id)
		}
		return 0
	}
	
	func saveStoreForwardModuleConfig(config: ModuleConfig.StoreForwardConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.storeForward = config
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return 0
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛟 Saved Store & Forward Module Config for \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			upsertStoreForwardModuleConfigPacket(config: config, nodeNum: toUser.num, context: context)
			return Int64(meshPacket.id)
		}
		return 0
	}
	
	func saveTelemetryModuleConfig(config: ModuleConfig.TelemetryConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.telemetry = config
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return 0
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		
		let messageDescription = "Saved Telemetry Module Config for \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			upsertTelemetryModuleConfigPacket(config: config, nodeNum: toUser.num, context: context)
			return Int64(meshPacket.id)
		}
		return 0
	}
	
	func getChannel(channelIndex: UInt32, fromUser: UserEntity, toUser: UserEntity, wantResponse: Bool) -> Bool {
		
		var adminPacket = AdminMessage()
		adminPacket.getChannelRequest = channelIndex
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = wantResponse
		
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return false
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Sent a Get Channel \(channelIndex) Request Admin Message for node: \(toUser.longName ?? "unknown".localized))"
		
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			
			return true
		}
		
		return false
	}
	
	func getCannedMessageModuleMessages(destNum: Int64, wantResponse: Bool) -> Bool {
		
		var adminPacket = AdminMessage()
		adminPacket.getCannedMessageModuleMessagesRequest = true
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(destNum)
		meshPacket.from	= UInt32(connectedPeripheral.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		meshPacket.decoded.wantResponse = wantResponse
		
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return false
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = wantResponse
		
		meshPacket.decoded = dataMessage
		
		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket
		
		guard let binaryData: Data = try? toRadio.serializedData() else {
			return false
		}
		
		if connectedPeripheral?.peripheral.state ?? .disconnected == .connected {
			connectedPeripheral.peripheral.writeValue(binaryData, for: characteristicToRadio, type: .withResponse)
			let logString = String.localizedStringWithFormat("mesh.log.cannedmessages.messages.get %@".localized, String(connectedPeripheral.num))
			MeshLogger.log("🥫 \(logString)")
			return true
		}
		
		return false
	}
	
	func requestBluetoothConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
		var adminPacket = AdminMessage()
		adminPacket.getConfigRequest = AdminMessage.ConfigType.bluetoothConfig
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.wantAck = true
		
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return false
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested Bluetooth Config on admin channel \(adminIndex) for node: \(String(connectedPeripheral.num))"
		
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			return true
		}
		return false
	}
	
	func requestDeviceConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
		var adminPacket = AdminMessage()
		adminPacket.getConfigRequest = AdminMessage.ConfigType.deviceConfig
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.wantAck = true
		
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return false
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested Device Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			return true
		}
		return false
	}
	
	func requestDisplayConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
		var adminPacket = AdminMessage()
		adminPacket.getConfigRequest = AdminMessage.ConfigType.displayConfig
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.wantAck = true
		
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return false
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested Display Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			return true
		}
		return false
	}
	
	func requestLoRaConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
		var adminPacket = AdminMessage()
		adminPacket.getConfigRequest = AdminMessage.ConfigType.loraConfig
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.wantAck = true
		
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return false
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested LoRa Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			
			return true
		}
		
		return false
	}
	
	func requestNetworkConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
		var adminPacket = AdminMessage()
		adminPacket.getConfigRequest = AdminMessage.ConfigType.networkConfig
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.wantAck = true
		
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return false
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested Network Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			return true
		}
		return false
	}
	
	func requestPositionConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
		var adminPacket = AdminMessage()
		adminPacket.getConfigRequest = AdminMessage.ConfigType.positionConfig
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.wantAck = true
		
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return false
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested Position Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			return true
		}
		return false
	}
	
	func requestPowerConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
		var adminPacket = AdminMessage()
		adminPacket.getConfigRequest = AdminMessage.ConfigType.powerConfig
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.wantAck = true
		
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return false
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested Power Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			return true
		}
		return false
	}
	
	func requestAmbientLightingConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
		var adminPacket = AdminMessage()
		adminPacket.getModuleConfigRequest = AdminMessage.ModuleConfigType.ambientlightingConfig
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.wantAck = true
		
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return false
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested Ambient Lighting Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			return true
		}
		return false
	}
	
	func requestCannedMessagesModuleConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
		var adminPacket = AdminMessage()
		adminPacket.getModuleConfigRequest = AdminMessage.ModuleConfigType.cannedmsgConfig
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.wantAck = true
		
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return false
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested Canned Messages Module Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			return true
		}
		return false
	}
	
	func requestExternalNotificationModuleConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
		var adminPacket = AdminMessage()
		adminPacket.getModuleConfigRequest = AdminMessage.ModuleConfigType.extnotifConfig
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.wantAck = true
		
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return false
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested External Notificaiton Module Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			return true
		}
		return false
	}
	
	func requestPaxCounterModuleConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
		var adminPacket = AdminMessage()
		adminPacket.getModuleConfigRequest = AdminMessage.ModuleConfigType.paxcounterConfig
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.wantAck = true
		
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return false
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested PAX Counter Module Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			return true
		}
		return false
	}
	
	func requestRtttlConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
		var adminPacket = AdminMessage()
		adminPacket.getRingtoneRequest = true
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.wantAck = true
		
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return false
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested RTTTL Ringtone Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			return true
		}
		return false
	}
	
	func requestRangeTestModuleConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
		var adminPacket = AdminMessage()
		adminPacket.getModuleConfigRequest = AdminMessage.ModuleConfigType.rangetestConfig
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.wantAck = true
		
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return false
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested Range Test Module Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			return true
		}
		return false
	}
	
	func requestMqttModuleConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
		var adminPacket = AdminMessage()
		adminPacket.getModuleConfigRequest = AdminMessage.ModuleConfigType.mqttConfig
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.wantAck = true
		
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return false
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested MQTT Module Config on admin channel \(adminIndex) for node: \(String(connectedPeripheral.num))"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			return true
		}
		return false
	}
	
	func requestDetectionSensorModuleConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
		var adminPacket = AdminMessage()
		adminPacket.getModuleConfigRequest = AdminMessage.ModuleConfigType.detectionsensorConfig
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.wantAck = true
		
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return false
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested Detection Sensor Module Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			return true
		}
		return false
	}
	
	func requestSerialModuleConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
		var adminPacket = AdminMessage()
		adminPacket.getModuleConfigRequest = AdminMessage.ModuleConfigType.serialConfig
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.wantAck = true
		
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return false
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested Serial Module Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			return true
		}
		return false
	}
	
	func requestStoreAndForwardModuleConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
		var adminPacket = AdminMessage()
		adminPacket.getModuleConfigRequest = AdminMessage.ModuleConfigType.storeforwardConfig
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.wantAck = true
		
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return false
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested Store and Forward Module Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			return true
		}
		return false
	}
	
	func requestTelemetryModuleConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
		var adminPacket = AdminMessage()
		adminPacket.getModuleConfigRequest = AdminMessage.ModuleConfigType.telemetryConfig
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.channel = UInt32(adminIndex)
		meshPacket.wantAck = true
		
		var dataMessage = DataMessage()
		guard let adminData: Data = try? adminPacket.serializedData() else {
			return false
		}
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested Telemetry Module Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			return true
		}
		return false
	}
	
	// Send an admin message to a radio, save a message to core data for logging
	private func sendAdminMessageToRadio(meshPacket: MeshPacket, adminDescription: String) -> Bool {
		
		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket
		guard let binaryData: Data = try? toRadio.serializedData() else {
			return false
		}
		
		if connectedPeripheral?.peripheral.state ?? .disconnected == .connected {
			connectedPeripheral.peripheral.writeValue(binaryData, for: characteristicToRadio, type: .withResponse)
			Logger.mesh.debug("\(adminDescription)")
			return true
		}
		return false
	}
	
	func requestStoreAndForwardClientHistory(fromUser: UserEntity, toUser: UserEntity) -> Bool {
		
		/// send a request for ClientHistory with a time period matching the heartbeat
		var sfPacket = StoreAndForward()
		sfPacket.rr = StoreAndForward.RequestResponse.clientHistory
		sfPacket.history.window = UInt32(toUser.userNode?.storeForwardConfig?.historyReturnWindow ?? 120)
		sfPacket.history.lastRequest = UInt32(toUser.userNode?.storeForwardConfig?.lastRequest ?? 0)
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		guard let sfData: Data = try? sfPacket.serializedData() else {
			return false
		}
		dataMessage.payload = sfData
		dataMessage.portnum = PortNum.storeForwardApp
		dataMessage.wantResponse = true
		meshPacket.decoded = dataMessage
		
		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket
		guard let binaryData: Data = try? toRadio.serializedData() else {
			return false
		}
		if connectedPeripheral?.peripheral.state ?? .disconnected == .connected {
			connectedPeripheral.peripheral.writeValue(binaryData, for: characteristicToRadio, type: .withResponse)
			Logger.mesh.debug("📮 Sent a request for a Store & Forward Client History to \(toUser.num.toHex(), privacy: .public) for the last \(120, privacy: .public) minutes.")
			return true
		}
		return false
	}
	
	func storeAndForwardPacket(packet: MeshPacket, connectedNodeNum: Int64, context: NSManagedObjectContext) {
		if let storeAndForwardMessage = try? StoreAndForward(serializedData: packet.decoded.payload) {
			// Handle each of the store and forward request / response messages
			switch storeAndForwardMessage.rr {
			case .unset:
				MeshLogger.log("📮 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")
			case .routerError:
				MeshLogger.log("☠️ Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")
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
				MeshLogger.log("💓 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")
			case .routerPing:
				MeshLogger.log("🏓 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")
			case .routerPong:
				MeshLogger.log("🏓 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")
			case .routerBusy:
				MeshLogger.log("🐝 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")
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
				MeshLogger.log("📜 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")
			case .routerStats:
				MeshLogger.log("📊 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")
			case .clientError:
				MeshLogger.log("☠️ Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")
			case .clientHistory:
				MeshLogger.log("📜 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")
			case .clientStats:
				MeshLogger.log("📊 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")
			case .clientPing:
				MeshLogger.log("🏓 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")
			case .clientPong:
				MeshLogger.log("🏓 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")
			case .clientAbort:
				MeshLogger.log("🛑 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")
			case .UNRECOGNIZED:
				MeshLogger.log("📮 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")
			case .routerTextDirect:
				MeshLogger.log("💬 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")
				textMessageAppPacket(
					packet: packet,
					wantRangeTestPackets: false,
					connectedNode: connectedNodeNum,
					storeForward: true,
					context: context,
					appState: appState
				)
			case .routerTextBroadcast:
				MeshLogger.log("✉️ Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from.toHex())")
				textMessageAppPacket(
					packet: packet,
					wantRangeTestPackets: false,
					connectedNode: connectedNodeNum,
					storeForward: true,
					context: context,
					appState: appState
				)
			}
		}
	}
	
	func tryClearExistingChannels() {
		// Before we get started delete the existing channels from the myNodeInfo
		let fetchMyInfoRequest = MyInfoEntity.fetchRequest()
		fetchMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", Int64(connectedPeripheral.num))
		
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
}
// swiftlint:enable all
