//
//  ESP32BLEOTAViewModel.swift (previously BLEConnection.swift in the DFU app)
//
//  Created by Garth Vander Houwen on 12/4/22
//

import CoreBluetooth
import OSLog

private let meshtasticOTAServiceId = CBUUID(string: "4FAFC201-1FB5-459E-8FCC-C5C9C331914B")
private let statusCharacteristicId = CBUUID(string: "62EC0272-3EC5-11EB-B378-0242AC130003") // ESP32 pTxCharacteristic ESP send (notifying)
private let otaCharacteristicId = CBUUID(string: "62EC0272-3EC5-11EB-B378-0242AC130005") // ESP32 pOtaCharacteristic  ESP write

private let outOfRangeHeuristics: Set<CBError.Code> = [.unknown, .connectionTimeout, .peripheralDisconnected, .connectionFailed]

class ESP32BLEOTAViewModel: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
	
	var manager: CBCentralManager!
	var statusCharacteristic: CBCharacteristic?
	var otaCharacteristic: CBCharacteristic?
	
	var otaCharacteristicIsNotifying =  false
	var statusCharacteristicIsNotifying = false
	
	var state = StateBLE.poweredOff
	
	enum StateBLE {
		case poweredOff
		case restoringConnectingPeripheral(CBPeripheral)
		case restoringConnectedPeripheral(CBPeripheral)
		case disconnected
		case scanning
		case connecting(CBPeripheral, Countdown)
		case discoveringServices(CBPeripheral, Countdown)
		case discoveringCharacteristics(CBPeripheral, Countdown)
		case connected(CBPeripheral)
		case outOfRange(CBPeripheral)
		
		var peripheral: CBPeripheral? {
			switch self {
			case .poweredOff: return nil
			case .restoringConnectingPeripheral(let p): return p
			case .restoringConnectedPeripheral(let p): return p
			case .disconnected: return nil
			case .scanning: return nil
			case .connecting(let p, _): return p
			case .discoveringServices(let p, _): return p
			case .discoveringCharacteristics(let p, _): return p
			case .connected(let p): return p
			case .outOfRange(let p): return p
			}
		}
	}
	
	// Used by contentView.swift
	@Published var name = ""
	@Published var connected = false
	@Published var transferProgress : Double = 0.0
	@Published var chunkCount = 1 // number of chunks to be sent before peripheral needs to accknowledge.
	@Published var elapsedTime = 0.0
	@Published var kBPerSecond = 0.0

	// OTA file URL
	var fileUrl: URL?
	var desiredPeripheral: CBPeripheral?
	
	// transfer varibles
	var dataToSend = Data()
	var dataBuffer = Data()
	var chunkSize = 0
	var dataLength = 0
	var transferOngoing = true
	var sentBytes = 0
	var packageCounter = 0
	var startTime = 0.0
	var stopTime = 0.0
	var firstAcknowledgeFromESP32 = false
	
	// Initiate CentralManager
	override init() {
		super.init()
		manager = CBCentralManager(delegate: self, queue: .none)
		manager.delegate = self
	}
	
	func startOTA(peripheral: CBPeripheral, binFileURL: URL) {
		self.desiredPeripheral = peripheral
		self.fileUrl = binFileURL
		
		self.startScanning()
	}
	
	// CentralManager State updates
	func centralManagerDidUpdateState(_ central: CBCentralManager) {
		Logger.services.info("Bluetooth State Updated")
		switch manager.state {
		case .unknown:
			Logger.services.info("Unknown")
		case .resetting:
			Logger.services.info("Resetting")
		case .unsupported:
			Logger.services.info("Unsupported")
		case .unauthorized:
			Logger.services.info("Bluetooth is disabled")
		case .poweredOff:
			Logger.services.info("Bluetooth is powered off")
		case .poweredOn:
			Logger.services.info("Bluetooth is working properly")
		@unknown default:
			Logger.services.info("fatal error")
		}
	}
	
	// Discovery (scanning) and handling of BLE devices in range
	func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
		guard case .scanning = state else { return }
		
		self.name = peripheral.name ?? "Unknown"
		Logger.services.info("Discovered \(self.name)")
		
		// Check if this is the desired peripheral
		if let desiredPeripheral, desiredPeripheral.identifier != peripheral.identifier {
			Logger.services.info("This peripheral is not the one we're looking for")
		}
		
		manager.stopScan()
		connect(peripheral: peripheral)
	}
	
	// Connection established handler
	func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
		Logger.services.info("Connection suceeded")
		
		transferOngoing = false
		
		// Clear the data that we may already have
		dataToSend.removeAll(keepingCapacity: false)
		
		// Make sure we get the discovery callbacks
		peripheral.delegate = self
		
		if peripheral.statusCharacteristic == nil {
			discoverServices(peripheral: peripheral)
		} else {
			setConnected(peripheral: peripheral)
		}
	}
	
	// Connection failed
	func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
		Logger.services.info("\(Date()) CM DidFailToConnect")
		state = .disconnected
	}
	
	func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
		transferOngoing = false
		Logger.services.info("\(peripheral.name ?? "unknown") disconnected")
		// Did our currently-connected peripheral just disconnect?
		if state.peripheral?.identifier == peripheral.identifier {
			name = ""
			connected = false
			// IME the error codes encountered are:
			// 0 = rebooting the peripheral.
			// 6 = out of range.
			if let error = error, (error as NSError).domain == CBErrorDomain,
			   let code = CBError.Code(rawValue: (error as NSError).code),
			   outOfRangeHeuristics.contains(code) {
				// Try reconnect without setting a timeout in the state machine.
				// With CB, it's like saying 'please reconnect me at any point
				// in the future if this peripheral comes back into range'.
				Logger.services.info("Connection failure, try and reconnect when the device is back in range")
				manager.connect(peripheral, options: nil)
				state = .outOfRange(peripheral)
			} else {
				// Likely a deliberate unpairing.
				state = .disconnected
			}
		}
	}
	
	// -----------------------------------------
	// Peripheral callbacks
	// -----------------------------------------
	
	// Discover BLE device service(s)
	func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
		Logger.services.info("Discovered Bluetooth Services")
		// Ignore services discovered late.
		guard case .discoveringServices = state else {
			return
		}
		if let error = error {
			Logger.services.error("\(error.localizedDescription)")
			disconnect()
			return
		}
		guard peripheral.meshtasticOTAService != nil else {
			Logger.services.info("Meshtastic OTA service missing")
			disconnect()
			return
		}
		// All fine so far, go to next step
		guard let services = peripheral.services else { return }
		for service in services {
			peripheral.discoverCharacteristics(nil, for: service)
		}
		
	}
	// Discover BLE device Service charachteristics
	func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
		Logger.services.info("Discovering Characteristics For Meshtastic OTA Service")
		
		if let error = error {
			Logger.services.error("\(error.localizedDescription)")
			disconnect()
			return
		}
		
		guard peripheral.statusCharacteristic != nil else {
			Logger.services.info("\(Date()) Desired characteristic missing")
			disconnect()
			return
		}
		
		guard let characteristics = service.characteristics else {
			return
		}
		
		for characteristic in characteristics {
			switch characteristic.uuid {
				
			case statusCharacteristicId:
				statusCharacteristic = characteristic
				Logger.services.info("Discovered Status Characteristic: \(self.statusCharacteristic!.uuid.uuidString)")
				peripheral.setNotifyValue(true, for: characteristic)
				
			case otaCharacteristicId:
				otaCharacteristic = characteristic
				Logger.services.info("Discovered OTA Characteristic: \(self.otaCharacteristic!.uuid.uuidString)")
				peripheral.setNotifyValue(false, for: characteristic)
				
			default:
				Logger.services.info("\(Date()) unknown")
			}
		}
		setConnected(peripheral: peripheral)
	}
	// The BLE peripheral device sent some notify data. Deal with it!
	func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
		Logger.services.info("\(Date()) PH didUpdateValueFor")
		if let error = error {
			Logger.services.error("\(error.localizedDescription)")
			return
		}
		if let data = characteristic.value {
			// deal with incoming data
			// First check if the incoming data is one byte length?
			// if so it's the peripheral acknowledging and telling
			// us to send another batch of data
			if data.count == 1 {
				if !firstAcknowledgeFromESP32 {
					firstAcknowledgeFromESP32 = true
					startTime = CFAbsoluteTimeGetCurrent()
				}
				// Logger.services.info("\(Date()) -X-")
				if transferOngoing {
					packageCounter = 0
					writeDataToPeripheral(characteristic: otaCharacteristic!)
				}
			}
		}
	}
	
	// Called when .withResponse is used.
	func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: Error?) {
		Logger.services.info("\(Date()) PH didWriteValueFor")
		if let error = error {
			Logger.services.error("\(Date()) Error writing to characteristic: \(error.localizedDescription)")
			return
		}
	}
	
	// Callback indicating peripheral notifying state
	func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
		Logger.services.info("\(Date()) PH didUpdateNotificationStateFor")
		Logger.services.info("\(Date()) PH characteristic: \(characteristic.uuid.uuidString)")
		if error == nil {
			Logger.services.info("\(Date()) Notification Set OK, isNotifying: \(characteristic.isNotifying)")
			if !characteristic.isNotifying {
				Logger.services.info("\(Date()) isNotifying is false, set to true again!")
				peripheral.setNotifyValue(true, for: characteristic)
			} else {
				if characteristic.uuid == statusCharacteristic?.uuid {
					statusCharacteristicIsNotifying = true
				}
			}
		}
		
		checkStartTransfer()
	}
	
	func checkStartTransfer() {
		guard connected else {
			Logger.services.info("Not connected, cannot start transfer")
			return
		}
		guard statusCharacteristicIsNotifying else {
			Logger.services.info("Status Characteristic not notifying yet, cannot start transfer")
			return
		}
		guard transferOngoing == false else {
			Logger.services.info("Transfer already ongoing")
			return
		}
			
		// All set, start the transfer
		self.sendFile()
	}
		
	/*-------------------------------------------------------------------------
	 Functions
	 -------------------------------------------------------------------------*/
	// Scan for a device with the OTA Service UUID (myDesiredServiceId)
	func startScanning() {
		Logger.services.info("Scanning for Meshtastic Devices in OTA Mode")
		guard manager.state == .poweredOn else {
			Logger.services.info("Cannot scan, Bluetooth is not powered on")
			return
		}
		manager.scanForPeripherals(withServices: [meshtasticOTAServiceId], options: nil)
//		state = .scanning(Countdown(seconds: 10, closure: {
//			self.manager.stopScan()
//			self.state = .disconnected
//			Logger.services.info("Scan timed out")
//		}))
		state = .scanning
	}
	
	func disconnect() {
		Logger.services.info("Disconnect")
		if let peripheral = state.peripheral {
			manager.cancelPeripheralConnection(peripheral)
		}
		state = .disconnected
		connected = false
		transferOngoing = false
	}
	
	// Connect to the device from the scanning
	func connect(peripheral: CBPeripheral) {
		Logger.services.info("Connect Button Pushed")
		if connected {
			manager.cancelPeripheralConnection(peripheral)
		} else {
			// Connect!
			manager.connect(peripheral, options: nil)
			name = String(peripheral.name ?? "unknown")
			Logger.services.info("Attempting connection to \(self.name)")
			state = .connecting(peripheral, Countdown(seconds: 10, closure: {
				self.manager.cancelPeripheralConnection(self.state.peripheral!)
				self.state = .disconnected
				self.connected = false
				Logger.services.info("Attempted connection to \(self.name) timed out")
			}))
		}
	}
	
	// Discover Services of a device
	func discoverServices(peripheral: CBPeripheral) {
		Logger.services.info("Discovering Meshtastic OTA service")
		peripheral.delegate = self
		peripheral.discoverServices([meshtasticOTAServiceId])
		state = .discoveringServices(peripheral, Countdown(seconds: 10, closure: {
			self.disconnect()
			Logger.services.info("\(Date()) Could not discover services")
		}))
	}
	
	// Discover Characteristics of a Services
	func discoverCharacteristics(peripheral: CBPeripheral) {
		Logger.services.info("Discovering characteristics for Meshtastic OTA service")
		guard let meshtasticOTAService = peripheral.meshtasticOTAService else {
			self.disconnect()
			return
		}
		peripheral.discoverCharacteristics([statusCharacteristicId], for: meshtasticOTAService)
		state = .discoveringCharacteristics(peripheral,
											Countdown(seconds: 10,
													  closure: {
			self.disconnect()
			Logger.services.info("\(Date()) Could not discover characteristics")
		}))
	}
	
	func setConnected(peripheral: CBPeripheral) {
		Logger.services.info("Max write value with response: \(peripheral.maximumWriteValueLength(for: .withResponse))")
		Logger.services.info("Max write value without response: \(peripheral.maximumWriteValueLength(for: .withoutResponse))")
		guard let statusCharacteristic = peripheral.statusCharacteristic
		else {
			Logger.services.info("Missing status characteristic")
			disconnect()
			return
		}
		
		peripheral.setNotifyValue(true, for: statusCharacteristic)
		state = .connected(peripheral)
		connected = true
		name = String(peripheral.name ?? "unknown")

		checkStartTransfer()
	}
	
	// Peripheral callback when its ready to receive more data without response
	func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
		if transferOngoing && packageCounter < chunkCount {
			writeDataToPeripheral(characteristic: otaCharacteristic!)
		}
	}
	
	func sendFile() {
		Logger.services.info("Start sending .bin file to device")
		
		// 1. Get the data from the file(name) and copy data to dataBUffer
		guard let fileUrl, let data: Data = try? Data(contentsOf: fileUrl) else {
			Logger.services.info("Failed to open .bin file")
			return
		}
		dataBuffer = data
		dataLength = dataBuffer.count
		
		// 1. Get the peripheral and its transfer characteristic
		guard let discoveredPeripheral = state.peripheral else { return }
		// Send dataLength to the device
		let sizeMessage = "OTA_SIZE:\(dataLength)"
		if let sizeData = sizeMessage.data(using: .utf8) {
			// Send sizeData to the peripheral
			// Assuming writeCharacteristic is the characteristic for sending messages
			discoveredPeripheral.writeValue(sizeData, for: otaCharacteristic!, type: .withoutResponse)
			Logger.services.info("Sent OTA size message: \(sizeMessage)")
		} else {
			Logger.services.info("Failed to encode OTA size message")
			return
		}
		
		// Logger.services.info the total size of the data in hexadecimal format
		Logger.services.info("Total data size (hexadecimal): \(String(format: "%02X", self.dataBuffer.count))")
		transferOngoing = true
		
		packageCounter = 0
		// Send the first chunk
		elapsedTime = 0.0
		sentBytes = 0
		firstAcknowledgeFromESP32 = false
		startTime = CFAbsoluteTimeGetCurrent()
		writeDataToPeripheral(characteristic: otaCharacteristic!)
	}
	
	func writeDataToPeripheral(characteristic: CBCharacteristic) {
		// 1. Get the peripheral and its transfer characteristic
		guard let discoveredPeripheral = state.peripheral else { return }
		// ATT MTU - 3 bytes
		let maxWriteValueLength = discoveredPeripheral.maximumWriteValueLength(for: .withoutResponse)
		chunkSize = maxWriteValueLength - 3
		Logger.services.info("Chunk size: \(self.chunkSize), 0x\(String(format: "%02X", self.chunkSize))")
		// Get the data range
		var range: Range<Data.Index>
		
		// 2. Loop through and send each chunk to the BLE device
		// check to see if the number of iterations completed and the peripheral can accept more data
		// package counter allows only "chunkCount" of data to be sent per time.
		while transferOngoing && packageCounter < chunkCount {
			// 3. Create a range based on the length of data to return
			range = (0..<min(chunkSize, dataBuffer.count))
			// 4. Get a subcopy copy of data
			let subData = dataBuffer.subdata(in: range)
			// Logger.services.info the first byte of the subData package as hexadecimal
			if let firstByte = subData.first {
				Logger.services.info("First byte of subData package: \(String(format: "%02X", firstByte))")
			}
			// 5. Send data chunk to BLE peripheral, send EOF when buffer is empty.
			if !dataBuffer.isEmpty {
				discoveredPeripheral.writeValue(subData, for: characteristic, type: .withoutResponse)
				packageCounter += 1
				// Logger.services.info(" Packages: \(packageCounter) bytes: \(subData.count)")
			} else {
				transferOngoing = false
			}
			
			if discoveredPeripheral.canSendWriteWithoutResponse {
				Logger.services.info("BLE peripheral ready?: \(discoveredPeripheral.canSendWriteWithoutResponse)")
			}
			
			// 6. Remove already sent data from buffer
			dataBuffer.removeSubrange(range)
			
			// 7. calculate and Logger.services.info the transfer progress in %
			transferProgress = (1 - (Double(dataBuffer.count) / Double(dataLength))) * 100
			Logger.services.info("File transfer progress: \(String(format: "%.02f", self.transferProgress))%")
			sentBytes += chunkSize
			elapsedTime = CFAbsoluteTimeGetCurrent() - startTime
			let kbPs = Double(sentBytes) / elapsedTime
			kBPerSecond = kbPs / 1000
		}
	}
}

extension CBPeripheral {
	// Helper to find the service we're interested in.
	var meshtasticOTAService: CBService? {
		guard let services = services else { return nil }
		return services.first { $0.uuid == meshtasticOTAServiceId }
	}
	// Helper to find the characteristic we're interested in.
	var statusCharacteristic: CBCharacteristic? {
		guard let characteristics = meshtasticOTAService?.characteristics else {
			return nil
		}
		return characteristics.first { $0.uuid == statusCharacteristicId }
	}
}

class Countdown {
	let timer: Timer
	init(seconds: TimeInterval, closure: @escaping () -> Void) {
		timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false, block: { _ in closure() })
	}
	deinit {
		timer.invalidate()
	}
}
