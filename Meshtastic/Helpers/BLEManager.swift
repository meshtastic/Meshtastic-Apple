import Foundation
import CoreData
import CoreBluetooth
import SwiftUI
import MapKit
import CocoaMQTT

// ---------------------------------------------------------------------------------------
// Meshtastic BLE Device Manager
// ---------------------------------------------------------------------------------------
class BLEManager: NSObject, CBPeripheralDelegate, MqttClientProxyManagerDelegate, ObservableObject {
	
	private static var documentsFolder: URL {
		do {
			return try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
		} catch {
			fatalError("Can't find documents directory.")
		}
	}
	var context: NSManagedObjectContext?
	//var userSettings: UserSettings?
	private var centralManager: CBCentralManager!
	@Published var peripherals: [Peripheral] = []
	@Published var connectedPeripheral: Peripheral!
	@Published var lastConnectionError: String
	@Published var invalidVersion = false
	@Published var isSwitchedOn: Bool = false
	@Published var automaticallyReconnect: Bool = true
	@Published var mqttProxyConnected: Bool = false
	@Published var mqttError: String = ""
	@StateObject var appState = AppState.shared
	var peripheralConnectingTo: CBPeripheral!
	public var minimumVersion = "2.0.0"
	public var connectedVersion: String
	public var isConnecting: Bool = false
	public var isConnected: Bool = false
	public var isSubscribed: Bool = false
	private var configNonce: UInt32 = 1
	var timeoutTimer: Timer?
	var timeoutTimerCount = 0
	var positionTimer: Timer?
	var lastPosition: CLLocationCoordinate2D?
	static let emptyNodeNum: UInt32 = 4294967295
	let mqttManager = MqttClientProxyManager.shared
	var wantRangeTestPackets = false
	var wantStoreAndForwardPackets = false
	/* Meshtastic Service Details */
	var TORADIO_characteristic: CBCharacteristic!
	var FROMRADIO_characteristic: CBCharacteristic!
	var FROMNUM_characteristic: CBCharacteristic!
	let meshtasticServiceCBUUID = CBUUID(string: "0x6BA1B218-15A8-461F-9FA8-5DCAE273EAFD")
	let TORADIO_UUID = CBUUID(string: "0xF75C76D2-129E-4DAD-A1DD-7866124401E7")
	let FROMRADIO_UUID = CBUUID(string: "0x2C55E69E-4993-11ED-B878-0242AC120002")
	let EOL_FROMRADIO_UUID = CBUUID(string: "0x8BA2BCC2-EE02-4A55-A531-C525C5E454D5")
	let FROMNUM_UUID = CBUUID(string: "0xED9DA18C-A800-4F66-A670-AA7547E34453")
	
	let meshLog = documentsFolder.appendingPathComponent("meshlog.txt")
	@State var forceCancelConnection:Bool = false
	
	// MARK: init BLEManager
	override init() {
		self.lastConnectionError = ""
		self.connectedVersion = "0.0.0"
		super.init()
		centralManager = CBCentralManager(delegate: self, queue: nil)
		mqttManager.delegate = self
		// centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionRestoreIdentifierKey: restoreKey])
	}
	
	// MARK: Scanning for BLE Devices
	// Scan for nearby BLE devices using the Meshtastic BLE service ID
	func startScanning() {
		if isSwitchedOn {
			centralManager.scanForPeripherals(withServices: [meshtasticServiceCBUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
			print("✅ Scanning Started")
		}
	}
	
	// Stop Scanning For BLE Devices
	func stopScanning() {
		if centralManager.isScanning {
			centralManager.stopScan()
			print("🛑 Stopped Scanning")
		}
	}
	
	// MARK: BLE Connect functions
	/// The action after the timeout-timer has fired
	///
	/// - Parameters:
	///     - timer: The time that fired the event
	///
	@objc func timeoutTimerFired(timer: Timer) {
		guard let timerContext = timer.userInfo as? [String: String] else { return }
		let name: String = timerContext["name", default: "Unknown"]
		
		self.timeoutTimerCount += 1
		self.lastConnectionError = ""
		
		
		if timeoutTimerCount == 10{
			if connectedPeripheral != nil {
				self.centralManager?.cancelPeripheralConnection(connectedPeripheral.peripheral)
			}
			self.isConnected = false
			self.isConnecting = false
			self.lastConnectionError = "🚨 " + String.localizedStringWithFormat("ble.connection.timeout %d %@".localized, timeoutTimerCount, name)
			MeshLogger.log(lastConnectionError)
			self.timeoutTimerCount = 0
			self.startScanning()
		} else {
			print("🚨 BLE Connecting 2 Second Timeout Timer Fired \(timeoutTimerCount) Time(s): \(name)")
		}
	}
	
	// Connect to a specific peripheral
	func connectTo(peripheral: CBPeripheral) {
		stopScanning()
		DispatchQueue.main.async {
			self.isConnecting = true
			self.lastConnectionError = ""
			self.automaticallyReconnect = true
		}
		if connectedPeripheral != nil {
			print("ℹ️ BLE Disconnecting from: \(connectedPeripheral.name) to connect to \(peripheral.name ?? "Unknown")")
			disconnectPeripheral()
		}
		peripheralConnectingTo = peripheral
		centralManager?.connect(peripheral)
		// Invalidate any existing timer
		if timeoutTimer != nil {
			timeoutTimer!.invalidate()
		}
		// Use a timer to keep track of connecting peripherals, context to pass the radio name with the timer and the RunLoop to prevent
		// the timer from running on the main UI thread
		let context = ["name": "\(peripheral.name ?? "Unknown")"]
		timeoutTimer = Timer.scheduledTimer(timeInterval: 1.5, target: self, selector: #selector(timeoutTimerFired), userInfo: context, repeats: true)
		RunLoop.current.add(timeoutTimer!, forMode: .common)
		print("ℹ️ BLE Connecting: \(peripheral.name ?? "Unknown")")
	}
	
	//Force cancel any ongoing connection attempt
	func cancelConnection(){
		if  peripheralConnectingTo.identifier.uuidString == UserDefaults.standard.object(forKey: "preferredPeripheralId") as? String ?? "" {
			UserDefaults.preferredPeripheralId = ""
		}
		self.isConnected = false
		self.isConnecting = false
		self.centralManager?.cancelPeripheralConnection(peripheralConnectingTo)
		self.timeoutTimer?.invalidate()
		self.timeoutTimer = nil
		self.startScanning()
	}
	
	// Disconnect Connected Peripheral
	func disconnectPeripheral(reconnect: Bool = true) {
		
		guard let connectedPeripheral = connectedPeripheral else { return }
		if mqttProxyConnected {
			mqttManager.mqttClientProxy?.disconnect()
		}
		automaticallyReconnect = reconnect
		centralManager?.cancelPeripheralConnection(connectedPeripheral.peripheral)
		FROMRADIO_characteristic = nil
		isConnected = false
		isSubscribed = false
		invalidVersion = false
		connectedVersion = "0.0.0"
		startScanning()
	}
	
	// Called each time a peripheral is discovered
	func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
		isConnecting = false
		isConnected = true
		if UserDefaults.preferredPeripheralId.count < 1 {
			UserDefaults.preferredPeripheralId = peripheral.identifier.uuidString
		}
		// Invalidate and reset connection timer count
		timeoutTimerCount = 0
		if timeoutTimer != nil {
			timeoutTimer!.invalidate()
		}
		
		// remove any connection errors
		self.lastConnectionError = ""
		// Map the peripheral to the connectedPeripheral ObservedObjects
		connectedPeripheral = peripherals.filter({ $0.peripheral.identifier == peripheral.identifier }).first
		if connectedPeripheral != nil {
			connectedPeripheral.peripheral.delegate = self
		} else {
			// we are null just disconnect and start over
			lastConnectionError = "Bluetooth connection error, please try again."
			disconnectPeripheral()
			return
		}
		// Discover Services
		peripheral.discoverServices([meshtasticServiceCBUUID])
		print("✅ BLE Connected: \(peripheral.name ?? "Unknown")")
	}
	
	// Called when a Peripheral fails to connect
	func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
		disconnectPeripheral()
		print("🚫 BLE Failed to Connect: \(peripheral.name ?? "Unknown")")
	}
	
	// Disconnect Peripheral Event
	func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
		self.connectedPeripheral = nil
		self.isConnecting = false
		self.isConnected = false
		self.isSubscribed = false
		let manager = LocalNotificationManager()
		if let e = error {
			// https://developer.apple.com/documentation/corebluetooth/cberror/code
			let errorCode = (e as NSError).code
			if errorCode == 6 { // CBError.Code.connectionTimeout The connection has timed out unexpectedly.
				// Happens when device is manually reset / powered off
				lastConnectionError = "🚨" + String.localizedStringWithFormat("ble.errorcode.6 %@".localized, e.localizedDescription)
				print("🚨 BLE Disconnected: \(peripheral.name ?? "Unknown") Error Code: \(errorCode) Error: \(e.localizedDescription)")
			} else if errorCode == 7 { // CBError.Code.peripheralDisconnected The specified device has disconnected from us.
				// Seems to be what is received when a tbeam sleeps, immediately recconnecting does not work.
				if UserDefaults.preferredPeripheralId == peripheral.identifier.uuidString {
					manager.notifications = [
						Notification(
							id: (peripheral.identifier.uuidString),
							title: "Radio Disconnected",
							subtitle: "\(peripheral.name ?? "unknown".localized)",
							content: e.localizedDescription,
							target: "bluetooth",
							path: "meshtastic://bluetooth"
						)
					]
					manager.schedule()
				}
				lastConnectionError = "🚨 \(e.localizedDescription)"
				print("🚨 BLE Disconnected: \(peripheral.name ?? "Unknown") Error Code: \(errorCode) Error: \(e.localizedDescription)")
			} else if errorCode == 14 { // Peer removed pairing information
				// Forgetting and reconnecting seems to be necessary so we need to show the user an error telling them to do that
				lastConnectionError = "🚨 " + String.localizedStringWithFormat("ble.errorcode.14 %@".localized, e.localizedDescription)
				print("🚨 BLE Disconnected: \(peripheral.name ?? "Unknown") Error Code: \(errorCode) Error: \(lastConnectionError)")
			} else {
				if UserDefaults.preferredPeripheralId == peripheral.identifier.uuidString {
					manager.notifications = [
						Notification(
							id: (peripheral.identifier.uuidString),
							title: "Radio Disconnected",
							subtitle: "\(peripheral.name ?? "unknown".localized)",
							content: e.localizedDescription,
							target: "bluetooth",
							path: "meshtastic://bluetooth"
						)
					]
					manager.schedule()
				}
				lastConnectionError = "🚨 \(e.localizedDescription)"
				print("🚨 BLE Disconnected: \(peripheral.name ?? "Unknown") Error Code: \(errorCode) Error: \(e.localizedDescription)")
			}
		} else {
			// Disconnected without error which indicates user intent to disconnect
			// Happens when swiping to disconnect
			print("ℹ️ BLE Disconnected: \(peripheral.name ?? "Unknown"): User Initiated Disconnect")
		}
		// Start a scan so the disconnected peripheral is moved to the peripherals[] if it is awake
		self.startScanning()
	}
	
