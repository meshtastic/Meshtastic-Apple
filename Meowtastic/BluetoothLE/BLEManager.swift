import CocoaMQTT
import CoreBluetooth
import CoreData
import FirebaseAnalytics
import Foundation
import MapKit
import MeshtasticProtobufs
import OSLog
import SwiftUI

// swiftlint:disable file_length
final class BLEManager: NSObject, ObservableObject {
	let appState: AppState
	let context: NSManagedObjectContext
	let privateContext: NSManagedObjectContext
	let centralManager: CBCentralManager
	let coreDataTools = CoreDataTools()
	let minimumVersion = "2.0.0"
	let debounce = Debounce<() async -> Void>(duration: .milliseconds(33)) { action in
		await action()
	}

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
	var mqttConnected = false
	@Published
	var mqttError = ""

	var devicesDelegate: DevicesDelegate?
	var mqttManager: MQTTManager?
	var connectedVersion: String
	var isConnecting = false
	var isConnected = false
	var isSubscribed = false
	var timeoutTimer: Timer?
	var timeoutCount = 0
	var positionTimer: Timer?
	var wantRangeTestPackets = false
	var wantStoreAndForwardPackets = false
	var lastConfigNonce = UInt32.min
	var characteristicToRadio: CBCharacteristic?
	var characteristicFromRadio: CBCharacteristic?
	var characteristicFromNum: CBCharacteristic?
	var characteristicLogRadio: CBCharacteristic?
	var characteristicLogRadioLegacy: CBCharacteristic?

	init(
		appState: AppState,
		context: NSManagedObjectContext
	) {
		self.appState = appState
		self.context = context
		self.privateContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
		self.centralManager = CBCentralManager()
		self.mqttManager = MQTTManager()

		self.lastConnectionError = ""
		self.connectedVersion = "0.0.0"

		super.init()

		centralManager.delegate = self
	}

	func connectMQTT(config: MQTTConfigEntity) {
		guard config.enabled else {
			return
		}

		let manager = MQTTManager()
		manager.delegate = self
		manager.connect(config: config)

		mqttManager = manager
	}

	func disconnectMQTT() {
		mqttManager?.disconnect()
		mqttManager?.delegate = nil
		mqttManager = nil
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

	func setIsInvalidFwVersion() {
		isInvalidFwVersion = true
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

		Analytics.logEvent(AnalyticEvents.bleConnect.id, parameters: nil)
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
		}
		else if deviceConnected != nil, isSubscribed {
			return true
		}

		return false
	}

	func cancelPeripheralConnection() {
		if let mqttClientProxy = mqttManager?.client, mqttConnected {
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

		Analytics.logEvent(AnalyticEvents.bleCancelConnecting.id, parameters: nil)

		stopScanning()
		startScanning()
	}

	func disconnectDevice(reconnect: Bool = true) {
		guard let deviceConnected else {
			return
		}

		if let mqttClientProxy = mqttManager?.client, mqttConnected {
			mqttClientProxy.disconnect()
		}

		automaticallyReconnect = reconnect
		centralManager.cancelPeripheralConnection(deviceConnected.peripheral)
		characteristicFromRadio = nil
		isConnected = false
		isSubscribed = false
		isInvalidFwVersion = false
		connectedVersion = "0.0.0"

		Analytics.logEvent(AnalyticEvents.bleDisconnect.id, parameters: nil)

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

			Analytics.logEvent(AnalyticEvents.bleTraceRoute.id, parameters: nil)

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

			// swiftlint:disable:next force_unwrapping
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

			debounce.emit { [weak self] in
				await self?.saveData()
			}

			return true
		}

		return false
	}

