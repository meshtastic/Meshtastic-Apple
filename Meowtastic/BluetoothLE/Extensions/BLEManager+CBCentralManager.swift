import CoreBluetooth
import OSLog

extension BLEManager: CBCentralManagerDelegate {
	func centralManagerDidUpdateState(
		_ central: CBCentralManager
	) {
		if central.state == .poweredOn {

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


	func centralManager(
		_ central: CBCentralManager,
		didDiscover peripheral: CBPeripheral,
		advertisementData: [String: Any],
		rssi RSSI: NSNumber
	) {
		if
			automaticallyReconnect,
			let preferred = UserDefaults.standard.object(forKey: "preferredPeripheralId") as? String,
			peripheral.identifier.uuidString == preferred
		{
			connectTo(peripheral: peripheral)

			Logger.services.info(
				"✅ [BLE] Reconnecting to prefered peripheral: \(peripheral.name ?? "Unknown", privacy: .public)"
			)
		}

		let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String
		let device = Device(
			id: peripheral.identifier.uuidString,
			num: 0,
			name: name ?? "Unknown",
			shortName: "?",
			longName: name ?? "Unknown",
			firmwareVersion: "Unknown",
			rssi: RSSI.intValue,
			lastUpdate: Date.now,
			peripheral: peripheral
		)
		let index = devices.map {
			$0.peripheral
		}.firstIndex(of: peripheral)

		if let peripheralIndex = index {
			devices[peripheralIndex] = device
		}
		else {
			devices.append(device)
		}

		let today = Date()
		let visibleDuration = Calendar.current.date(byAdding: .second, value: -5, to: today)!

		devices.removeAll(where: {
			$0.lastUpdate < visibleDuration
		})
	}

	func centralManager(
		_ central: CBCentralManager,
		didConnect peripheral: CBPeripheral
	) {
		UserDefaults.preferredPeripheralId = peripheral.identifier.uuidString

		isConnecting = false
		isConnected = true
		timeoutTimer?.invalidate()
		timeoutCount = 0
		lastConnectionError = ""

		deviceConnected = devices.first(where: {
			$0.peripheral.identifier == peripheral.identifier
		})

		if let deviceConnected {
			deviceConnected.peripheral.delegate = self
		}
		else {
			lastConnectionError = "🚫 [BLE] Bluetooth connection error, please try again."

			disconnectDevice()
			return
		}


		peripheral.discoverServices([BluetoothUUID.meshtasticService])

		Logger.services.info("✅ [BLE] Connected: \(peripheral.name ?? "Unknown", privacy: .public)")
	}

	func centralManager(
		_ central: CBCentralManager,
		didFailToConnect peripheral: CBPeripheral,
		error: Error?
	) {
		cancelPeripheralConnection()

		Logger.services.error("🚫 [BLE] Failed to Connect: \(peripheral.name ?? "Unknown", privacy: .public)")
	}

	func centralManager(
		_ central: CBCentralManager,
		didDisconnectPeripheral peripheral: CBPeripheral,
		error: Error?
	) {
		deviceConnected = nil
		isConnecting = false
		isConnected = false
		isSubscribed = false

		let manager = LocalNotificationManager()

		if let error {
			// https://developer.apple.com/documentation/corebluetooth/cberror/code
			switch (error as NSError).code {
			case 6:
				lastConnectionError = "Connection timed out. Will connect back soon."

			case 7:
				if UserDefaults.preferredPeripheralId == peripheral.identifier.uuidString {
					manager.notifications = [
						Notification(
							id: (peripheral.identifier.uuidString),
							title: "Radio Disconnected",
							subtitle: "\(peripheral.name ?? "unknown".localized)",
							content: error.localizedDescription,
							target: "bluetooth",
							path: "meshtastic:///bluetooth"
						)
					]
					manager.schedule()
				}

				lastConnectionError = "Node was disconnected. Check if it's turned on."

			case 14:
				lastConnectionError = "Pairing was cancelled. Please try to pair the node again."

			default:
				if UserDefaults.preferredPeripheralId == peripheral.identifier.uuidString {
					manager.notifications = [
						Notification(
							id: (peripheral.identifier.uuidString),
							title: "Radio Disconnected",
							subtitle: "\(peripheral.name ?? "unknown".localized)",
							content: error.localizedDescription,
							target: "bluetooth",
							path: "meshtastic:///bluetooth"
						)
					]
					manager.schedule()
				}

				lastConnectionError = error.localizedDescription
			}
		}

		startScanning()
	}
}