	// MARK: Peripheral Services functions
	func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
		if let e = error {
			print("🚫 Discover Services error \(e)")
		}
		guard let services = peripheral.services else { return }
		for service in services {
			if service.uuid == meshtasticServiceCBUUID {
				peripheral.discoverCharacteristics([TORADIO_UUID, FROMRADIO_UUID, FROMNUM_UUID], for: service)
				print("✅ BLE Service for Meshtastic discovered by \(peripheral.name ?? "Unknown")")
			}
		}
	}
	
	// MARK: Discover Characteristics Event
	func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
		
		if let e = error {
			print("🚫 BLE Discover Characteristics error for \(peripheral.name ?? "Unknown") \(e) disconnecting device")
			// Try and stop crashes when this error occurs
			disconnectPeripheral()
			return
		}
		
		guard let characteristics = service.characteristics else { return }
		
		for characteristic in characteristics {
			switch characteristic.uuid {
				
			case TORADIO_UUID:
				print("✅ BLE did discover TORADIO characteristic for Meshtastic by \(peripheral.name ?? "Unknown")")
				TORADIO_characteristic = characteristic
				
			case FROMRADIO_UUID:
				print("✅ BLE did discover FROMRADIO characteristic for Meshtastic by \(peripheral.name ?? "Unknown")")
				FROMRADIO_characteristic = characteristic
				peripheral.readValue(for: FROMRADIO_characteristic)
				
			case FROMNUM_UUID:
				print("✅ BLE did discover FROMNUM (Notify) characteristic for Meshtastic by \(peripheral.name ?? "Unknown")")
				FROMNUM_characteristic = characteristic
				peripheral.setNotifyValue(true, for: characteristic)
				
			default:
				break
			}
		}
		if ![FROMNUM_characteristic, TORADIO_characteristic].contains(nil) {
			if mqttProxyConnected {
				mqttManager.mqttClientProxy?.disconnect()
			}
			sendWantConfig()
		}
	}
	
	// MARK:  MqttClientProxyManagerDelegate Methods
	func onMqttConnected() {
		mqttProxyConnected = true
		mqttError = ""
		print("📲 Mqtt Client Proxy onMqttConnected now subscribing to \(mqttManager.topic).")
		mqttManager.mqttClientProxy?.subscribe(mqttManager.topic)
	}
	
	func onMqttDisconnected() {
		mqttProxyConnected = false
		print("MQTT Disconnected")
	}
	
	func onMqttMessageReceived(message: CocoaMQTTMessage) {

		
		if message.topic.contains("/stat/") {
			return
		}
		var proxyMessage = MqttClientProxyMessage()
		proxyMessage.topic = message.topic
		proxyMessage.data = Data(message.payload)
		proxyMessage.retained = message.retained
		
		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.mqttClientProxyMessage = proxyMessage
		let binaryData: Data = try! toRadio.serializedData()
		if connectedPeripheral?.peripheral.state ?? CBPeripheralState.disconnected == CBPeripheralState.connected {
			connectedPeripheral.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
			
		}
	}
	
	func onMqttError(message: String) {
		mqttProxyConnected = false
		mqttError = message
		print("📲 Mqtt Client Proxy onMqttError: \(message)")
	}
	
	// MARK: Protobuf Methods
	func requestDeviceMetadata(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32, context: NSManagedObjectContext) -> Int64 {
		
		guard connectedPeripheral?.peripheral.state ?? CBPeripheralState.disconnected == CBPeripheralState.connected else { return 0 }
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		meshPacket.decoded = dataMessage
		let messageDescription = "🛎️ Requested Device Metadata for node \(toUser.longName ?? "unknown".localized) by \(fromUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			return Int64(meshPacket.id)
		}
		return 0
	}
	
	func sendTraceRouteRequest(destNum: Int64, wantResponse: Bool) -> Bool {
		
		var success = false
		guard connectedPeripheral?.peripheral.state ?? CBPeripheralState.disconnected == CBPeripheralState.connected else { return success }
		
		let fromNodeNum = connectedPeripheral.num
		let routePacket = RouteDiscovery()
		var meshPacket = MeshPacket()
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.to = UInt32(destNum)
		meshPacket.from	= UInt32(fromNodeNum)
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		dataMessage.payload = try! routePacket.serializedData()
		dataMessage.portnum = PortNum.tracerouteApp
		dataMessage.wantResponse = wantResponse
		meshPacket.decoded = dataMessage
		
		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket
		let binaryData: Data = try! toRadio.serializedData()
		
		if connectedPeripheral?.peripheral.state ?? CBPeripheralState.disconnected == CBPeripheralState.connected {
			connectedPeripheral.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
			success = true
			
			let traceRoute = TraceRouteEntity(context: context!)
			let nodes: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
			nodes.predicate = NSPredicate(format: "num IN %@", [destNum, self.connectedPeripheral.num])
			do {
				guard let fetchedNodes = try context!.fetch(nodes) as? [NodeInfoEntity] else {
					return false
				}
				let receivingNode = fetchedNodes.first(where: { $0.num == destNum })
				let connectedNode = fetchedNodes.first(where: { $0.num == self.connectedPeripheral.num })
				traceRoute.id = Int64(meshPacket.id)
				traceRoute.time = Date()
				traceRoute.node = receivingNode
				// Grab the most recent postion, within the last hour
				if connectedNode?.positions?.count ?? 0 > 0 {
					let mostRecent = connectedNode?.positions?.lastObject as! PositionEntity
					if mostRecent.time! >= Calendar.current.date(byAdding: .hour, value: -24, to: Date())! {
						traceRoute.altitude = mostRecent.altitude
						traceRoute.latitudeI = mostRecent.latitudeI
						traceRoute.longitudeI = mostRecent.longitudeI
						traceRoute.hasPositions = true
					}
				}
				do {
					try context!.save()
					print("💾 Saved TraceRoute sent to node: \(String(receivingNode?.user?.longName ?? "unknown".localized))")
				} catch {
					context!.rollback()
					let nsError = error as NSError
					print("💥 Error Updating Core Data BluetoothConfigEntity: \(nsError)")
				}
			
				let logString = String.localizedStringWithFormat("mesh.log.traceroute.sent %@".localized, String(destNum))
				MeshLogger.log("🪧 \(logString)")
				
			} catch {
				
			}
		}
		return success
	}
	
	func sendWantConfig() {
		guard connectedPeripheral?.peripheral.state ?? CBPeripheralState.disconnected == CBPeripheralState.connected else { return }
		
		if FROMRADIO_characteristic == nil {
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
			let binaryData: Data = try! toRadio.serializedData()
			connectedPeripheral!.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
			// Either Read the config complete value or from num notify value
			guard connectedPeripheral != nil else { return }
			connectedPeripheral!.peripheral.readValue(for: FROMRADIO_characteristic)
		}
	}
	
	func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
		if let errorText = error?.localizedDescription {
			print("🚫 didUpdateNotificationStateFor error: \(errorText)")
		}
	}
	
	// MARK: Data Read / Update Characteristic Event
	func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
		
		if let e = error {
			
			print("🚫 didUpdateValueFor Characteristic error \(e)")
			
			let errorCode = (e as NSError).code
			
			if errorCode == 5 || errorCode == 15 {
				// BLE PIN connection errors
				// 5 CBATTErrorDomain Code=5 "Authentication is insufficient."
				// 15 CBATTErrorDomain Code=15 "Encryption is insufficient."
				lastConnectionError = "🚨" + String.localizedStringWithFormat("ble.errorcode.pin %@".localized, e.localizedDescription)
				print("🚨 \(e.localizedDescription) Please try connecting again and check the PIN carefully.")
				self.disconnectPeripheral(reconnect: false)
			}
		}
		
		switch characteristic.uuid {
			
		case FROMRADIO_UUID:
			
			if characteristic.value == nil || characteristic.value!.isEmpty {
				return
			}
			var decodedInfo = FromRadio()
			
			do {
				decodedInfo = try FromRadio(serializedData: characteristic.value!)
				
			} catch {
				print(characteristic.value!)
			}
			
			// Publish mqttClientProxyMessages received on the from radio
			if decodedInfo.payloadVariant == FromRadio.OneOf_PayloadVariant.mqttClientProxyMessage(decodedInfo.mqttClientProxyMessage) {
				let message = CocoaMQTTMessage (
					topic: decodedInfo.mqttClientProxyMessage.topic,
					payload:  [UInt8](decodedInfo.mqttClientProxyMessage.data),
					retained: decodedInfo.mqttClientProxyMessage.retained
				)
				mqttManager.mqttClientProxy?.publish(message)
			}
			
			switch decodedInfo.packet.decoded.portnum {
				
				// Handle Any local only packets we get over BLE
			case .unknownApp:
				var nowKnown = false
				
				// MyInfo from initial connection
				if context != nil && decodedInfo.myInfo.isInitialized && decodedInfo.myInfo.myNodeNum > 0 {
					let myInfo = myInfoPacket(myInfo: decodedInfo.myInfo, peripheralId: self.connectedPeripheral.id, context: context!)
					
					if myInfo != nil {
						UserDefaults.preferredPeripheralNum = Int(myInfo!.myNodeNum)
						connectedPeripheral.num = myInfo!.myNodeNum
						connectedPeripheral.name = myInfo?.bleName ?? "unknown".localized
						connectedPeripheral.longName = myInfo?.bleName ?? "unknown".localized
					}
					tryClearExistingChannels()
				}
				// NodeInfo
				if decodedInfo.nodeInfo.num > 0 {// && !invalidVersion {
					nowKnown = true
					let nodeInfo = nodeInfoPacket(nodeInfo: decodedInfo.nodeInfo, channel: decodedInfo.packet.channel, context: context!)
					
					if nodeInfo != nil {
						if self.connectedPeripheral != nil && self.connectedPeripheral.num == nodeInfo!.num {
							if nodeInfo!.user != nil {
								connectedPeripheral.shortName = nodeInfo?.user?.shortName ?? "?"
								connectedPeripheral.longName = nodeInfo?.user?.longName ?? "unknown".localized
							}
						}
					}
				}
				// Channels
				if decodedInfo.channel.isInitialized && connectedPeripheral != nil {
					nowKnown = true
					channelPacket(channel: decodedInfo.channel, fromNum: Int64(truncatingIfNeeded: connectedPeripheral.num), context: context!)
				}
				// Config
				if decodedInfo.config.isInitialized && !invalidVersion && connectedPeripheral != nil {
					nowKnown = true
					localConfig(config: decodedInfo.config, context: context!, nodeNum: Int64(truncatingIfNeeded: self.connectedPeripheral.num), nodeLongName: self.connectedPeripheral.longName)
				}
				// Module Config
				if decodedInfo.moduleConfig.isInitialized && !invalidVersion && self.connectedPeripheral?.num != 0{
					nowKnown = true
					moduleConfig(config: decodedInfo.moduleConfig, context: context!, nodeNum: Int64(truncatingIfNeeded: self.connectedPeripheral?.num ?? 0), nodeLongName: self.connectedPeripheral.longName)
					if decodedInfo.moduleConfig.payloadVariant == ModuleConfig.OneOf_PayloadVariant.cannedMessage(decodedInfo.moduleConfig.cannedMessage) {
						if decodedInfo.moduleConfig.cannedMessage.enabled {
							_ = self.getCannedMessageModuleMessages(destNum: self.connectedPeripheral.num, wantResponse: true)
						}
					}
				}
				// Device Metadata
				if decodedInfo.metadata.firmwareVersion.count > 0 && !invalidVersion {
					nowKnown = true
					deviceMetadataPacket(metadata: decodedInfo.metadata, fromNum: connectedPeripheral.num, context: context!)
					connectedPeripheral.firmwareVersion = decodedInfo.metadata.firmwareVersion
					let lastDotIndex = decodedInfo.metadata.firmwareVersion.lastIndex(of: ".")
					if lastDotIndex == nil {
						invalidVersion = true
						connectedVersion = "0.0.0"
					} else {
						let version = decodedInfo.metadata.firmwareVersion[...(lastDotIndex ?? String.Index(utf16Offset: 6, in: decodedInfo.metadata.firmwareVersion))]
						nowKnown = true
						connectedVersion = String(version.dropLast())
						appState.firmwareVersion = connectedVersion
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
				textMessageAppPacket(packet: decodedInfo.packet, wantRangeTestPackets: wantRangeTestPackets, connectedNode: (self.connectedPeripheral != nil ? connectedPeripheral.num : 0), context: context!)
			case .remoteHardwareApp:
				MeshLogger.log("🕸️ MESH PACKET received for Remote Hardware App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure")")
			case .positionApp:
				upsertPositionPacket(packet: decodedInfo.packet, context: context!)
			case .waypointApp:
				waypointPacket(packet: decodedInfo.packet, context: context!)
			case .nodeinfoApp:
				if !invalidVersion { upsertNodeInfoPacket(packet: decodedInfo.packet, context: context!) }
			case .routingApp:
				if !invalidVersion { routingPacket(packet: decodedInfo.packet, connectedNodeNum: self.connectedPeripheral.num, context: context!) }
			case .adminApp:
				adminAppPacket(packet: decodedInfo.packet, context: context!)
			case .replyApp:
				MeshLogger.log("🕸️ MESH PACKET received for Reply App handling as a text message")
				textMessageAppPacket(packet: decodedInfo.packet, wantRangeTestPackets: wantRangeTestPackets, connectedNode: (self.connectedPeripheral != nil ? connectedPeripheral.num : 0), context: context!)
			case .ipTunnelApp:
				//MeshLogger.log("🕸️ MESH PACKET received for IP Tunnel App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure")")
				MeshLogger.log("🕸️ MESH PACKET received for IP Tunnel App UNHANDLED UNHANDLED")
			case .serialApp:
				//MeshLogger.log("🕸️ MESH PACKET received for Serial App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure")")
				MeshLogger.log("🕸️ MESH PACKET received for Serial App UNHANDLED UNHANDLED")
			case .storeForwardApp:
				if wantStoreAndForwardPackets {
					storeAndForwardPacket(packet: decodedInfo.packet, connectedNodeNum: (self.connectedPeripheral != nil ? connectedPeripheral.num : 0), context: context!)
				} else {
					MeshLogger.log("🕸️ MESH PACKET received for Store and Forward App - Store and Forward is disabled.")
				}
			case .rangeTestApp:
				if wantRangeTestPackets {
					textMessageAppPacket(packet: decodedInfo.packet, wantRangeTestPackets: true, connectedNode: (self.connectedPeripheral != nil ? connectedPeripheral.num : 0), context: context!)
				}
				else {
					MeshLogger.log("🕸️ MESH PACKET received for Range Test App Range testing is disabled.")
				}
			case .telemetryApp:
				if !invalidVersion { telemetryPacket(packet: decodedInfo.packet, connectedNode: (self.connectedPeripheral != nil ? connectedPeripheral.num : 0), context: context!) }
			case .textMessageCompressedApp:
				//MeshLogger.log("🕸️ MESH PACKET received for Text Message Compressed App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure")")
				MeshLogger.log("🕸️ MESH PACKET received for Text Message Compressed App UNHANDLED")
			case .zpsApp:
				// MeshLogger.log("🕸️ MESH PACKET received for Zero Positioning System App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure")")
				MeshLogger.log("🕸️ MESH PACKET received for Zero Positioning System App UNHANDLED")
			case .privateApp:
				//MeshLogger.log("🕸️ MESH PACKET received for Private App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure")")
				MeshLogger.log("🕸️ MESH PACKET received for Private App UNHANDLED UNHANDLED")
			case .atakForwarder:
				//MeshLogger.log("🕸️ MESH PACKET received for ATAK Forwarder App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure")")
				MeshLogger.log("🕸️ MESH PACKET received for ATAK Forwarder App UNHANDLED UNHANDLED")
			case .simulatorApp:
				//MeshLogger.log("🕸️ MESH PACKET received for Simulator App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure")")
				MeshLogger.log("🕸️ MESH PACKET received for Simulator App UNHANDLED UNHANDLED")
			case .audioApp:
				//MeshLogger.log("🕸️ MESH PACKET received for Audio App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure")")
				MeshLogger.log("🕸️ MESH PACKET received for Audio App UNHANDLED UNHANDLED")
			case .tracerouteApp:
				if let routingMessage = try? RouteDiscovery(serializedData: decodedInfo.packet.decoded.payload) {
					let traceRoute = getTraceRoute(id: Int64(decodedInfo.packet.decoded.requestID), context: context!)
					traceRoute?.response = true
					traceRoute?.route = routingMessage.route
					if routingMessage.route.count == 0 {
						let logString = String.localizedStringWithFormat("mesh.log.traceroute.received.direct %@".localized, String(decodedInfo.packet.from))
						MeshLogger.log("🪧 \(logString)")
						
					} else {
						var routeString = "You --> "
						var hopNodes: [TraceRouteHopEntity] = []
						for node in routingMessage.route {
							var hopNode = getNodeInfo(id: Int64(node), context: context!)
							if hopNode == nil && hopNode?.num ?? 0 > 0 {
								hopNode = createNodeInfo(num: Int64(node), context: context!)
							}
							let traceRouteHop = TraceRouteHopEntity(context: context!)
							traceRouteHop.time = Date()
							if hopNode?.hasPositions ?? false {
								traceRoute?.hasPositions = true
								let mostRecent = hopNode?.positions?.lastObject as! PositionEntity
								if mostRecent.time! >= Calendar.current.date(byAdding: .minute, value: -60, to: Date())! {
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
								hopNodes.append(traceRouteHop)
							}
							routeString += "\(hopNode?.user?.longName ?? "unknown".localized) \(hopNode?.viaMqtt ?? false ? "MQTT" : "") --> "
						}
						routeString += traceRoute?.node?.user?.longName ?? "unknown".localized
						traceRoute?.routeText = routeString
						traceRoute?.hops = NSOrderedSet(array: hopNodes)
						do {
							try context!.save()
							print("💾 Saved Trace Route")
						} catch {
							context!.rollback()
							let nsError = error as NSError
							print("💥 Error Updating Core Data TraceRouteHOp: \(nsError)")
						}
						let logString = String.localizedStringWithFormat("mesh.log.traceroute.received.route %@".localized, routeString)
						MeshLogger.log("🪧 \(logString)")
					}
				}
			case .neighborinfoApp:
				if let neighborInfo = try? NeighborInfo(serializedData: decodedInfo.packet.decoded.payload) {
					MeshLogger.log("🕸️ MESH PACKET received for Neighbor Info App UNHANDLED")
				//	MeshLogger.log("🕸️ MESH PACKET received for Neighbor Info App UNHANDLED \(neighborInfo)")
				}
			case .paxcounterApp:
				paxCounterPacket(packet: decodedInfo.packet, context: context!)
			case .mapReportApp:
				MeshLogger.log("🕸️ MESH PACKET received for Map Report App UNHANDLED\(try! decodedInfo.packet.jsonString())")
			case .UNRECOGNIZED:
				MeshLogger.log("🕸️ MESH PACKET received for Other App UNHANDLED \(try! decodedInfo.packet.jsonString())")
			case .max:
				print("MAX PORT NUM OF 511")
			case .atakPlugin:
				MeshLogger.log("🕸️ MESH PACKET received for ATAK Plugin App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure")")
		
			}
			
			if decodedInfo.configCompleteID != 0 && decodedInfo.configCompleteID == configNonce {
				invalidVersion = false
				lastConnectionError = ""
				isSubscribed = true
				print("🤜 Want Config Complete. ID:\(decodedInfo.configCompleteID)")
				peripherals.removeAll(where: { $0.peripheral.state == CBPeripheralState.disconnected })
				// Config conplete returns so we don't read the characteristic again
				
				/// MQTT Client Proxy and RangeTest and Store and Forward interest
				if connectedPeripheral.num > 0 {
					
					let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
					fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(connectedPeripheral.num))
					do {
						let fetchedNodeInfo = try context?.fetch(fetchNodeInfoRequest) as? [NodeInfoEntity] ?? []
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
							let appState = AppState.shared
							appState.unreadChannelMessages = fetchedNodeInfo[0].myInfo?.unreadMessages ?? 0
							appState.unreadDirectMessages = fetchedNodeInfo[0].user?.unreadMessages ?? 0
							//appState.connectedNode = fetchedNodeInfo[0]
							UIApplication.shared.applicationIconBadgeNumber = appState.unreadChannelMessages + appState.unreadDirectMessages
							
						}
						if fetchedNodeInfo.count == 1 && fetchedNodeInfo[0].rangeTestConfig?.enabled == true {
							wantRangeTestPackets = true;
						}
						if fetchedNodeInfo.count == 1 && fetchedNodeInfo[0].storeForwardConfig?.enabled == true {
							wantStoreAndForwardPackets = true;
						}
						
					} catch {
						print("Failed to find a node info for the connected node")
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
			
		case FROMNUM_UUID:
			print("🗞️ BLE (Notify) characteristic, value will be read next")
		default:
			print("🚨 Unhandled Characteristic UUID: \(characteristic.uuid)")
		}
		if FROMRADIO_characteristic != nil {
			// Either Read the config complete value or from num notify value
			peripheral.readValue(for: FROMRADIO_characteristic)
		}
	}
	
	public func sendMessage(message: String, toUserNum: Int64, channel: Int32, isEmoji: Bool, replyID: Int64) -> Bool {
		var success = false
		
		// Return false if we are not properly connected to a device, handle retry logic in the view for now
		if connectedPeripheral == nil || connectedPeripheral!.peripheral.state != CBPeripheralState.connected {
			
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
			print("🚫 Don't Send an Empty Message")
			success = false
			
		} else {
			
			let fromUserNum: Int64 = self.connectedPeripheral.num
			
			let messageUsers: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "UserEntity")
			messageUsers.predicate = NSPredicate(format: "num IN %@", [fromUserNum, Int64(toUserNum)])
			
			do {
				
				guard let fetchedUsers = try context?.fetch(messageUsers) as? [UserEntity] else {
					return false
				}
				if fetchedUsers.isEmpty {
					
					print("🚫 Message Users Not Found, Fail")
					success = false
				} else if fetchedUsers.count >= 1 {
					
					let newMessage = MessageEntity(context: context!)
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
						meshPacket.to = Self.emptyNodeNum
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
					let binaryData: Data = try! toRadio.serializedData()
					if connectedPeripheral?.peripheral.state ?? CBPeripheralState.disconnected == CBPeripheralState.connected {
						connectedPeripheral.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
						let logString = String.localizedStringWithFormat("mesh.log.textmessage.sent %@ %@ %@".localized, String(newMessage.messageId), String(fromUserNum), String(toUserNum))
												
						MeshLogger.log("💬 \(logString)")
						do {
							try context!.save()
							print("💾 Saved a new sent message from \(connectedPeripheral.num) to \(toUserNum)")
							success = true
							
						} catch {
							context!.rollback()
							let nsError = error as NSError
							print("💥 Unresolved Core Data error in Send Message Function your database is corrupted running a node db reset should clean up the data. Error: \(nsError)")
						}
					}
				}
				
			} catch {
				
			}
		}
		return success
	}
	
	public func sendWaypoint(waypoint: Waypoint) -> Bool {
		if waypoint.latitudeI == 373346000 && waypoint.longitudeI == -1220090000 {
			return false
		}
		var success = false
		let fromNodeNum = UInt32(connectedPeripheral.num)
		var meshPacket = MeshPacket()
		meshPacket.to = Self.emptyNodeNum
		meshPacket.from	= fromNodeNum
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		do {
			dataMessage.payload = try waypoint.serializedData()
		}
		catch {
			// Could not serialiaze the payload
			return false
		}
		
		dataMessage.portnum = PortNum.waypointApp
		meshPacket.decoded = dataMessage
		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket
		let binaryData: Data = try! toRadio.serializedData()
		let logString = String.localizedStringWithFormat("mesh.log.waypoint.sent %@".localized, String(fromNodeNum))
		MeshLogger.log("📍 \(logString)")
		if connectedPeripheral?.peripheral.state ?? CBPeripheralState.disconnected == CBPeripheralState.connected {
			connectedPeripheral.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
			success = true
			let wayPointEntity = getWaypoint(id: Int64(waypoint.id), context: context!)
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
				try context!.save()
				print("💾 Updated Waypoint from Waypoint App Packet From: \(fromNodeNum)")
			} catch {
				context!.rollback()
				let nsError = error as NSError
				print("💥 Error Saving NodeInfoEntity from WAYPOINT_APP \(nsError)")
			}
		}
		return success
	}
	
	public func getPositionFromPhoneGPS(channel: Int32, destNum: Int64) -> Position? {
		var positionPacket = Position()
		
		let fetchChannelRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "ChannelEntity")
		fetchChannelRequest.predicate = NSPredicate(format: "index == %lld", channel)

		do {
			guard let fetchedChannel = try context!.fetch(fetchChannelRequest) as? [ChannelEntity] else {
				return nil
			}
			if #available(iOS 17.0, macOS 14.0, *) {
				
				if let lastLocation = LocationsHandler.shared.locationsArray.last {
					
					positionPacket.latitudeI = Int32(lastLocation.coordinate.latitude * 1e7)
					positionPacket.longitudeI = Int32(lastLocation.coordinate.longitude * 1e7)
					let timestamp = lastLocation.timestamp
					positionPacket.time = UInt32(timestamp.timeIntervalSince1970)
					positionPacket.timestamp = UInt32(timestamp.timeIntervalSince1970)
					positionPacket.altitude = Int32(lastLocation.altitude)
					positionPacket.satsInView = UInt32(LocationsHandler.satsInView)
					positionPacket.precisionBits = UInt32(fetchedChannel[0].positionPrecision)
					let currentSpeed = lastLocation.speed
					if currentSpeed > 0 && (!currentSpeed.isNaN || !currentSpeed.isInfinite)  {
						positionPacket.groundSpeed = UInt32(currentSpeed * 3.6)
					}
					let currentHeading = lastLocation.course
					if currentHeading > 0 && (!currentHeading.isNaN || !currentHeading.isInfinite) {
						positionPacket.groundTrack = UInt32(currentHeading)
					}
					
				}

			} else {
				if destNum <= 0 || LocationHelper.currentLocation.distance(from: LocationHelper.DefaultLocation) == 0.0 {
					return nil
				}
				positionPacket.latitudeI = Int32(LocationHelper.currentLocation.latitude * 1e7)
				positionPacket.longitudeI = Int32(LocationHelper.currentLocation.longitude * 1e7)
				let timestamp = LocationHelper.shared.locationManager.location?.timestamp ?? Date()
				positionPacket.time = UInt32(timestamp.timeIntervalSince1970)
				positionPacket.timestamp = UInt32(timestamp.timeIntervalSince1970)
				positionPacket.altitude = Int32(LocationHelper.shared.locationManager.location?.altitude ?? 0)
				positionPacket.satsInView = UInt32(LocationHelper.satsInView)
				positionPacket.precisionBits = UInt32(fetchedChannel[0].positionPrecision)
				let currentSpeed = LocationHelper.shared.locationManager.location?.speed ?? 0
				if currentSpeed > 0 && (!currentSpeed.isNaN || !currentSpeed.isInfinite)  {
					positionPacket.groundSpeed = UInt32(currentSpeed * 3.6)
				}
				let currentHeading  = LocationHelper.shared.locationManager.location?.course ?? 0
				if currentHeading > 0 && (!currentHeading.isNaN || !currentHeading.isInfinite) {
					positionPacket.groundTrack = UInt32(currentHeading)
				}
			}
			
		} catch {
			return nil
		}
		
		return positionPacket
	}
	
	public func setFixedPosition(fromUser: UserEntity, channel: Int32) -> Bool {
		var adminPacket = AdminMessage()
		guard let positionPacket = getPositionFromPhoneGPS(channel: channel, destNum: fromUser.num) else {
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		let messageDescription = "🚀 Sent Set Fixed Postion Admin Message to: \(fromUser.longName ?? "unknown".localized) from: \(fromUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: fromUser) {
			return true
		}
		return false
	}
	
	public func removeFixedPosition(fromUser: UserEntity, channel: Int32) -> Bool {
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		let messageDescription = "🚀 Sent Remove Fixed Position Admin Message to: \(fromUser.longName ?? "unknown".localized) from: \(fromUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: fromUser) {
			return true
		}
		return false
	}
	
	public func sendPosition(channel: Int32, destNum: Int64, wantResponse: Bool) -> Bool {
		var success = false
		let fromNodeNum = connectedPeripheral.num
		guard let positionPacket = getPositionFromPhoneGPS(channel: channel, destNum: destNum) else {
			return false
		}

		var meshPacket = MeshPacket()
		meshPacket.to = UInt32(destNum)
		meshPacket.channel = UInt32(channel)
		meshPacket.from	= UInt32(fromNodeNum)
		var dataMessage = DataMessage()
		dataMessage.payload = try! positionPacket.serializedData()
		dataMessage.portnum = PortNum.positionApp
		dataMessage.wantResponse = wantResponse
		meshPacket.decoded = dataMessage
		
		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket
		let binaryData: Data = try! toRadio.serializedData()
		if connectedPeripheral?.peripheral.state ?? CBPeripheralState.disconnected == CBPeripheralState.connected {
			connectedPeripheral.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
			success = true
			let logString = String.localizedStringWithFormat("mesh.log.sharelocation %@".localized, String(fromNodeNum))
			print("📍 \(logString)")
		}
		return success
	}
	@objc func positionTimerFired(timer: Timer) {
		// Check for connected node
		if connectedPeripheral != nil {
			// Send a position out to the mesh if "share location with the mesh" is enabled in settings
			if UserDefaults.provideLocation {
				let _ = sendPosition(channel: 0, destNum: connectedPeripheral.num, wantResponse: false)
			}
		}
	}
	
	public func sendShutdown(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		let messageDescription = "🚀 Sent Shutdown Admin Message to: \(toUser.longName ?? "unknown".localized) from: \(fromUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			return true
		}
		return false
	}
	
	public func sendReboot(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		let messageDescription = "🚀 Sent Reboot Admin Message to: \(toUser.longName ?? "unknown".localized) from: \(fromUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			return true
		}
		return false
	}
	
	public func sendRebootOta(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		let messageDescription = "🚀 Sent Reboot OTA Admin Message to: \(toUser.longName ?? "unknown".localized) from: \(fromUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			return true
		}
		return false
	}
	
	public func sendEnterDfuMode(fromUser: UserEntity, toUser: UserEntity) -> Bool {
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		automaticallyReconnect = false
		let messageDescription = "🚀 Sent enter DFU mode Admin Message to: \(toUser.longName ?? "unknown".localized) from: \(fromUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			return true
		}
		return false
	}
	
	public func sendFactoryReset(fromUser: UserEntity, toUser: UserEntity) -> Bool {
		var adminPacket = AdminMessage()
		adminPacket.factoryReset = 5
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	=  UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🚀 Sent Factory Reset Admin Message to: \(toUser.longName ?? "unknown".localized) from: \(fromUser.longName ??  "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			return true
		}
		return false
	}
	
	public func sendNodeDBReset(fromUser: UserEntity, toUser: UserEntity) -> Bool {
		var adminPacket = AdminMessage()
		adminPacket.nodedbReset = 5
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= 0 // UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		
		meshPacket.decoded = dataMessage
		let messageDescription = "🚀 Sent NodeDB Reset Admin Message to: \(toUser.longName ?? "unknown".localized) from: \(fromUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			return true
		}
		return false
	}
	
	public func connectToPreferredPeripheral() -> Bool {
		var success = false
		// Return false if we are not properly connected to a device, handle retry logic in the view for now
		if connectedPeripheral == nil || connectedPeripheral!.peripheral.state != CBPeripheralState.connected {
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
	
	public func getChannel(channel: Channel, fromUser: UserEntity, toUser: UserEntity) -> Int64 {
		
		var adminPacket = AdminMessage()
		adminPacket.getChannelRequest = UInt32(channel.index + 1)
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		var dataMessage = DataMessage()
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🎛️ Requested Channel \(channel.index) for \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			return Int64(meshPacket.id)
		}
		return 0
	}
	public func saveChannel(channel: Channel, fromUser: UserEntity, toUser: UserEntity) -> Int64 {
		
		var adminPacket = AdminMessage()
		adminPacket.setChannel = channel
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		var dataMessage = DataMessage()
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛟 Saved Channel \(channel.index) for \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			return Int64(meshPacket.id)
		}
		return 0
	}
	
	public func saveChannelSet(base64UrlString: String, addChannels: Bool = false) -> Bool {
		if isConnected {
			
			var i: Int32 = 0
			// Before we get started delete the existing channels from the myNodeInfo
			if !addChannels {
				tryClearExistingChannels()
			} else {
				// We are trying to add a channel so lets get the last index
				let fetchMyInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "MyInfoEntity")
				fetchMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", Int64(connectedPeripheral.num))
				do {
					let fetchedMyInfo = try context?.fetch(fetchMyInfoRequest) as? [MyInfoEntity] ?? []
					if fetchedMyInfo.count == 1 {
						if addChannels {
							i = Int32(fetchedMyInfo[0].channels?.count ?? -1)
							// Bail out if the index is negative or bigger than our max of 8
							if i < 0 || i > 8 {
								return false
							}
						}
					}
				} catch {
					print("Failed to find a node MyInfo to save these channels to")
				}
			}
			let decodedString = base64UrlString.base64urlToBase64()
			if let decodedData = Data(base64Encoded: decodedString) {
				do {
					let channelSet: ChannelSet = try ChannelSet(serializedData: decodedData)
					for cs in channelSet.settings {
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
						dataMessage.payload = try! adminPacket.serializedData()
						dataMessage.portnum = PortNum.adminApp
						meshPacket.decoded = dataMessage
						var toRadio: ToRadio!
						toRadio = ToRadio()
						toRadio.packet = meshPacket
						let binaryData: Data = try! toRadio.serializedData()
						if connectedPeripheral?.peripheral.state ?? CBPeripheralState.disconnected == CBPeripheralState.connected {
							self.connectedPeripheral.peripheral.writeValue(binaryData, for: self.TORADIO_characteristic, type: .withResponse)
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
					dataMessage.payload = try! adminPacket.serializedData()
					dataMessage.portnum = PortNum.adminApp
					meshPacket.decoded = dataMessage
					var toRadio: ToRadio!
					toRadio = ToRadio()
					toRadio.packet = meshPacket
					let binaryData: Data = try! toRadio.serializedData()
					if connectedPeripheral?.peripheral.state ?? CBPeripheralState.disconnected == CBPeripheralState.connected {
						self.connectedPeripheral.peripheral.writeValue(binaryData, for: self.TORADIO_characteristic, type: .withResponse)
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
	
	public func saveUser(config: User, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		let messageDescription = "🛟 Saved User Config for \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			return Int64(meshPacket.id)
		}
		return 0
	}
	
	public func removeNode(node: NodeInfoEntity, connectedNodeNum: Int64) -> Bool {
		var adminPacket = AdminMessage()
		adminPacket.removeByNodenum = UInt32(node.num)
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(connectedNodeNum)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket
		let binaryData: Data = try! toRadio.serializedData()
		
		if connectedPeripheral?.peripheral.state ?? CBPeripheralState.disconnected == CBPeripheralState.connected{
			do {
				connectedPeripheral.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
				context!.delete(node.user!)
				context!.delete(node)
				try context!.save()
				return true
			} catch {
				context!.rollback()
				let nsError = error as NSError
				print("💥 Error deleting node from core data: \(nsError)")
			}
		}
		return false
	}
	
	public func setFavoriteNode(node: NodeInfoEntity, connectedNodeNum: Int64) -> Bool {
		var adminPacket = AdminMessage()
		adminPacket.setFavoriteNode = UInt32(node.num)
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(connectedNodeNum)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket
		let binaryData: Data = try! toRadio.serializedData()
		
		if connectedPeripheral?.peripheral.state ?? CBPeripheralState.disconnected == CBPeripheralState.connected{
			connectedPeripheral.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
				return true
		}
		return false
	}
	
	public func removeFavoriteNode(node: NodeInfoEntity, connectedNodeNum: Int64) -> Bool {
		var adminPacket = AdminMessage()
		adminPacket.removeFavoriteNode = UInt32(node.num)
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(connectedNodeNum)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		var dataMessage = DataMessage()
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket
		let binaryData: Data = try! toRadio.serializedData()
		
		if connectedPeripheral?.peripheral.state ?? CBPeripheralState.disconnected == CBPeripheralState.connected{
			connectedPeripheral.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
				return true
		}
		return false
	}
	
	public func saveLicensedUser(ham: HamParameters, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		let messageDescription = "🛟 Saved Ham Parameters for \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			return Int64(meshPacket.id)
		}
		return 0
	}
	public func saveBluetoothConfig(config: Config.BluetoothConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		let messageDescription = "🛟 Saved Bluetooth Config for \(toUser.longName ?? "unknown".localized)"
		
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			upsertBluetoothConfigPacket(config: config, nodeNum: toUser.num, context: context!)
			return Int64(meshPacket.id)
		}
		
		return 0
	}
	
	public func saveDeviceConfig(config: Config.DeviceConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		let messageDescription = "🛟 Saved Device Config for \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			upsertDeviceConfigPacket(config: config, nodeNum: toUser.num, context: context!)
			return Int64(meshPacket.id)
		}
		return 0
	}
	
	public func saveDisplayConfig(config: Config.DisplayConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		let messageDescription = "🛟 Saved Display Config for \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			upsertDisplayConfigPacket(config: config, nodeNum: toUser.num, context: context!)
			return Int64(meshPacket.id)
		}
		return 0
	}
	
	public func saveLoRaConfig(config: Config.LoRaConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		let messageDescription = "🛟 Saved LoRa Config for \(toUser.longName ?? "unknown".localized)"
		
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			upsertLoRaConfigPacket(config: config, nodeNum: toUser.num, context: context!)
			return Int64(meshPacket.id)
		}
		
		return 0
	}
	
	public func savePositionConfig(config: Config.PositionConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛟 Saved Position Config for \(toUser.longName ?? "unknown".localized)"
		
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			upsertPositionConfigPacket(config: config, nodeNum: toUser.num, context: context!)
			return Int64(meshPacket.id)
		}
		
		return 0
	}

	public func savePowerConfig(config: Config.PowerConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {

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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp

		meshPacket.decoded = dataMessage

		let messageDescription = "🛟 Saved Power Config for \(toUser.longName ?? "unknown".localized)"

		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			upsertPowerConfigPacket(config: config, nodeNum: toUser.num, context: context!)
			return Int64(meshPacket.id)
		}

		return 0
	}

	public func saveNetworkConfig(config: Config.NetworkConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛟 Saved Network Config for \(toUser.longName ?? "unknown".localized)"
		
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			upsertNetworkConfigPacket(config: config, nodeNum: toUser.num, context: context!)
			return Int64(meshPacket.id)
		}
		
		return 0
	}
	
	public func saveAmbientLightingModuleConfig(config: ModuleConfig.AmbientLightingConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛟 Saved Ambient Lighting Module Config for \(toUser.longName ?? "unknown".localized)"
		
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			upsertAmbientLightingModuleConfigPacket(config: config, nodeNum: toUser.num, context: context!)
			return Int64(meshPacket.id)
		}
		
		return 0
	}
	
	public func saveCannedMessageModuleConfig(config: ModuleConfig.CannedMessageConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛟 Saved Canned Message Module Config for \(toUser.longName ?? "unknown".localized)"
		
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			upsertCannedMessagesModuleConfigPacket(config: config, nodeNum: toUser.num, context: context!)
			return Int64(meshPacket.id)
		}
		
		return 0
	}
	
	public func saveCannedMessageModuleMessages(messages: String, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛟 Saved Canned Message Module Messages for \(toUser.longName ?? "unknown".localized)"
		
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			
			return Int64(meshPacket.id)
		}
		
		return 0
	}
	
	public func saveDetectionSensorModuleConfig(config: ModuleConfig.DetectionSensorConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛟 Saved Detection Sensor Module Config for \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			upsertDetectionSensorModuleConfigPacket(config: config, nodeNum: toUser.num, context: context!)
			return Int64(meshPacket.id)
		}
		return 0
	}
	
	public func saveExternalNotificationModuleConfig(config: ModuleConfig.ExternalNotificationConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛟 Saved External Notification Module Config for \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			upsertExternalNotificationModuleConfigPacket(config: config, nodeNum: toUser.num, context: context!)
			return Int64(meshPacket.id)
		}
		return 0
	}
	
	public func savePaxcounterModuleConfig(config: ModuleConfig.PaxcounterConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛟 Saved PAX Counter Module Config for \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			upsertPaxCounterModuleConfigPacket(config: config, nodeNum: toUser.num, context: context!)
			return Int64(meshPacket.id)
		}
		
		return 0
	}
	
	public func saveRtttlConfig(ringtone: String, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛟 Saved RTTTL Ringtone Config for \(toUser.longName ?? "unknown".localized)"
		
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			upsertRtttlConfigPacket(ringtone: ringtone, nodeNum: toUser.num, context: context!)
			return Int64(meshPacket.id)
		}
		
		return 0
	}
	
	public func saveMQTTConfig(config: ModuleConfig.MQTTConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛟 Saved MQTT Config for \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			upsertMqttModuleConfigPacket(config: config, nodeNum: toUser.num, context: context!)
			return Int64(meshPacket.id)
		}
		return 0
	}
	
	public func saveRangeTestModuleConfig(config: ModuleConfig.RangeTestConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛟 Saved Range Test Module Config for \(toUser.longName ?? "unknown".localized)"
		
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			upsertRangeTestModuleConfigPacket(config: config, nodeNum: toUser.num, context: context!)
			return Int64(meshPacket.id)
		}
		
		return 0
	}
	
	public func saveSerialModuleConfig(config: ModuleConfig.SerialConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛟 Saved Serial Module Config for \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			upsertSerialModuleConfigPacket(config: config, nodeNum: toUser.num, context: context!)
			return Int64(meshPacket.id)
		}
		return 0
	}
	
	public func saveStoreForwardModuleConfig(config: ModuleConfig.StoreForwardConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛟 Saved Store & Forward Module Config for \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			upsertStoreForwardModuleConfigPacket(config: config, nodeNum: toUser.num, context: context!)
			return Int64(meshPacket.id)
		}
		return 0
	}
	
	public func saveTelemetryModuleConfig(config: ModuleConfig.TelemetryConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		meshPacket.decoded = dataMessage
		
		let messageDescription = "Saved Telemetry Module Config for \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			upsertTelemetryModuleConfigPacket(config: config, nodeNum: toUser.num, context: context!)
			return Int64(meshPacket.id)
		}
		return 0
	}
	
	public func getChannel(channelIndex: UInt32, fromUser: UserEntity, toUser: UserEntity, wantResponse: Bool) -> Bool {
		
		var adminPacket = AdminMessage()
		adminPacket.getChannelRequest = channelIndex
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(toUser.num)
		meshPacket.from	= UInt32(fromUser.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = wantResponse
		
		var dataMessage = DataMessage()
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Sent a Get Channel \(channelIndex) Request Admin Message for node: \(toUser.longName ?? "unknown".localized))"
		
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			
			return true
		}
		
		return false
	}
	
	public func getCannedMessageModuleMessages(destNum: Int64, wantResponse: Bool) -> Bool {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = wantResponse
		
		meshPacket.decoded = dataMessage
		
		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket
		
		let binaryData: Data = try! toRadio.serializedData()
		
		if connectedPeripheral?.peripheral.state ?? CBPeripheralState.disconnected == CBPeripheralState.connected {
			connectedPeripheral.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
			let logString = String.localizedStringWithFormat("mesh.log.cannedmessages.messages.get %@".localized, String(connectedPeripheral.num))
			MeshLogger.log("🥫 \(logString)")
			return true
		}
		
		return false
	}
	
	public func requestBluetoothConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested Bluetooth Config on admin channel \(adminIndex) for node: \(String(connectedPeripheral.num))"
		
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			return true
		}
		return false
	}
	
	public func requestDeviceConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested Device Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			return true
		}
		return false
	}
	
	public func requestDisplayConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested Display Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			return true
		}
		return false
	}
	
	public func requestLoRaConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested LoRa Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			
			return true
		}
		
		return false
	}
	
	public func requestNetworkConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested Network Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			return true
		}
		return false
	}
	
	public func requestPositionConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested Position Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			return true
		}
		return false
	}

	public func requestPowerConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {

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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true

		meshPacket.decoded = dataMessage

		let messageDescription = "🛎️ Requested Power Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			return true
		}
		return false
	}

	public func requestAmbientLightingConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested Ambient Lighting Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			return true
		}
		return false
	}
	
	public func requestCannedMessagesModuleConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested Canned Messages Module Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			return true
		}
		return false
	}
	
	public func requestExternalNotificationModuleConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested External Notificaiton Module Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			return true
		}
		return false
	}
	
	public func requestPaxCounterModuleConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested PAX Counter Module Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			return true
		}
		return false
	}
	
	public func requestRtttlConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested RTTTL Ringtone Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			return true
		}
		return false
	}
	
	public func requestRangeTestModuleConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested Range Test Module Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			return true
		}
		return false
	}
	
	public func requestMqttModuleConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested MQTT Module Config on admin channel \(adminIndex) for node: \(String(connectedPeripheral.num))"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			return true
		}
		return false
	}
	
	public func requestDetectionSensorModuleConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested Detection Sensor Module Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			return true
		}
		return false
	}
	
	
	public func requestSerialModuleConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested Serial Module Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			return true
		}
		return false
	}
	
	public func requestStoreAndForwardModuleConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested Store and Forward Module Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			return true
		}
		return false
	}
	
	public func requestTelemetryModuleConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		
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
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = true
		
		meshPacket.decoded = dataMessage
		
		let messageDescription = "🛎️ Requested Telemetry Module Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription, fromUser: fromUser, toUser: toUser) {
			return true
		}
		return false
	}
	
	// Send an admin message to a radio, save a message to core data for logging
	private func sendAdminMessageToRadio(meshPacket: MeshPacket, adminDescription: String, fromUser: UserEntity, toUser: UserEntity) -> Bool {
		
		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket
		let binaryData: Data = try! toRadio.serializedData()
		
		if connectedPeripheral?.peripheral.state ?? CBPeripheralState.disconnected == CBPeripheralState.connected{
			let newMessage = MessageEntity(context: context!)
			newMessage.messageId =  Int64(meshPacket.id)
			newMessage.messageTimestamp =  Int32(Date().timeIntervalSince1970)
			newMessage.receivedACK = false
			newMessage.admin = true
			newMessage.adminDescription = adminDescription
			newMessage.fromUser = fromUser
			newMessage.toUser = toUser
			
			do {
				connectedPeripheral.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
				try context!.save()
				return true
			} catch {
				context!.rollback()
				let nsError = error as NSError
				print("💥 Error inserting new core data MessageEntity: \(nsError)")
			}
		}
		return false
	}
	
	public func requestStoreAndForwardClientHistory(fromUser: UserEntity, toUser: UserEntity) -> Bool {
		
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
		dataMessage.payload = try! sfPacket.serializedData()
		dataMessage.portnum = PortNum.storeForwardApp
		dataMessage.wantResponse = true
		meshPacket.decoded = dataMessage

		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket
		let binaryData: Data = try! toRadio.serializedData()
		if connectedPeripheral?.peripheral.state ?? CBPeripheralState.disconnected == CBPeripheralState.connected {
			connectedPeripheral.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
			print("📮 Sent a request for a Store & Forward Client History to \(toUser.num) for the last \(120) minutes.")
			return true
		}
		return false
	}
	
	func storeAndForwardPacket(packet: MeshPacket, connectedNodeNum: Int64, context: NSManagedObjectContext) {
		if let storeAndForwardMessage = try? StoreAndForward(serializedData: packet.decoded.payload) {
			// Handle each of the store and forward request / response messages
			switch storeAndForwardMessage.rr {
			case .unset:
				MeshLogger.log("📮 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from)")
			case .routerError:
				MeshLogger.log("☠️ Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from)")
			case .routerHeartbeat:
				/// When we get a router heartbeat we know there is a store and forward node on the network
				/// Check if it is the primary S&F Router and save the timestamp of the last heartbeat so that we can show the request message history menu item on node long press if the router has been seen recently
				if (storeAndForwardMessage.heartbeat.secondary == 0) {
					
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
						print("💥 Save Store and Forward Router Error")
					}
				}
				MeshLogger.log("💓 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from)")
			case .routerPing:
				MeshLogger.log("🏓 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from)")
			case .routerPong:
				MeshLogger.log("🏓 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from)")
			case .routerBusy:
				MeshLogger.log("🐝 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from)")
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
					print("💥 Save Store and Forward Router Error")
				}
				MeshLogger.log("📜 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from)")
			case .routerStats:
				MeshLogger.log("📊 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from)")
			case .clientError:
				MeshLogger.log("☠️ Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from)")
			case .clientHistory:
				MeshLogger.log("📜 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from)")
			case .clientStats:
				MeshLogger.log("📊 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from)")
			case .clientPing:
				MeshLogger.log("🏓 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from)")
			case .clientPong:
				MeshLogger.log("🏓 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from)")
			case .clientAbort:
				MeshLogger.log("🛑 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from)")
			case .UNRECOGNIZED:
				MeshLogger.log("📮 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from)")
			case .routerTextDirect:
				MeshLogger.log("💬 Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from)")
				textMessageAppPacket(packet: packet, wantRangeTestPackets: false, connectedNode: connectedNodeNum, storeForward: true, context: context)
			case .routerTextBroadcast:
				MeshLogger.log("✉️ Store and Forward \(storeAndForwardMessage.rr) message received from \(packet.from)")
				textMessageAppPacket(packet: packet, wantRangeTestPackets: false, connectedNode: connectedNodeNum, storeForward: true, context: context)
			}
		}
	}
	
	public func tryClearExistingChannels() {
		// Before we get started delete the existing channels from the myNodeInfo
		let fetchMyInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "MyInfoEntity")
		fetchMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", Int64(connectedPeripheral.num))
		
		do {
			let fetchedMyInfo = try context?.fetch(fetchMyInfoRequest) as? [MyInfoEntity] ?? []
			if fetchedMyInfo.count == 1 {
				let mutableChannels = fetchedMyInfo[0].channels?.mutableCopy() as? NSMutableOrderedSet
				mutableChannels?.removeAllObjects()
				fetchedMyInfo[0].channels = mutableChannels
				do {
					try context!.save()
				} catch {
					print("Failed to clear existing channels from local app database")
				}
			}
		} catch {
			print("Failed to find a node MyInfo to save these channels to")
		}
	}
}

