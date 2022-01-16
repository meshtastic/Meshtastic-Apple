import Foundation
import CoreData
import CoreBluetooth
import SwiftUI
import MapKit

// ---------------------------------------------------------------------------------------
// Meshtastic BLE Device Manager
// ---------------------------------------------------------------------------------------
class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {

	static let shared = BLEManager()

	private static var documentsFolder: URL {
		do {
			return try FileManager.default.url(for: .documentDirectory,	in: .userDomainMask, appropriateFor: nil, create: true)
		} catch {
			fatalError("Can't find documents directory.")
		}
	}

	var context: NSManagedObjectContext?

	private var centralManager: CBCentralManager!

	@Published var peripherals = [Peripheral]()

    @Published var connectedPeripheral: Peripheral!
    //@Published var lastConnectedPeripheral: String
    @Published var lastConnectionError: String
	@Published var lastConnnectionVersion: String

	@Published var isSwitchedOn: Bool = false
	@Published var isScanning: Bool = false
	@Published var isConnected: Bool = false

	var timeoutTimer: Timer?
	var timeoutTimerCount = 0

    let broadcastNodeNum: UInt32 = 4294967295

    /* Meshtastic Service Details */
    var TORADIO_characteristic: CBCharacteristic!
    var FROMRADIO_characteristic: CBCharacteristic!
    var FROMNUM_characteristic: CBCharacteristic!

    let meshtasticServiceCBUUID = CBUUID(string: "0x6BA1B218-15A8-461F-9FA8-5DCAE273EAFD")
    let TORADIO_UUID = CBUUID(string: "0xF75C76D2-129E-4DAD-A1DD-7866124401E7")
    let FROMRADIO_UUID = CBUUID(string: "0x8BA2BCC2-EE02-4A55-A531-C525C5E454D5")
    let FROMNUM_UUID = CBUUID(string: "0xED9DA18C-A800-4F66-A670-AA7547E34453")

	private var meshLoggingEnabled: Bool = true
	let meshLog = documentsFolder.appendingPathComponent("meshlog.txt")

    // MARK: init BLEManager
    override init() {

		self.meshLoggingEnabled = true // UserDefaults.standard.object(forKey: "meshActivityLog") as? Bool ?? false
        self.lastConnectionError = ""
		self.lastConnnectionVersion = "0.0.0"
        super.init()
		// let bleQueue: DispatchQueue = DispatchQueue(label: "CentralManager")
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

	// MARK: Bluetooth enabled/disabled for the app
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
         if central.state == .poweredOn {

             isSwitchedOn = true
			 startScanning()
         } else {

             isSwitchedOn = false
         }
    }

	// MARK: Scanning for BLE Devices
    // Scan for nearby BLE devices using the Meshtastic BLE service ID
    func startScanning() {

        if isSwitchedOn {

            centralManager.scanForPeripherals(withServices: [meshtasticServiceCBUUID], options: nil)
			self.isScanning = self.centralManager.isScanning

            print("✅ Scanning Started")
        }
    }

	// Stop Scanning For BLE Devices
    func stopScanning() {

        if centralManager.isScanning {

            self.centralManager.stopScan()
			self.isScanning = self.centralManager.isScanning

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

		if timeoutTimerCount == 5 {

			if connectedPeripheral != nil {

				self.centralManager?.cancelPeripheralConnection(connectedPeripheral.peripheral)
			}
			connectedPeripheral = nil

			self.lastConnectionError = "🚨 BLE Connection Timeout after making \(timeoutTimerCount) attempts to connect to \(name)."
			print("🚨 BLE Connection Timeout after making \(timeoutTimerCount) attempts to connect to \(name).")
			if meshLoggingEnabled { MeshLogger.log("🚨 BLE Connection Timeout after making \(timeoutTimerCount) attempts to connect to \(String(name)). This can occur when a device has been taken out of BLE range, or if a device is already connected to another phone, tablet or computer.") }

			self.timeoutTimerCount = 0
			self.timeoutTimer?.invalidate()

		} else {
			print("🚨 BLE Connecting 2 Second Timeout Timer Fired \(timeoutTimerCount) Time(s): \(name)")
			if meshLoggingEnabled { MeshLogger.log("🚨 BLE Connecting 2 Second Timeout Timer Fired \(timeoutTimerCount) Time(s): \(name)") }
		}
	}

    // Connect to a specific peripheral
    func connectTo(peripheral: CBPeripheral) {

		if meshLoggingEnabled { MeshLogger.log("✅ BLE Connecting: \(peripheral.name ?? "Unknown")") }
		print("✅ BLE Connecting: \(peripheral.name ?? "Unknown")")

        stopScanning()

		if self.connectedPeripheral != nil {
			if meshLoggingEnabled { MeshLogger.log("ℹ️ BLE Disconnecting from: \(self.connectedPeripheral.name) to connect to \(peripheral.name ?? "Unknown")") }
			print("ℹ️ BLE Disconnecting from: \(self.connectedPeripheral.name) to connect to \(peripheral.name ?? "Unknown")")
            self.disconnectPeripheral()
        }

		self.centralManager?.connect(peripheral)

		// Use a timer to keep track of connecting peripherals, context to pass the radio name with the timer and the RunLoop to prevent
		// the timer from running on the main UI thread
		let context = ["name": "@\(peripheral.name ?? "Unknown")"]
		self.timeoutTimer = Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: #selector(timeoutTimerFired), userInfo: context, repeats: true)
		RunLoop.current.add(self.timeoutTimer!, forMode: .common)
    }

    // Disconnect Connected Peripheral
    func disconnectPeripheral() {

		guard let connectedPeripheral = connectedPeripheral else { return }
		self.centralManager?.cancelPeripheralConnection(connectedPeripheral.peripheral)
    }

    // Called each time a peripheral is discovered
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {

        var peripheralName: String = peripheral.name ?? "Unknown"

        if let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            peripheralName = name
        }

		let newPeripheral = Peripheral(id: peripheral.identifier.uuidString, num: 0, name: peripheralName, shortName: String(peripheralName.suffix(3)), longName: peripheralName, firmwareVersion: "Unknown", rssi: RSSI.intValue, subscribed: false, peripheral: peripheral)
		let peripheralIndex = peripherals.firstIndex(where: { $0.id == newPeripheral.id })

		if peripheralIndex != nil && newPeripheral.peripheral.state != CBPeripheralState.connected {

			peripherals[peripheralIndex!] = newPeripheral
			peripherals.remove(at: peripheralIndex!)
			peripherals.append(newPeripheral)
			print("ℹ️ Updating peripheral: \(peripheralName)")

		} else {

			if newPeripheral.peripheral.state != CBPeripheralState.connected {

				peripherals.append(newPeripheral)
				print("ℹ️ Adding peripheral: \(peripheralName)")
			}
		}
    }

