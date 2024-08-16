import CoreBluetooth
import OSLog

extension BLEManager: CBCentralManagerDelegate {
	// MARK: Bluetooth enabled/disabled
	func centralManagerDidUpdateState(
		_ central: CBCentralManager
	) {
		if central.state == CBManagerState.poweredOn {
			Logger.services.info("✅ [BLE] powered on")
			isSwitchedOn = true
			startScanning()
		}
		else {
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
	func centralManager(
		_ central: CBCentralManager,
		didDiscover peripheral: CBPeripheral,
		advertisementData: [String: Any],
		rssi RSSI: NSNumber
	) {
		if self.automaticallyReconnect && peripheral.identifier.uuidString == UserDefaults.standard.object(forKey: "preferredPeripheralId") as? String ?? "" {
			self.connectTo(peripheral: peripheral)
			Logger.services.info("✅ [BLE] Reconnecting to prefered peripheral: \(peripheral.name ?? "Unknown", privacy: .public)")
		}
		let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String
		let device = Peripheral(id: peripheral.identifier.uuidString, num: 0, name: name ?? "Unknown", shortName: "?", longName: name ?? "Unknown", firmwareVersion: "Unknown", rssi: RSSI.intValue, lastUpdate: Date(), peripheral: peripheral)
		let index = peripherals.map { $0.peripheral }.firstIndex(of: peripheral)
		
		if let peripheralIndex = index {
			peripherals[peripheralIndex] = device
		}
		else {
			peripherals.append(device)
		}
		let today = Date()
		let visibleDuration = Calendar.current.date(byAdding: .second, value: -5, to: today)!
		self.peripherals.removeAll(where: { $0.lastUpdate < visibleDuration })
	}
	
	// Called each time a peripheral is connected
	func centralManager(
		_ central: CBCentralManager,
		didConnect peripheral: CBPeripheral
	) {
		isConnecting = false
		isConnected = true
		
		UserDefaults.preferredPeripheralId = peripheral.identifier.uuidString
		
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
		}
		else {
			// we are null just disconnect and start over
			lastConnectionError = "🚫 [BLE] Bluetooth connection error, please try again."
			disconnectPeripheral()
			return
		}
		// Discover Services
		peripheral.discoverServices([BluetoothUUID.meshtasticService])
		Logger.services.info("✅ [BLE] Connected: \(peripheral.name ?? "Unknown", privacy: .public)")
	}
	
	// Called when a Peripheral fails to connect
	func centralManager(
		_ central: CBCentralManager,
		didFailToConnect peripheral: CBPeripheral,
		error: Error?
	) {
		cancelPeripheralConnection()
		Logger.services.error("🚫 [BLE] Failed to Connect: \(peripheral.name ?? "Unknown", privacy: .public)")
	}
	
	// Disconnect Peripheral Event
	func centralManager(
		_ central: CBCentralManager,
		didDisconnectPeripheral peripheral: CBPeripheral,
		error: Error?
	) {
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
			}
			else if errorCode == 7 { // CBError.Code.peripheralDisconnected The specified device has disconnected from us.
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
			}
			else if errorCode == 14 { // Peer removed pairing information
				// Forgetting and reconnecting seems to be necessary so we need to show the user an error telling them to do that
				lastConnectionError = "🚨 " + String.localizedStringWithFormat("ble.errorcode.14 %@".localized, e.localizedDescription)
				Logger.services.error("🚨 [BLE] Disconnected: \(peripheral.name ?? "Unknown") Error Code: \(errorCode, privacy: .public) Error: \(self.lastConnectionError, privacy: .public)")
			}
			else {
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
		}
		else {
			// Disconnected without error which indicates user intent to disconnect
			// Happens when swiping to disconnect
			Logger.services.info("ℹ️ [BLE] Disconnected: \(peripheral.name ?? "Unknown", privacy: .public): User Initiated Disconnect")
		}
		
		// Start a scan so the disconnected peripheral is moved to the peripherals[] if it is awake
		self.startScanning()
	}
}