	func sendMessage(
		message: String,
		toUserNum: Int64,
		channel: Int32,
		isEmoji: Bool,
		replyID: Int64
	) -> Bool {
		guard
			let connectedDevice = getConnectedDevice(),
			!message.isEmpty
		else {
			AnalyticEvents.trackBLEEvent(for: .message, status: .failureProcess)
			return false
		}

		let fromUserNum: Int64 = connectedDevice.num
		let messageUsers = UserEntity.fetchRequest()
		messageUsers.predicate = NSPredicate(format: "num IN %@", [fromUserNum, Int64(toUserNum)])

		guard
			let fetchedUsers = try? context.fetch(messageUsers),
			!fetchedUsers.isEmpty
		else {
			AnalyticEvents.trackBLEEvent(for: .message, status: .failureProcess)
			return false
		}

		let newMessage = MessageEntity(context: context)
		newMessage.messageId = Int64(UInt32.random(in: UInt32(UInt8.max)..<UInt32.max))
		newMessage.messageTimestamp = Int32(Date.now.timeIntervalSince1970)
		newMessage.receivedACK = false
		newMessage.read = true
		if toUserNum > 0 {
			newMessage.toUser = fetchedUsers.first(where: {
				$0.num == toUserNum
			})
			newMessage.toUser?.lastMessage = Date()
		}
		newMessage.fromUser = fetchedUsers.first(where: {
			$0.num == fromUserNum
		})
		newMessage.isEmoji = isEmoji
		newMessage.admin = false
		newMessage.channel = channel
		if replyID > 0 {
			newMessage.replyID = replyID
		}
		newMessage.messagePayload = message
		newMessage.messagePayloadMarkdown = generateMessageMarkdown(message: message)
		newMessage.read = true

		var dataMessage = DataMessage()
		dataMessage.portnum = PortNum.textMessageApp
		dataMessage.payload = message
			.replacingOccurrences(of: "’", with: "'")
			.replacingOccurrences(of: "”", with: "\"")
			.data(using: String.Encoding.utf8)!

		var meshPacket = MeshPacket()
		meshPacket.id = UInt32(newMessage.messageId)
		if toUserNum > 0 {
			meshPacket.to = UInt32(toUserNum)
		}
		else {
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
			AnalyticEvents.trackBLEEvent(for: .message, status: .failureProcess)
			return false
		}

		connectedDevice.peripheral.writeValue(
			binaryData,
			for: characteristicToRadio,
			type: .withResponse
		)

		debounce.emit { [weak self] in
			if let status = await self?.saveData(), status{
				AnalyticEvents.trackBLEEvent(for: .message, status: .success)
			}
			else {
				AnalyticEvents.trackBLEEvent(for: .message, status: .failureSend)
			}
		}

		return true
	}

	@discardableResult
	func sendPosition(channel: Int32, destNum: Int64, wantResponse: Bool) -> Bool {
		guard
			let connectedDevice = getConnectedDevice(),
			let positionPacket = getPhonePosition()
		else {
			AnalyticEvents.trackBLEEvent(for: .position, status: .failureProcess)
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
		}
		else {
			AnalyticEvents.trackBLEEvent(for: .position, status: .failureProcess)
			return false
		}

		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket

		guard let binaryData: Data = try? toRadio.serializedData() else {
			AnalyticEvents.trackBLEEvent(for: .position, status: .failureProcess)
			return false
		}

		connectedDevice.peripheral.writeValue(
			binaryData,
			for: characteristicToRadio,
			type: .withResponse
		)

		AnalyticEvents.trackBLEEvent(for: .position, status: .success)

		return true
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
	func saveData() async -> Bool {
		privateContext.performAndWait { [weak self] in
			guard
				let self,
				privateContext.hasChanges
			else {
				return false
			}

			do {
				try privateContext.save()

				return true
			}
			catch let error {
				privateContext.rollback()

				Logger.app.debug("context save failed misrably: \(error.localizedDescription)")

				return false
			}
		}
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

			Analytics.logEvent(AnalyticEvents.bleTimeout.id, parameters: nil)

			startScanning()
		}
	}
}
// swiftlint:enable file_length