    // Called when a peripheral is connected
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {

		self.isConnected = true

		// Invalidate and reset connection timer count, remove any connection errors
		self.lastConnectionError = ""
		self.timeoutTimer!.invalidate()
		self.timeoutTimerCount = 0

		// Map the peripheral to the connectedNode and connectedPeripheral ObservedObjects
        connectedPeripheral = peripherals.filter({ $0.peripheral.identifier == peripheral.identifier }).first
		connectedPeripheral.peripheral.delegate = self

		let fetchConnectedPeripheralRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
		fetchConnectedPeripheralRequest.predicate = NSPredicate(format: "bleName MATCHES %@", String(peripheral.name ?? "???"))

		do {
			let fetchedNode = try context?.fetch(fetchConnectedPeripheralRequest) as! [NodeInfoEntity]

			if fetchedNode.count == 1 {

				connectedPeripheral.num = fetchedNode[0].user!.num
				connectedPeripheral.shortName = fetchedNode[0].user!.shortName!
				connectedPeripheral.longName = fetchedNode[0].user!.longName!
				connectedPeripheral.firmwareVersion = (fetchedNode[0].myInfo?.firmwareVersion ?? "Unknown")
			}

		} catch {
			print("💥 Fetch NodeInfo Failed")
			if meshLoggingEnabled { MeshLogger.log("💥 Fetch NodeInfo Failed") }
		}

        //lastConnectedPeripheral = peripheral.identifier.uuidString

		// Discover Services
        peripheral.discoverServices([meshtasticServiceCBUUID])
		if meshLoggingEnabled { MeshLogger.log("✅ BLE Connected: \(peripheral.name ?? "Unknown")") }
        print("✅ BLE Connected: \(peripheral.name ?? "Unknown")")

    }

	// Called when a Peripheral fails to connect
	func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {

		if meshLoggingEnabled { MeshLogger.log("🚫 BLE Failed to Connect: \(peripheral.name ?? "Unknown")") }
		print("🚫 BLE Failed to Connect: \(peripheral.name ?? "Unknown")")
		disconnectPeripheral()
	}

    // Disconnect Peripheral Event
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // Start a scan so the disconnected peripheral is moved to the peripherals[] if it is awake
        self.startScanning()
		self.connectedPeripheral = nil

