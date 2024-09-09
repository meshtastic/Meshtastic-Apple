import Foundation
import CoreData
import CoreBluetooth
import SwiftUI
import MapKit
import MeshtasticProtobufs
import CocoaMQTT
import OSLog

// ---------------------------------------------------------------------------------------
// Meshtastic BLE Device Manager
// ---------------------------------------------------------------------------------------
class BLEManager: NSObject, CBPeripheralDelegate, MqttClientProxyManagerDelegate, ObservableObject {
	static var shared: BLEManager! // Singleton instance

	let appState: AppState

	let context: NSManagedObjectContext

	private var centralManager: CBCentralManager!

	@Published var peripherals: [Peripheral] = []
	@Published var connectedPeripheral: Peripheral!
	@Published var lastConnectionError: String
	@Published var invalidVersion = false
	@Published var isSwitchedOn: Bool = false
	@Published var automaticallyReconnect: Bool = true
	@Published var mqttProxyConnected: Bool = false
	@Published var mqttError: String = ""
	public var minimumVersion = "2.0.0"
	public var connectedVersion: String
	public var isConnecting: Bool = false
	public var isConnected: Bool = false
	public var isSubscribed: Bool = false
	private var configNonce: UInt32 = 1
	var timeoutTimer: Timer?
	var timeoutTimerCount = 0
	var positionTimer: Timer?
	let mqttManager = MqttClientProxyManager.shared
	var wantRangeTestPackets = false
	var wantStoreAndForwardPackets = false
	/* Meshtastic Service Details */
	var TORADIO_characteristic: CBCharacteristic!
	var FROMRADIO_characteristic: CBCharacteristic!
	var FROMNUM_characteristic: CBCharacteristic!
	var LEGACY_LOGRADIO_characteristic: CBCharacteristic!
	var LOGRADIO_characteristic: CBCharacteristic!
	let meshtasticServiceCBUUID = CBUUID(string: "0x6BA1B218-15A8-461F-9FA8-5DCAE273EAFD")
	let TORADIO_UUID = CBUUID(string: "0xF75C76D2-129E-4DAD-A1DD-7866124401E7")
	let FROMRADIO_UUID = CBUUID(string: "0x2C55E69E-4993-11ED-B878-0242AC120002")
	let EOL_FROMRADIO_UUID = CBUUID(string: "0x8BA2BCC2-EE02-4A55-A531-C525C5E454D5")
	let FROMNUM_UUID = CBUUID(string: "0xED9DA18C-A800-4F66-A670-AA7547E34453")
	let LEGACY_LOGRADIO_UUID = CBUUID(string: "0x6C6FD238-78FA-436B-AACF-15C5BE1EF2E2")
	let LOGRADIO_UUID = CBUUID(string: "0x5a3d6e49-06e6-4423-9944-e9de8cdf9547")

	// MARK: init

	private override init() {
		   // Default initialization should not be used
		   fatalError("Use setup(appState:context:) to initialize the singleton")
	   }

	   static func setup(appState: AppState, context: NSManagedObjectContext) {
		   guard shared == nil else {
			   print("BLEManager already initialized")
			   return
		   }
		   shared = BLEManager(appState: appState, context: context)
	   }

	   private init(appState: AppState, context: NSManagedObjectContext) {
		   self.appState = appState
		   self.context = context
		   self.lastConnectionError = ""
		   self.connectedVersion = "0.0.0"
		   super.init()
		   centralManager = CBCentralManager(delegate: self, queue: nil)
		   mqttManager.delegate = self
	   }