// MARK: - CB Central Manager implmentation
extension BLEManager: CBCentralManagerDelegate {
	
	// MARK: Bluetooth enabled/disabled
	func centralManagerDidUpdateState(_ central: CBCentralManager) {
		if central.state == CBManagerState.poweredOn {
			print("BLE powered on")
			isSwitchedOn = true
			startScanning()
		} else {
			isSwitchedOn = false
		}
		
		var status = ""
		
		switch central.state {
		case .poweredOff:
			status = "BLE is powered off"
		case .poweredOn:
			status = "BLE is poweredOn"
		case .resetting:
			status = "BLE is resetting"
		case .unauthorized:
			status = "BLE is unauthorized"
		case .unknown:
			status = "BLE is unknown"
		case .unsupported:
			status = "BLE is unsupported"
		default:
			status = "default"
		}
		print("BLEManager status: \(status)")
	}
	
	// Called each time a peripheral is discovered
	func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
		
		if self.automaticallyReconnect && peripheral.identifier.uuidString == UserDefaults.standard.object(forKey: "preferredPeripheralId") as? String ?? "" {
			self.connectTo(peripheral: peripheral)
			print("ℹ️ BLE Reconnecting to prefered peripheral: \(peripheral.name ?? "Unknown")")
		}
		let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String
		let device = Peripheral(id: peripheral.identifier.uuidString, num: 0, name: name ?? "Unknown", shortName: "?", longName: name ?? "Unknown", firmwareVersion: "Unknown", rssi: RSSI.intValue, lastUpdate: Date(), peripheral: peripheral)
		let index = peripherals.map { $0.peripheral }.firstIndex(of: peripheral)
		
		if let peripheralIndex = index {
			peripherals[peripheralIndex] = device
		} else {
			peripherals.append(device)
		}
		let today = Date()
		let visibleDuration = Calendar.current.date(byAdding: .second, value: -5, to: today)!
		self.peripherals.removeAll(where: { $0.lastUpdate < visibleDuration})
	}
}