        if let e = error {

			// https://developer.apple.com/documentation/corebluetooth/cberror/code
            let errorCode = (e as NSError).code
            // unknown = 0,

            if errorCode == 6 { // CBError.Code.connectionTimeout The connection has timed out unexpectedly.

				// Happens when device is manually reset / powered off
				// We will try and re-connect to this device
				lastConnectionError = "🚨 \(e.localizedDescription) The app will automatically reconnect to the preferred radio if it reappears within 10 seconds."
				if peripheral.identifier.uuidString == UserDefaults.standard.object(forKey: "preferredPeripheralId") as? String ?? "" {
					if meshLoggingEnabled { MeshLogger.log("ℹ️ BLE Reconnecting: \(peripheral.name ?? "Unknown")") }
					print("ℹ️ BLE Reconnecting: \(peripheral.name ?? "Unknown")")
					self.connectTo(peripheral: peripheral)
				}
            } else if errorCode == 7 { // CBError.Code.peripheralDisconnected The specified device has disconnected from us.

                // Seems to be what is received when a tbeam sleeps, immediately recconnecting does not work.
				lastConnectionError = e.localizedDescription

				print("🚨 BLE Disconnected: \(peripheral.name ?? "Unknown") Error Code: \(errorCode) Error: \(e.localizedDescription)")
				if meshLoggingEnabled { MeshLogger.log("🚨 BLE Disconnected: \(peripheral.name ?? "Unknown") Error Code: \(errorCode) Error: \(e.localizedDescription)") }
            } else if errorCode == 14 { // Peer removed pairing information

                // Forgetting and reconnecting seems to be necessary so we need to show the user an error telling them to do that
				lastConnectionError = "🚨 \(e.localizedDescription) This error usually cannot be fixed without forgetting the device unders Settings > Bluetooth and re-connecting to the radio."

				if meshLoggingEnabled { MeshLogger.log("🚨 BLE Disconnected: \(peripheral.name ?? "Unknown") Error Code: \(errorCode) Error: \(lastConnectionError)") }
            } else {

				lastConnectionError = e.localizedDescription

				print("🚨 BLE Disconnected: \(peripheral.name ?? "Unknown") Error Code: \(errorCode) Error: \(e.localizedDescription)")
				if meshLoggingEnabled { MeshLogger.log("🚨 BLE Disconnected: \(peripheral.name ?? "Unknown") Error Code: \(errorCode) Error: \(e.localizedDescription)") }
			}
        } else {

            // Disconnected without error which indicates user intent to disconnect
			// Happens when swiping to disconnect
			if meshLoggingEnabled { MeshLogger.log("ℹ️ BLE Disconnected: \(peripheral.name ?? "Unknown"): User Initiated Disconnect") }
            print("ℹ️ BLE Disconnected: \(peripheral.name ?? "Unknown"): User Initiated Disconnect")
        }
    }

    // MARK: Peripheral Services functions
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {

        if let e = error {

            print("🚫 Discover Services error \(e)")
        }

        guard let services = peripheral.services else { return }

        for service in services {

            if service.uuid == meshtasticServiceCBUUID {
                print("✅ Meshtastic service discovered OK")
				if meshLoggingEnabled { MeshLogger.log("✅ BLE Service for Meshtastic discovered by \(peripheral.name ?? "Unknown")") }
                peripheral.discoverCharacteristics(nil, for: service)
               // peripheral.discoverCharacteristics([TORADIO_UUID, FROMRADIO_UUID, FROMNUM_UUID], for: service)
            }
        }
    }

    // MARK: Discover Characteristics Event
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let e = error {

            print("🚫 Discover Characteristics error \(e)")
			if meshLoggingEnabled { MeshLogger.log("🚫 BLE didDiscoverCharacteristicsFor error by \(peripheral.name ?? "Unknown") \(e)") }
        }

        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {

			switch characteristic.uuid {
			case TORADIO_UUID:
				print("✅ TORADIO characteristic OK")
				if meshLoggingEnabled { MeshLogger.log("✅ BLE did discover TORADIO characteristic for Meshtastic by \(peripheral.name ?? "Unknown")") }
				TORADIO_characteristic = characteristic
				var toRadio: ToRadio = ToRadio()
				toRadio.wantConfigID = 32168
				let binaryData: Data = try! toRadio.serializedData()
				peripheral.writeValue(binaryData, for: characteristic, type: .withResponse)

			case FROMRADIO_UUID:
				print("✅ FROMRADIO characteristic OK")
				if meshLoggingEnabled { MeshLogger.log("✅ BLE did discover FROMRADIO characteristic for Meshtastic by \(peripheral.name ?? "Unknown")") }
				FROMRADIO_characteristic = characteristic
				peripheral.readValue(for: FROMRADIO_characteristic)

			case FROMNUM_UUID:
				print("✅ FROMNUM (Notify) characteristic OK")
				if meshLoggingEnabled { MeshLogger.log("✅ BLE did discover FROMNUM (Notify) characteristic for Meshtastic by \(peripheral.name ?? "Unknown")") }
				FROMNUM_characteristic = characteristic
				peripheral.setNotifyValue(true, for: characteristic)

			default:
				break
			}

      }
    }

	func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {

		print("ℹ️ didUpdateNotificationStateFor char: \(characteristic.uuid.uuidString) \(characteristic.isNotifying)")
		if meshLoggingEnabled { MeshLogger.log("ℹ️ didUpdateNotificationStateFor char: \(characteristic.uuid.uuidString) \(characteristic.isNotifying)") }

		if let errorText = error?.localizedDescription {
			  print("🚫 didUpdateNotificationStateFor error: \(errorText)")
		}
	}

    // MARK: Data Read / Update Characteristic Event
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
       
		
		if let e = error {
			
			print("🚫 didUpdateValueFor Characteristic error \(e)")

			let errorCode = (e as NSError).code
			
			if errorCode == 5 { // CBATTErrorDomain Code=5 "Authentication is insufficient."

				// BLE Pin connection error
				// We will try and re-connect to this device
				lastConnectionError = "🚫 BLE \(e.localizedDescription) Please try connecting again and check the PIN carefully."
				if meshLoggingEnabled { MeshLogger.log("🚫 BLE \(e.localizedDescription) Please try connecting again and check the PIN carefully.") }
				self.centralManager?.cancelPeripheralConnection(peripheral)

			}
			if errorCode == 15 { // CBATTErrorDomain Code=15 "Encryption is insufficient."

				// BLE Pin connection error
				// We will try and re-connect to this device
				lastConnectionError = "🚫 BLE \(e.localizedDescription) This may be a Meshtastic Firmware bug affecting BLE 4.0 devices."
				if meshLoggingEnabled { MeshLogger.log("🚫 BLE \(e.localizedDescription) Please try connecting again. You may need to forget the device under Settings > General > Bluetooth.") }
				self.centralManager?.cancelPeripheralConnection(peripheral)

			}
        }

        switch characteristic.uuid {
		case FROMNUM_UUID:
			peripheral.readValue(for: FROMNUM_characteristic)
			let characteristicValue: [UInt8] = [UInt8](characteristic.value!)
			let bigEndianUInt32 = characteristicValue.withUnsafeBytes { $0.load(as: UInt32.self) }
			let returnValue = CFByteOrderGetCurrent() == CFByteOrder(CFByteOrderLittleEndian.rawValue)
							? UInt32(bigEndian: bigEndianUInt32) : bigEndianUInt32
		    // print(returnValue)

		case FROMRADIO_UUID:
			if characteristic.value == nil || characteristic.value!.isEmpty {
				return
			}
			// print(characteristic.value ?? "no value")
			// print(characteristic.value?.hexDescription ?? "no value")
			var decodedInfo = FromRadio()

			decodedInfo = try! FromRadio(serializedData: characteristic.value!)
			// print("Print DecodedInfo")
			// print(decodedInfo)

			// MARK: Incoming MyInfo Packet
			if decodedInfo.myInfo.myNodeNum != 0 {

				let fetchMyInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "MyInfoEntity")
				fetchMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", Int64(decodedInfo.myInfo.myNodeNum))

				do {
					let fetchedMyInfo = try context?.fetch(fetchMyInfoRequest) as! [MyInfoEntity]
					// Not Found Insert
					if fetchedMyInfo.isEmpty {
						let myInfo = MyInfoEntity(context: context!)
						myInfo.myNodeNum = Int64(decodedInfo.myInfo.myNodeNum)
						myInfo.hasGps = decodedInfo.myInfo.hasGps_p
						myInfo.numBands = Int32(bitPattern: decodedInfo.myInfo.numBands)
						
						// Swift does strings weird, this does work
						let lastDotIndex = decodedInfo.myInfo.firmwareVersion.lastIndex(of: ".")//.lastIndex(of: ".", offsetBy: -1)
						var version = decodedInfo.myInfo.firmwareVersion[...(lastDotIndex ?? String.Index(utf16Offset: 6, in: decodedInfo.myInfo.firmwareVersion))]
						version = version.dropLast()
						myInfo.firmwareVersion = String(version)
						lastConnnectionVersion = String(version)
				
						myInfo.messageTimeoutMsec = Int32(bitPattern: decodedInfo.myInfo.messageTimeoutMsec)
						myInfo.minAppVersion = Int32(bitPattern: decodedInfo.myInfo.minAppVersion)
						myInfo.maxChannels = Int32(bitPattern: decodedInfo.myInfo.maxChannels)
						connectedPeripheral.num = myInfo.myNodeNum
						connectedPeripheral.firmwareVersion = myInfo.firmwareVersion ?? "Unknown"
						
						let fetchBCUserRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "UserEntity")
						fetchBCUserRequest.predicate = NSPredicate(format: "num == %lld", Int64(decodedInfo.myInfo.myNodeNum))
						
						do {
							let fetchedUser = try context?.fetch(fetchBCUserRequest) as! [UserEntity]
							
							if fetchedUser.isEmpty {
								// Save the broadcast user if it does not exist
								let bcu: UserEntity = UserEntity(context: context!)
								bcu.shortName = "ALL"
								bcu.longName = "All - Broadcast"
								bcu.hwModel = "UNSET"
								bcu.num = Int64(broadcastNodeNum)
								bcu.userId = "BROADCASTNODE"
								print("💾 Saved the All - Broadcast User")
							}
							
						} catch {
							
							print("💥 Error Saving the All - Broadcast User")
						}
						
					} else {

						fetchedMyInfo[0].myNodeNum = Int64(decodedInfo.myInfo.myNodeNum)
						fetchedMyInfo[0].hasGps = decodedInfo.myInfo.hasGps_p
						fetchedMyInfo[0].numBands = Int32(bitPattern: decodedInfo.myInfo.numBands)
						let lastDotIndex = decodedInfo.myInfo.firmwareVersion.lastIndex(of: ".")//.lastIndex(of: ".", offsetBy: -1)
						var version = decodedInfo.myInfo.firmwareVersion[...(lastDotIndex ?? String.Index(utf16Offset:6, in: decodedInfo.myInfo.firmwareVersion))]
						version = version.dropLast()
						fetchedMyInfo[0].firmwareVersion = String(version)
						lastConnnectionVersion = String(version)
						fetchedMyInfo[0].messageTimeoutMsec = Int32(bitPattern: decodedInfo.myInfo.messageTimeoutMsec)
						fetchedMyInfo[0].minAppVersion = Int32(bitPattern: decodedInfo.myInfo.minAppVersion)
						fetchedMyInfo[0].maxChannels = Int32(bitPattern: decodedInfo.myInfo.maxChannels)
					}
					do {

						try context!.save()
						print("💾 Saved a myInfo for \(decodedInfo.myInfo.myNodeNum)")
						if meshLoggingEnabled { MeshLogger.log("💾 Saved a myInfo for \(peripheral.name ?? String(decodedInfo.myInfo.myNodeNum))") }

					} catch {

						context!.rollback()

						let nsError = error as NSError
						print("💥 Error Saving CoreData MyInfoEntity: \(nsError)")
					}

				} catch {

					print("💥 Fetch MyInfo Error")
				}
			}

			// MARK: Incoming Node Info Packet
			if decodedInfo.nodeInfo.num != 0 {

				let fetchNodeRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
				fetchNodeRequest.predicate = NSPredicate(format: "num == %lld", Int64(decodedInfo.nodeInfo.num))

				do {

					let fetchedNode = try context?.fetch(fetchNodeRequest) as! [NodeInfoEntity]
					// Not Found Insert
					if fetchedNode.isEmpty && decodedInfo.nodeInfo.hasUser {

						let newNode = NodeInfoEntity(context: context!)
						newNode.id = Int64(decodedInfo.nodeInfo.num)
						newNode.num = Int64(decodedInfo.nodeInfo.num)
						if decodedInfo.nodeInfo.lastHeard > 0 {
							newNode.lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(decodedInfo.nodeInfo.lastHeard)))
						}
						else {
							newNode.lastHeard = Date()
						}
						newNode.snr = decodedInfo.nodeInfo.snr

						if self.connectedPeripheral != nil && self.connectedPeripheral.num == newNode.id {

							newNode.bleName = self.connectedPeripheral.peripheral.name
							if decodedInfo.nodeInfo.hasUser {

								connectedPeripheral.name  = decodedInfo.nodeInfo.user.longName
								connectedPeripheral.longName = decodedInfo.nodeInfo.user.longName
								connectedPeripheral.shortName = decodedInfo.nodeInfo.user.shortName
								connectedPeripheral.num	= Int64(decodedInfo.nodeInfo.num)
							}
						}

						if decodedInfo.nodeInfo.hasUser {

							let newUser = UserEntity(context: context!)
							newUser.userId = decodedInfo.nodeInfo.user.id
							newUser.num = Int64(decodedInfo.nodeInfo.num)
							newUser.longName = decodedInfo.nodeInfo.user.longName
							newUser.shortName = decodedInfo.nodeInfo.user.shortName
							newUser.macaddr = decodedInfo.nodeInfo.user.macaddr
							newUser.hwModel = String(describing: decodedInfo.nodeInfo.user.hwModel).uppercased()
							newUser.team = (String(describing: decodedInfo.nodeInfo.user.team))
							newNode.user = newUser
						}

						let position = PositionEntity(context: context!)
						position.latitudeI = decodedInfo.nodeInfo.position.latitudeI
						position.longitudeI = decodedInfo.nodeInfo.position.longitudeI
						position.altitude = decodedInfo.nodeInfo.position.altitude

						position.batteryLevel = decodedInfo.nodeInfo.position.batteryLevel
						position.time = Date(timeIntervalSince1970: TimeInterval(Int64(decodedInfo.nodeInfo.position.time)))

						var newPostions = [PositionEntity]()
						newPostions.append(position)
						newNode.positions? = NSOrderedSet(array: newPostions)

						// Look for a MyInfo
						let fetchMyInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "MyInfoEntity")
						fetchMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", Int64(decodedInfo.nodeInfo.num))

						do {

							let fetchedMyInfo = try context?.fetch(fetchMyInfoRequest) as! [MyInfoEntity]
							if fetchedMyInfo.count > 0 {
								newNode.myInfo = fetchedMyInfo[0]

							}

						} catch {
							print("💥 Fetch MyInfo Error")
						}

					} else if decodedInfo.nodeInfo.hasUser {

						fetchedNode[0].id = Int64(decodedInfo.nodeInfo.num)
						fetchedNode[0].num = Int64(decodedInfo.nodeInfo.num)
						fetchedNode[0].lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(decodedInfo.nodeInfo.lastHeard)))
						fetchedNode[0].snr = decodedInfo.nodeInfo.snr

						if decodedInfo.nodeInfo.hasUser {

							fetchedNode[0].user!.userId = decodedInfo.nodeInfo.user.id
							fetchedNode[0].user!.longName = decodedInfo.nodeInfo.user.longName
							fetchedNode[0].user!.shortName = decodedInfo.nodeInfo.user.shortName
							fetchedNode[0].user!.hwModel = String(describing: decodedInfo.nodeInfo.user.hwModel).uppercased()
							fetchedNode[0].user!.team = (String(describing: decodedInfo.nodeInfo.user.team))
						}

						let position = PositionEntity(context: context!)
						position.latitudeI = decodedInfo.nodeInfo.position.latitudeI
						position.longitudeI = decodedInfo.nodeInfo.position.longitudeI
						position.altitude = decodedInfo.nodeInfo.position.altitude
						position.batteryLevel = decodedInfo.nodeInfo.position.batteryLevel
						position.time = Date(timeIntervalSince1970: TimeInterval(Int64(decodedInfo.nodeInfo.position.time)))

						let mutablePositions = fetchedNode[0].positions!.mutableCopy() as! NSMutableOrderedSet
						mutablePositions.add(position)

						if position.coordinate == nil {
							var newPostions = [PositionEntity]()
							newPostions.append(position)
							fetchedNode[0].positions? = NSOrderedSet(array: newPostions)

						} else {

							fetchedNode[0].positions = mutablePositions.copy() as? NSOrderedSet
						}

						// Look for a MyInfo
						let fetchMyInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "MyInfoEntity")
						fetchMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", Int64(decodedInfo.nodeInfo.num))

						do {

							let fetchedMyInfo = try context?.fetch(fetchMyInfoRequest) as! [MyInfoEntity]
							if fetchedMyInfo.count > 0 {

								fetchedNode[0].myInfo = fetchedMyInfo[0]
							}

						} catch {
							print("💥 Fetch MyInfo Error")
						}
					}
					do {

						try context!.save()
						print("💾 Saved a nodeInfo for \(decodedInfo.nodeInfo.num)")

					} catch {

						context!.rollback()

						let nsError = error as NSError
						print("💥 Error Saving CoreData NodeInfoEntity: \(nsError)")
					}

				} catch {

					print("💥 Fetch NodeInfoEntity Error")
				}

				if decodedInfo.nodeInfo.hasUser {

					print("💾 BLE FROMRADIO received and nodeInfo saved for \(decodedInfo.nodeInfo.user.longName)")
					if meshLoggingEnabled { MeshLogger.log("💾 BLE FROMRADIO received and nodeInfo saved for \(decodedInfo.nodeInfo.user.longName)") }

				} else {

					print("💾 BLE FROMRADIO received and nodeInfo saved for \(decodedInfo.nodeInfo.num)")
					if meshLoggingEnabled { MeshLogger.log("💾 BLE FROMRADIO received and nodeInfo saved for \(decodedInfo.nodeInfo.num)") }
				}
			}
			// Handle assorted app packets
			if decodedInfo.packet.id  != 0 {

				do {

					// MARK: Incoming Packet from the TEXTMESSAGE_APP
					if decodedInfo.packet.decoded.portnum == PortNum.textMessageApp {

						if let messageText = String(bytes: decodedInfo.packet.decoded.payload, encoding: .utf8) {

							print("💬 BLE FROMRADIO received for text message app \(messageText)")
							if meshLoggingEnabled { MeshLogger.log("💬 BLE FROMRADIO received for text message app \(messageText)") }

							let messageUsers: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "UserEntity")
							messageUsers.predicate = NSPredicate(format: "num IN %@", [decodedInfo.packet.to, decodedInfo.packet.from])

							do {

								let fetchedUsers = try context?.fetch(messageUsers) as! [UserEntity]

								let newMessage = MessageEntity(context: context!)
								newMessage.messageId = Int64(decodedInfo.packet.id)
								
								
								if decodedInfo.packet.rxTime == 0 {

									newMessage.messageTimestamp = Int32(Date().timeIntervalSince1970)

								} else {

									newMessage.messageTimestamp = Int32(bitPattern: decodedInfo.packet.rxTime)
								}
								newMessage.receivedACK = false
								newMessage.direction = "IN"
								newMessage.isTapback = decodedInfo.packet.decoded.isTapback
								
								if decodedInfo.packet.decoded.replyID > 0 {
									
									newMessage.replyID = Int64(decodedInfo.packet.decoded.replyID)
								}

								if decodedInfo.packet.to == broadcastNodeNum && fetchedUsers.count == 1 {

									// Save the broadcast user if it does not exist
									let bcu: UserEntity = UserEntity(context: context!)
									bcu.shortName = "ALL"
									bcu.longName = "All - Broadcast"
									bcu.hwModel = "UNSET"
									bcu.num = Int64(broadcastNodeNum)
									bcu.userId = "BROADCASTNODE"
									newMessage.toUser = bcu

								} else {

									newMessage.toUser = fetchedUsers.first(where: { $0.num == decodedInfo.packet.to })
								}

								newMessage.fromUser = fetchedUsers.first(where: { $0.num == decodedInfo.packet.from })
								newMessage.messagePayload = messageText

								do {

									try context!.save()
									print("💾 Saved a new message for \(decodedInfo.packet.id)")
									if meshLoggingEnabled { MeshLogger.log("💾 Saved a new message for \(decodedInfo.packet.id)") }
									
									if newMessage.toUser!.num == self.broadcastNodeNum || self.connectedPeripheral != nil && self.connectedPeripheral.num == newMessage.toUser!.num {
										
										// Create an iOS Notification for the received message and schedule it immediately
										let manager = LocalNotificationManager()

										manager.notifications = [
											Notification(
												id: ("notification.id.\(decodedInfo.packet.id)"),
												title: "\(newMessage.fromUser?.longName ?? "Unknown")",
												subtitle: "AKA \(newMessage.fromUser?.shortName ?? "???")",
												content: messageText)
										]
										manager.schedule()
										if meshLoggingEnabled { MeshLogger.log("💬 iOS Notification Scheduled for text message from \(newMessage.fromUser?.longName ?? "Unknown") \(messageText)") }

									}
								} catch {

									context!.rollback()

									let nsError = error as NSError
									print("💥 Failed to save new MessageEntity \(nsError)")
								}

							} catch {

							print("💥 Fetch Message To and From Users Error")
						}
					}
				} else if decodedInfo.packet.decoded.portnum == PortNum.nodeinfoApp {

					let fetchNodeInfoAppRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
					fetchNodeInfoAppRequest.predicate = NSPredicate(format: "num == %lld", Int64(decodedInfo.packet.from))

					do {

						let fetchedNode = try context?.fetch(fetchNodeInfoAppRequest) as! [NodeInfoEntity]

						if fetchedNode.count == 1 {
							fetchedNode[0].id = Int64(decodedInfo.packet.from)
							fetchedNode[0].num = Int64(decodedInfo.packet.from)
							
							if decodedInfo.packet.rxTime > 0 {
								fetchedNode[0].lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(decodedInfo.packet.rxTime)))
							}
							else {
								fetchedNode[0].lastHeard = Date()
							}
							
							fetchedNode[0].snr = decodedInfo.packet.rxSnr

						} else {
							return
						}
						do {

							try context!.save()

							if meshLoggingEnabled { MeshLogger.log("💾 Updated NodeInfo SNR and Time from Node Info App Packet For: \(Int64(decodedInfo.nodeInfo.num))")}
							print("💾 Updated NodeInfo SNR and Time from Packet For: \(fetchedNode[0].num)")

						} catch {

							context!.rollback()

							let nsError = error as NSError
							print("💥 Error Saving NodeInfoEntity from NODEINFO_APP \(nsError)")

						}
					} catch {

						print("💥 Error Fetching NodeInfoEntity for NODEINFO_APP")
					}

				// MARK: Incoming Packet from the POSITION_APP
				} else if  decodedInfo.packet.decoded.portnum == PortNum.positionApp {

					let fetchNodePositionRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
					fetchNodePositionRequest.predicate = NSPredicate(format: "num == %lld", Int64(decodedInfo.packet.from))

					do {

						let fetchedNode = try context?.fetch(fetchNodePositionRequest) as! [NodeInfoEntity]

						if fetchedNode.count == 1 {
							fetchedNode[0].id = Int64(decodedInfo.packet.from)
							fetchedNode[0].num = Int64(decodedInfo.packet.from)
							if decodedInfo.packet.rxTime == 0 {

								fetchedNode[0].lastHeard = Date()

							} else {

								fetchedNode[0].lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(decodedInfo.packet.rxTime)))

							}
							fetchedNode[0].snr = decodedInfo.packet.rxSnr

						} else {
							
							return
						}
						do {

						  try context!.save()

							if meshLoggingEnabled {
								MeshLogger.log("💾 Updated NodeInfo SNR and Time from Node Info App Packet For: \(fetchedNode[0].num)")
							}
							print("💾 Updated NodeInfo SNR and Time from Position Packet For: \(fetchedNode[0].num)")

						} catch {

							context!.rollback()

							let nsError = error as NSError
							print("💥 Error Saving NodeInfoEntity from NODEINFO_APP \(nsError)")
						}
					} catch {

						print("💥 Error Fetching NodeInfoEntity for NODEINFO_APP")
					}

					
					//
				} else if  decodedInfo.packet.decoded.portnum == PortNum.storeForwardApp {

					 if meshLoggingEnabled { MeshLogger.log("🚨 MESH PACKET received for Store Forward App UNHANDLED \(try decodedInfo.packet.jsonString())") }
					 print("ℹ️ MESH PACKET received for Admin App UNHANDLED \(try decodedInfo.packet.jsonString())")

				 } else if  decodedInfo.packet.decoded.portnum == PortNum.adminApp {

					 if meshLoggingEnabled { MeshLogger.log("🚨 MESH PACKET received for Admin App UNHANDLED \(try decodedInfo.packet.jsonString())") }
					 print("ℹ️ MESH PACKET received for Admin App UNHANDLED \(try decodedInfo.packet.jsonString())")

				 } else if  decodedInfo.packet.decoded.portnum == PortNum.routingApp {

					 if meshLoggingEnabled { MeshLogger.log("🚨 MESH PACKET received for Routing App UNHANDLED \(try decodedInfo.packet.jsonString())") }
					 print("ℹ️ MESH PACKET received for Routing App UNHANDLED \(try decodedInfo.packet.jsonString())")

				 } else {

					 if meshLoggingEnabled { MeshLogger.log("🚨 MESH PACKET received for Other App UNHANDLED \(try decodedInfo.packet.jsonString())") }
					 print("ℹ️ MESH PACKET received for Other App UNHANDLED \(try decodedInfo.packet.jsonString())")
				 }

				} catch {
					if meshLoggingEnabled { MeshLogger.log("⚰️ Fatal Error: Failed to decode json") }
					print("⚰️ Fatal Error: Failed to decode json")
				}
			}

			if decodedInfo.configCompleteID != 0 {

				if meshLoggingEnabled { MeshLogger.log("🤜 BLE Config Complete Packet Id: \(decodedInfo.configCompleteID)") }
				print("🤜 BLE Config Complete Packet Id: \(decodedInfo.configCompleteID)")
				self.connectedPeripheral.subscribed = true
				peripherals.removeAll(where: { $0.peripheral.state == CBPeripheralState.disconnected })
			}

		default:
			if meshLoggingEnabled { MeshLogger.log("🚨 Unhandled Characteristic UUID: \(characteristic.uuid)") }
			print("🚨 Unhandled Characteristic UUID: \(characteristic.uuid)")
        }
        peripheral.readValue(for: FROMRADIO_characteristic)
    }

	// Send  Message
	public func sendMessage(message: String, toUserNum: Int64, isTapback: Bool, replyID: Int64) -> Bool {
		
		var success = false

		// Return false if we are not properly connected to a device, handle retry logic in the view for now
		if connectedPeripheral == nil || connectedPeripheral!.peripheral.state != CBPeripheralState.connected {

			self.disconnectPeripheral()
			self.startScanning()

			// Try and connect to the preferredPeripherial first
			let preferredPeripheral = peripherals.filter({ $0.peripheral.identifier.uuidString == UserDefaults.standard.object(forKey: "preferredPeripheralId") as? String ?? "" }).first
			if preferredPeripheral != nil && preferredPeripheral?.peripheral != nil {
				connectTo(peripheral: preferredPeripheral!.peripheral)
			}
			print("🚫 Message Send Failed, not properly connected to \(preferredPeripheral?.name ?? "Unknown")")
			if meshLoggingEnabled { MeshLogger.log("🚫 Message Send Failed, not properly connected to \(preferredPeripheral?.name ?? "Unknown")") }

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

				let fetchedUsers = try context?.fetch(messageUsers) as! [UserEntity]

				if fetchedUsers.isEmpty {

					print("🚫 Message Users Not Found, Fail")
					success = false
					
				} else if fetchedUsers.count >= 1 {

					let newMessage = MessageEntity(context: context!)
					newMessage.messageId = Int64(UInt32.random(in: UInt32(UInt8.max)..<UInt32.max))
					newMessage.messageTimestamp =  Int32(Date().timeIntervalSince1970)
					newMessage.receivedACK = false
					newMessage.direction = "IN"
					newMessage.toUser = fetchedUsers.first(where: { $0.num == toUserNum })
					newMessage.isTapback = isTapback
					
					if replyID > 0 {
						
						newMessage.replyID = replyID
					}
					if newMessage.toUser == nil {

						let bcu: UserEntity = UserEntity(context: context!)
						bcu.shortName = "ALL"
						bcu.longName = "All - Broadcast"
						bcu.hwModel = "UNSET"
						bcu.num = Int64(broadcastNodeNum)
						bcu.userId = "BROADCASTNODE"
						newMessage.toUser = bcu
					}
					
					newMessage.fromUser = fetchedUsers.first(where: { $0.num == fromUserNum })
					newMessage.messagePayload = message

					let dataType = PortNum.textMessageApp
					let payloadData: Data = message.data(using: String.Encoding.utf8)!

					var dataMessage = DataMessage()
					dataMessage.payload = payloadData
					dataMessage.portnum = dataType

					var meshPacket = MeshPacket()
					meshPacket.to = UInt32(toUserNum)
					meshPacket.from	= UInt32(fromUserNum)

					meshPacket.decoded = dataMessage

					meshPacket.decoded.isTapback = isTapback
					if replyID > 0 {
						meshPacket.decoded.replyID = UInt32(replyID)
					}
					meshPacket.wantAck = true

					var toRadio: ToRadio!
					toRadio = ToRadio()
					toRadio.packet = meshPacket

					let binaryData: Data = try! toRadio.serializedData()

					if meshLoggingEnabled { MeshLogger.log("📲 New message sent to \(newMessage.toUser?.longName! ?? "Unknown")") }
					print("📲 New message sent to \(newMessage.toUser?.longName! ?? "Unknown")")

					if connectedPeripheral!.peripheral.state == CBPeripheralState.connected {
						connectedPeripheral.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
						do {

							try context!.save()
							print("💾 Saved a new sent message to \(toUserNum)")
							if meshLoggingEnabled { MeshLogger.log("💾 Saved a new sent message from \(connectedPeripheral.num) to \(toUserNum)") }
							success = true

						} catch {

							context!.rollback()

							let nsError = error as NSError
							print("🚫 Unresolved error \(nsError)")
						}
					}
				}

			} catch {

			}
		}
		return success
	}
}