	// MARK: Scanning for BLE Devices
	// Scan for nearby BLE devices using the Meshtastic BLE service ID
	func startScanning() {
		if isSwitchedOn {
			centralManager.scanForPeripherals(withServices: [meshtasticServiceCBUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
			Logger.services.info("✅ [BLE] Scanning Started")
		}
	}

	// Stop Scanning For BLE Devices
	func stopScanning() {
		if centralManager.isScanning {
			centralManager.stopScan()
			Logger.services.info("🛑 [BLE] Stopped Scanning")
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

		if timeoutTimerCount == 10 {
			if connectedPeripheral != nil {
				self.centralManager?.cancelPeripheralConnection(connectedPeripheral.peripheral)
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

	// Connect to a specific peripheral
	func connectTo(peripheral: CBPeripheral) {
		stopScanning()
		DispatchQueue.main.async {
			self.isConnecting = true
			self.lastConnectionError = ""
			self.automaticallyReconnect = true
		}
		if connectedPeripheral != nil {
			Logger.services.info("ℹ️ [BLE] Disconnecting from: \(self.connectedPeripheral.name, privacy: .public) to connect to \(peripheral.name ?? "Unknown", privacy: .public)")
			disconnectPeripheral()
		}

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
		Logger.services.info("ℹ️ BLE Connecting: \(peripheral.name ?? "Unknown", privacy: .public)")
	}

	// Disconnect Connected Peripheral
	func cancelPeripheralConnection() {

		if mqttProxyConnected {
			mqttManager.mqttClientProxy?.disconnect()
		}
		FROMRADIO_characteristic = nil
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
		stopScanning()
		startScanning()
	}

	// Called each time a peripheral is connected
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
			lastConnectionError = "🚫 [BLE] Bluetooth connection error, please try again."
			disconnectPeripheral()
			return
		}
		// Discover Services
		peripheral.discoverServices([meshtasticServiceCBUUID])
		Logger.services.info("✅ [BLE] Connected: \(peripheral.name ?? "Unknown", privacy: .public)")
	}

	// Called when a Peripheral fails to connect
	func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
		cancelPeripheralConnection()
		Logger.services.error("🚫 [BLE] Failed to Connect: \(peripheral.name ?? "Unknown", privacy: .public)")
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
				Logger.services.error("🚨 [BLE] Disconnected: \(peripheral.name ?? "Unknown", privacy: .public) Error Code: \(errorCode, privacy: .public) Error: \(e.localizedDescription, privacy: .public)")
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
							path: "meshtastic:///bluetooth"
						)
					]
					manager.schedule()
				}
				lastConnectionError = "🚨 \(e.localizedDescription)"
				Logger.services.error("🚨 [BLE] Disconnected: \(peripheral.name ?? "Unknown", privacy: .public) Error Code: \(errorCode, privacy: .public) Error: \(e.localizedDescription, privacy: .public)")
			} else if errorCode == 14 { // Peer removed pairing information
				// Forgetting and reconnecting seems to be necessary so we need to show the user an error telling them to do that
				lastConnectionError = "🚨 " + String.localizedStringWithFormat("ble.errorcode.14 %@".localized, e.localizedDescription)
				Logger.services.error("🚨 [BLE] Disconnected: \(peripheral.name ?? "Unknown") Error Code: \(errorCode, privacy: .public) Error: \(self.lastConnectionError, privacy: .public)")
			} else {
				if UserDefaults.preferredPeripheralId == peripheral.identifier.uuidString {
					manager.notifications = [
						Notification(
							id: (peripheral.identifier.uuidString),
							title: "Radio Disconnected",
							subtitle: "\(peripheral.name ?? "unknown".localized)",
							content: e.localizedDescription,
							target: "bluetooth",
							path: "meshtastic:///bluetooth"
						)
					]
					manager.schedule()
				}
				lastConnectionError = "🚨 \(e.localizedDescription)"
				Logger.services.error("🚨 [BLE] Disconnected: \(peripheral.name ?? "Unknown", privacy: .public) Error Code: \(errorCode, privacy: .public) Error: \(e.localizedDescription, privacy: .public)")
			}
		} else {
			// Disconnected without error which indicates user intent to disconnect
			// Happens when swiping to disconnect
			Logger.services.info("ℹ️ [BLE] Disconnected: \(peripheral.name ?? "Unknown", privacy: .public): User Initiated Disconnect")
		}
		// Start a scan so the disconnected peripheral is moved to the peripherals[] if it is awake
		self.startScanning()
	}

	// MARK: Peripheral Services functions
	func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
		if let error {
			Logger.services.error("🚫 [BLE] Discover Services error \(error.localizedDescription, privacy: .public)")
		}
		guard let services = peripheral.services else { return }
		for service in services where service.uuid == meshtasticServiceCBUUID {
			peripheral.discoverCharacteristics([TORADIO_UUID, FROMRADIO_UUID, FROMNUM_UUID, LEGACY_LOGRADIO_UUID, LOGRADIO_UUID], for: service)
			Logger.services.info("✅ [BLE] Service for Meshtastic discovered by \(peripheral.name ?? "Unknown", privacy: .public)")
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

			case TORADIO_UUID:
				Logger.services.info("✅ [BLE] did discover TORADIO characteristic for Meshtastic by \(peripheral.name ?? "Unknown", privacy: .public)")
				TORADIO_characteristic = characteristic

			case FROMRADIO_UUID:
				Logger.services.info("✅ [BLE] did discover FROMRADIO characteristic for Meshtastic by \(peripheral.name ?? "Unknown", privacy: .public)")
				FROMRADIO_characteristic = characteristic
				peripheral.readValue(for: FROMRADIO_characteristic)

			case FROMNUM_UUID:
				Logger.services.info("✅ [BLE] did discover FROMNUM (Notify) characteristic for Meshtastic by \(peripheral.name ?? "Unknown", privacy: .public)")
				FROMNUM_characteristic = characteristic
				peripheral.setNotifyValue(true, for: characteristic)

			case LEGACY_LOGRADIO_UUID:
				Logger.services.info("✅ [BLE] did discover legacy LOGRADIO (Notify) characteristic for Meshtastic by \(peripheral.name ?? "Unknown", privacy: .public)")
				LEGACY_LOGRADIO_characteristic = characteristic
				peripheral.setNotifyValue(true, for: characteristic)

			case LOGRADIO_UUID:
				Logger.services.info("✅ [BLE] did discover LOGRADIO (Notify) characteristic for Meshtastic by \(peripheral.name ?? "Unknown", privacy: .public)")
				LOGRADIO_characteristic = characteristic
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

	// MARK: MqttClientProxyManagerDelegate Methods
	func onMqttConnected() {
		mqttProxyConnected = true
		mqttError = ""
		Logger.services.info("📲 [MQTT Client Proxy] onMqttConnected now subscribing to \(self.mqttManager.topic, privacy: .public).")
		mqttManager.mqttClientProxy?.subscribe(mqttManager.topic)
	}

	func onMqttDisconnected() {
		mqttProxyConnected = false
		Logger.services.info("📲 MQTT Disconnected")
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
		guard let binaryData: Data = try? toRadio.serializedData() else {
			return
		}
		if connectedPeripheral?.peripheral.state ?? CBPeripheralState.disconnected == CBPeripheralState.connected {
			connectedPeripheral.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
		}
	}

	func onMqttError(message: String) {
		mqttProxyConnected = false
		mqttError = message
		Logger.services.info("📲 [MQTT Client Proxy] onMqttError: \(message, privacy: .public)")
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
		guard connectedPeripheral?.peripheral.state ?? CBPeripheralState.disconnected == CBPeripheralState.connected else { return success }

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
		if connectedPeripheral?.peripheral.state ?? CBPeripheralState.disconnected == CBPeripheralState.connected {
			connectedPeripheral.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
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
			guard let binaryData: Data = try? toRadio.serializedData() else {
				return
			}
			connectedPeripheral!.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
			// Either Read the config complete value or from num notify value
			guard connectedPeripheral != nil else { return }
			connectedPeripheral!.peripheral.readValue(for: FROMRADIO_characteristic)
		}
	}

	func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
		if let error {
			Logger.services.error("💥 [BLE] didUpdateNotificationStateFor error: \(characteristic.uuid, privacy: .public) \(error.localizedDescription, privacy: .public)")
		} else {
			Logger.services.info("ℹ️ [BLE] peripheral didUpdateNotificationStateFor \(characteristic.uuid, privacy: .public)")
		}
	}

	fileprivate func handleRadioLog(radioLog: String) {
		var log = radioLog
		/// Debug Log Level
		if log.starts(with: "DEBUG |") {
			do {
				let logString = log
				if let coordsMatch = try CommonRegex.COORDS_REGEX.firstMatch(in: logString) {
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
				if let coordsMatch = try CommonRegex.COORDS_REGEX.firstMatch(in: logString) {
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
		case LOGRADIO_UUID:
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

		case LEGACY_LOGRADIO_UUID:
			if characteristic.value == nil || characteristic.value!.isEmpty {
				return
			}
			if let log = String(data: characteristic.value!, encoding: .utf8) {
				handleRadioLog(radioLog: log)
			}

		case FROMRADIO_UUID:

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
				sendTime()
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

		case FROMNUM_UUID:
			Logger.services.info("🗞️ [BLE] (Notify) characteristic value will be read next")
		default:
			Logger.services.error("🚫 Unhandled Characteristic UUID: \(characteristic.uuid, privacy: .public)")
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
						if newMessage.toUser?.pkiEncrypted ?? false {
							newMessage.publicKey = newMessage.toUser?.publicKey
							newMessage.pkiEncrypted = true
						}
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
					if newMessage.toUser?.pkiEncrypted ?? false {
						meshPacket.pkiEncrypted = true
						meshPacket.publicKey = newMessage.toUser?.publicKey ?? Data()
					}
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
					if connectedPeripheral?.peripheral.state ?? CBPeripheralState.disconnected == CBPeripheralState.connected {
						connectedPeripheral.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
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

	public func sendWaypoint(waypoint: Waypoint) -> Bool {
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
		if connectedPeripheral?.peripheral.state ?? CBPeripheralState.disconnected == CBPeripheralState.connected {
			connectedPeripheral.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
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
	public func getPositionFromPhoneGPS(destNum: Int64, fixedPosition: Bool) -> Position? {
		var positionPacket = Position()
		if #available(iOS 17.0, macOS 14.0, *) {

			guard let lastLocation = LocationsHandler.shared.locationsArray.last else {
				return nil
			}

			if lastLocation == CLLocation(latitude: 0, longitude: 0) {
				return nil
			}

			positionPacket.latitudeI = Int32(lastLocation.coordinate.latitude * 1e7)
			positionPacket.longitudeI = Int32(lastLocation.coordinate.longitude * 1e7)
			let timestamp = lastLocation.timestamp
			positionPacket.time = UInt32(timestamp.timeIntervalSince1970)
			positionPacket.timestamp = UInt32(timestamp.timeIntervalSince1970)
			positionPacket.altitude = Int32(lastLocation.altitude)
			positionPacket.satsInView = UInt32(LocationsHandler.satsInView)
			let currentSpeed = lastLocation.speed
			if currentSpeed > 0 && (!currentSpeed.isNaN || !currentSpeed.isInfinite) {
				positionPacket.groundSpeed = UInt32(currentSpeed)
			}
			let currentHeading = lastLocation.course
			if (currentHeading > 0  && currentHeading <= 360) && (!currentHeading.isNaN || !currentHeading.isInfinite) {
				positionPacket.groundTrack = UInt32(currentHeading)
			}
			/// Set location source for time
			if !fixedPosition {
				/// From GPS treat time as good
				positionPacket.locationSource = Position.LocSource.locExternal
			} else {
				/// From GPS, but time can be old and have drifted
				positionPacket.locationSource = Position.LocSource.locManual
			}

		} else {

			positionPacket.latitudeI = Int32(LocationHelper.currentLocation.latitude * 1e7)
			positionPacket.longitudeI = Int32(LocationHelper.currentLocation.longitude * 1e7)
			let timestamp = LocationHelper.shared.locationManager.location?.timestamp ?? Date()
			positionPacket.time = UInt32(timestamp.timeIntervalSince1970)
			positionPacket.timestamp = UInt32(timestamp.timeIntervalSince1970)
			positionPacket.altitude = Int32(LocationHelper.shared.locationManager.location?.altitude ?? 0)
			positionPacket.satsInView = UInt32(LocationHelper.satsInView)
			let currentSpeed = LocationHelper.shared.locationManager.location?.speed ?? 0
			if currentSpeed > 0 && (!currentSpeed.isNaN || !currentSpeed.isInfinite) {
				positionPacket.groundSpeed = UInt32(currentSpeed)
			}
			let currentHeading  = LocationHelper.shared.locationManager.location?.course ?? 0
			if (currentHeading > 0  && currentHeading <= 360) && (!currentHeading.isNaN || !currentHeading.isInfinite) {
				positionPacket.groundTrack = UInt32(currentHeading)
			}
			/// Set location source for time
			if !fixedPosition {
				/// From GPS treat time as good
				positionPacket.locationSource = Position.LocSource.locExternal
			} else {
				/// From GPS, but time can be old and have drifted
				positionPacket.locationSource = Position.LocSource.locManual
			}
		}
		return positionPacket
	}

	@MainActor
	public func setFixedPosition(fromUser: UserEntity, channel: Int32) -> Bool {
		var adminPacket = AdminMessage()
		guard let positionPacket = getPositionFromPhoneGPS(destNum: fromUser.num, fixedPosition: true) else {
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
	public func sendPosition(channel: Int32, destNum: Int64, wantResponse: Bool) -> Bool {
		let fromNodeNum = connectedPeripheral.num
		guard let positionPacket = getPositionFromPhoneGPS(destNum: destNum, fixedPosition: false) else {
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
		if connectedPeripheral?.peripheral.state ?? CBPeripheralState.disconnected == CBPeripheralState.connected {
			connectedPeripheral.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
			let logString = String.localizedStringWithFormat("mesh.log.sharelocation %@".localized, String(fromNodeNum))
			Logger.services.debug("📍 \(logString)")
			return true
		} else {
			Logger.services.error("Device no longer connected. Unable to send position information.")
			return false
		}
	}

	@MainActor
	@objc func positionTimerFired(timer: Timer) {
		// Check for connected node
		if connectedPeripheral != nil {
			// Send a position out to the mesh if "share location with the mesh" is enabled in settings
			if UserDefaults.provideLocation {
				_ = sendPosition(channel: 0, destNum: connectedPeripheral.num, wantResponse: false)
			}
		}
	}

	public func sendTime() -> Bool {
		var adminPacket = AdminMessage()
		adminPacket.setTimeOnly = UInt32(Date().timeIntervalSince1970)
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(self.connectedPeripheral.num)
		meshPacket.from = UInt32(self.connectedPeripheral.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = true
		meshPacket.channel = 0
		var dataMessage = DataMessage()
		if let serializedData: Data = try? adminPacket.serializedData() {
			dataMessage.payload = serializedData
			dataMessage.portnum = PortNum.adminApp
			meshPacket.decoded = dataMessage
		} else {
			return false
		}
		let messageDescription = "🕛 Sent Set Time Admin Message to the connectecd node."
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			return true
		}
		return false
	}

	public func sendShutdown(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		var adminPacket = AdminMessage()
		adminPacket.shutdownSeconds = 5
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
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

	public func sendReboot(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		var adminPacket = AdminMessage()
		adminPacket.rebootSeconds = 5
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
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

	public func sendRebootOta(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {
		var adminPacket = AdminMessage()
		adminPacket.rebootOtaSeconds = 5
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
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

	public func sendEnterDfuMode(fromUser: UserEntity, toUser: UserEntity) -> Bool {
		var adminPacket = AdminMessage()
		adminPacket.enterDfuModeRequest = true
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
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

	public func sendFactoryReset(fromUser: UserEntity, toUser: UserEntity) -> Bool {
		var adminPacket = AdminMessage()
		adminPacket.factoryResetConfig = 5
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
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

	public func sendNodeDBReset(fromUser: UserEntity, toUser: UserEntity) -> Bool {
		var adminPacket = AdminMessage()
		adminPacket.nodedbReset = 5
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
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
	public func saveChannel(channel: Channel, fromUser: UserEntity, toUser: UserEntity) -> Int64 {

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

	public func saveChannelSet(base64UrlString: String, addChannels: Bool = false) -> Bool {
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
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
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

	public func removeNode(node: NodeInfoEntity, connectedNodeNum: Int64) -> Bool {
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

		if connectedPeripheral?.peripheral.state ?? CBPeripheralState.disconnected == CBPeripheralState.connected {
			do {
				connectedPeripheral.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
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

	public func setFavoriteNode(node: NodeInfoEntity, connectedNodeNum: Int64) -> Bool {
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

		if connectedPeripheral?.peripheral.state ?? CBPeripheralState.disconnected == CBPeripheralState.connected {
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

		if connectedPeripheral?.peripheral.state ?? CBPeripheralState.disconnected == CBPeripheralState.connected {
			connectedPeripheral.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
			return true
		}
		return false
	}

	public func saveLicensedUser(ham: HamParameters, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		var adminPacket = AdminMessage()
		adminPacket.setHamMode = ham
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
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
	public func saveBluetoothConfig(config: Config.BluetoothConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		var adminPacket = AdminMessage()
		adminPacket.setConfig.bluetooth = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
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
			upsertBluetoothConfigPacket(config: config, nodeNum: toUser.num, sessionPasskey: toUser.userNode?.sessionPasskey, context: context)
			return Int64(meshPacket.id)
		}

		return 0
	}

	public func saveDeviceConfig(config: Config.DeviceConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setConfig.device = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
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
			upsertDeviceConfigPacket(config: config, nodeNum: toUser.num, sessionPasskey: toUser.userNode?.sessionPasskey, context: context)
			return Int64(meshPacket.id)
		}
		return 0
	}

	public func saveDisplayConfig(config: Config.DisplayConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {
		var adminPacket = AdminMessage()
		adminPacket.setConfig.display = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
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
			upsertDisplayConfigPacket(config: config, nodeNum: toUser.num, sessionPasskey: toUser.userNode?.sessionPasskey, context: context)
			return Int64(meshPacket.id)
		}
		return 0
	}

	public func saveLoRaConfig(config: Config.LoRaConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setConfig.lora = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
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
			upsertLoRaConfigPacket(config: config, nodeNum: toUser.num, sessionPasskey: toUser.userNode?.sessionPasskey, context: context)
			return Int64(meshPacket.id)
		}

		return 0
	}

	public func savePositionConfig(config: Config.PositionConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setConfig.position = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
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

	public func saveNetworkConfig(config: Config.NetworkConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setConfig.network = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
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

	public func saveSecurityConfig(config: Config.SecurityConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setConfig.security = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
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

		let messageDescription = "🛟 Saved Security Config for \(toUser.longName ?? "unknown".localized)"

		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
			upsertSecurityConfigPacket(config: config, nodeNum: toUser.num, context: context)
			return Int64(meshPacket.id)
		}

		return 0
	}

	public func saveAmbientLightingModuleConfig(config: ModuleConfig.AmbientLightingConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.ambientLighting = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
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

	public func saveCannedMessageModuleConfig(config: ModuleConfig.CannedMessageConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.cannedMessage = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
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

	public func saveCannedMessageModuleMessages(messages: String, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setCannedMessageModuleMessages = messages
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
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

	public func saveDetectionSensorModuleConfig(config: ModuleConfig.DetectionSensorConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.detectionSensor = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
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

	public func saveExternalNotificationModuleConfig(config: ModuleConfig.ExternalNotificationConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.externalNotification = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
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

	public func savePaxcounterModuleConfig(config: ModuleConfig.PaxcounterConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.paxcounter = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
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

	public func saveRtttlConfig(ringtone: String, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setRingtoneMessage = ringtone
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
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

	public func saveMQTTConfig(config: ModuleConfig.MQTTConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.mqtt = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
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

	public func saveRangeTestModuleConfig(config: ModuleConfig.RangeTestConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.rangeTest = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
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

	public func saveSerialModuleConfig(config: ModuleConfig.SerialConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.serial = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
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

	public func saveStoreForwardModuleConfig(config: ModuleConfig.StoreForwardConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.storeForward = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
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

	public func saveTelemetryModuleConfig(config: ModuleConfig.TelemetryConfig, fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Int64 {

		var adminPacket = AdminMessage()
		adminPacket.setModuleConfig.telemetry = config
		if fromUser != toUser {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
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
		if UserDefaults.enableAdministration {
			adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
		}
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

	public func requestSecurityConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {

		var adminPacket = AdminMessage()
		adminPacket.getConfigRequest = AdminMessage.ConfigType.securityConfig
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

		let messageDescription = "🛎️ Requested Security Config on admin channel \(adminIndex) for node: \(toUser.longName ?? "unknown".localized)"
		if sendAdminMessageToRadio(meshPacket: meshPacket, adminDescription: messageDescription) {
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

	public func requestTelemetryModuleConfig(fromUser: UserEntity, toUser: UserEntity, adminIndex: Int32) -> Bool {

		var adminPacket = AdminMessage()
		adminPacket.getModuleConfigRequest = AdminMessage.ModuleConfigType.telemetryConfig
		adminPacket.sessionPasskey = toUser.userNode?.sessionPasskey ?? Data()
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

		if connectedPeripheral?.peripheral.state ?? CBPeripheralState.disconnected == CBPeripheralState.connected {
			connectedPeripheral.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
			Logger.mesh.debug("\(adminDescription)")
			return true
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
		if connectedPeripheral?.peripheral.state ?? CBPeripheralState.disconnected == CBPeripheralState.connected {
			connectedPeripheral.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
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

	public func tryClearExistingChannels() {
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

// MARK: - CB Central Manager implmentation
extension BLEManager: CBCentralManagerDelegate {

	// MARK: Bluetooth enabled/disabled
	func centralManagerDidUpdateState(_ central: CBCentralManager) {
		if central.state == CBManagerState.poweredOn {
			Logger.services.info("✅ [BLE] powered on")
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
		Logger.services.info("📜 [BLE] Bluetooth status: \(status)")
	}

	// Called each time a peripheral is discovered
	func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {

		if self.automaticallyReconnect && peripheral.identifier.uuidString == UserDefaults.standard.object(forKey: "preferredPeripheralId") as? String ?? "" {
			self.connectTo(peripheral: peripheral)
			Logger.services.info("✅ [BLE] Reconnecting to prefered peripheral: \(peripheral.name ?? "Unknown", privacy: .public)")
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
