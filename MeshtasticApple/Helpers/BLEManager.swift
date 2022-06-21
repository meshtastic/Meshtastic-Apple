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
	
	var userSettings: UserSettings?

	private var centralManager: CBCentralManager!

	@Published var peripherals = [Peripheral]()

    @Published var connectedPeripheral: Peripheral!
    @Published var lastConnectionError: String
	@Published var lastConnnectionVersion: String

	@Published var isSwitchedOn: Bool = false
	@Published var isScanning: Bool = false
	@Published var isConnected: Bool = false
	
	/// Used to make sure we never get foold by old BLE packets
	private var configNonce: UInt32 = 1

	var timeoutTimer: Timer?
	var timeoutTimerCount = 0
	
	var positionTimer: Timer?

    let broadcastNodeNum: UInt32 = 4294967295

    /* Meshtastic Service Details */
    var TORADIO_characteristic: CBCharacteristic!
    var FROMRADIO_characteristic: CBCharacteristic!
    var FROMNUM_characteristic: CBCharacteristic!

    let meshtasticServiceCBUUID = CBUUID(string: "0x6BA1B218-15A8-461F-9FA8-5DCAE273EAFD")
    let TORADIO_UUID = CBUUID(string: "0xF75C76D2-129E-4DAD-A1DD-7866124401E7")
    let FROMRADIO_UUID = CBUUID(string: "0x8BA2BCC2-EE02-4A55-A531-C525C5E454D5")
    let FROMNUM_UUID = CBUUID(string: "0xED9DA18C-A800-4F66-A670-AA7547E34453")

	private var meshLoggingEnabled: Bool = false
	let meshLog = documentsFolder.appendingPathComponent("meshlog.txt")

    // MARK: init BLEManager
    override init() {

		self.meshLoggingEnabled = UserDefaults.standard.object(forKey: "meshActivityLog") as? Bool ?? false
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
			self.isConnected = false

			self.lastConnectionError = "🚨 BLE Connection Timeout after making \(timeoutTimerCount) attempts to connect to \(name)."

			if meshLoggingEnabled { MeshLogger.log(self.lastConnectionError + " This can occur when a device has been taken out of BLE range, or if a device is already connected to another phone, tablet or computer.") }

			self.timeoutTimerCount = 0
			self.timeoutTimer?.invalidate()

		} else {

			if meshLoggingEnabled { MeshLogger.log("🚨 BLE Connecting 2 Second Timeout Timer Fired \(timeoutTimerCount) Time(s): \(name)") }
		}
	}

    // Connect to a specific peripheral
    func connectTo(peripheral: CBPeripheral) {

		if meshLoggingEnabled { MeshLogger.log("✅ BLE Connecting: \(peripheral.name ?? "Unknown")") }

        stopScanning()

		if self.connectedPeripheral != nil {
			
			if meshLoggingEnabled { MeshLogger.log("ℹ️ BLE Disconnecting from: \(self.connectedPeripheral.name) to connect to \(peripheral.name ?? "Unknown")") }
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
		self.isConnected = false
    }

    // Called each time a peripheral is discovered
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {

        var peripheralName: String = peripheral.name ?? "Unknown"
		let last4Code: String = (peripheral.name != nil ? String(peripheral.name!.suffix(4)) : "Unknown")

        if let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            peripheralName = name
        }

		let newPeripheral = Peripheral(id: peripheral.identifier.uuidString, num: 0, name: peripheralName, shortName: last4Code, longName: peripheralName, lastFourCode: last4Code, firmwareVersion: "Unknown", rssi: RSSI.intValue, bitrate: nil, channelUtilization: nil, airTime: nil, lastUpdate: Date(), subscribed: false, peripheral: peripheral)
		let peripheralIndex = peripherals.firstIndex(where: { $0.id == newPeripheral.id })

		if peripheralIndex != nil && newPeripheral.peripheral.state != CBPeripheralState.connected {

			peripherals[peripheralIndex!] = newPeripheral
			peripherals.remove(at: peripheralIndex!)
			peripherals.append(newPeripheral)

		} else {
			
			if newPeripheral.peripheral.state != CBPeripheralState.connected {

				peripherals.append(newPeripheral)
				print("ℹ️ Adding peripheral: \(peripheralName)")
			}
		}
		
		let today = Date()
		let visibleDuration = Calendar.current.date(byAdding: .second, value: -2, to: today)!
		peripherals.removeAll(where: { $0.lastUpdate <= visibleDuration})
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

		// Discover Services
        peripheral.discoverServices([meshtasticServiceCBUUID])
		if meshLoggingEnabled { MeshLogger.log("✅ BLE Connected: \(peripheral.name ?? "Unknown")") }
		
    }

	// Called when a Peripheral fails to connect
	func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {

		if meshLoggingEnabled { MeshLogger.log("🚫 BLE Failed to Connect: \(peripheral.name ?? "Unknown")") }
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
					self.connectTo(peripheral: peripheral)
				}
				
            } else if errorCode == 7 { // CBError.Code.peripheralDisconnected The specified device has disconnected from us.

                // Seems to be what is received when a tbeam sleeps, immediately recconnecting does not work.
				lastConnectionError = e.localizedDescription

				if meshLoggingEnabled { MeshLogger.log("🚨 BLE Disconnected: \(peripheral.name ?? "Unknown") Error Code: \(errorCode) Error: \(e.localizedDescription)") }
				
            } else if errorCode == 14 { // Peer removed pairing information

                // Forgetting and reconnecting seems to be necessary so we need to show the user an error telling them to do that
				lastConnectionError = "🚨 \(e.localizedDescription) This error usually cannot be fixed without forgetting the device unders Settings > Bluetooth and re-connecting to the radio."

				if meshLoggingEnabled { MeshLogger.log("🚨 BLE Disconnected: \(peripheral.name ?? "Unknown") Error Code: \(errorCode) Error: \(lastConnectionError)") }
				
            } else {

				lastConnectionError = e.localizedDescription

				if meshLoggingEnabled { MeshLogger.log("🚨 BLE Disconnected: \(peripheral.name ?? "Unknown") Error Code: \(errorCode) Error: \(e.localizedDescription)") }
			}
        } else {

            // Disconnected without error which indicates user intent to disconnect
			// Happens when swiping to disconnect
			if meshLoggingEnabled { MeshLogger.log("ℹ️ BLE Disconnected: \(peripheral.name ?? "Unknown"): User Initiated Disconnect") }
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
			
				if meshLoggingEnabled { MeshLogger.log("✅ BLE Service for Meshtastic discovered by \(peripheral.name ?? "Unknown")") }
                //peripheral.discoverCharacteristics(nil, for: service)
                peripheral.discoverCharacteristics([TORADIO_UUID, FROMRADIO_UUID, FROMNUM_UUID], for: service)
            }
        }
    }
	
	func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
		
		print(invalidatedServices)
	}

    // MARK: Discover Characteristics Event
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
		
        if let e = error {

			if meshLoggingEnabled { MeshLogger.log("🚫 BLE didDiscoverCharacteristicsFor error by \(peripheral.name ?? "Unknown") \(e)") }
        }

        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {

			switch characteristic.uuid {
			case TORADIO_UUID:
				
				if meshLoggingEnabled { MeshLogger.log("✅ BLE did discover TORADIO characteristic for Meshtastic by \(peripheral.name ?? "Unknown")") }
				TORADIO_characteristic = characteristic
				var toRadio: ToRadio = ToRadio()
				configNonce += 1
				toRadio.wantConfigID = configNonce

				let binaryData: Data = try! toRadio.serializedData()
				peripheral.writeValue(binaryData, for: characteristic, type: .withResponse)

			case FROMRADIO_UUID:
				
				if meshLoggingEnabled { MeshLogger.log("✅ BLE did discover FROMRADIO characteristic for Meshtastic by \(peripheral.name ?? "Unknown")") }
				FROMRADIO_characteristic = characteristic
				peripheral.readValue(for: FROMRADIO_characteristic)

			case FROMNUM_UUID:
				
				if meshLoggingEnabled { MeshLogger.log("✅ BLE did discover FROMNUM (Notify) characteristic for Meshtastic by \(peripheral.name ?? "Unknown")") }
				FROMNUM_characteristic = characteristic
				peripheral.setNotifyValue(true, for: characteristic)

			default:
				break
			}
		}
    }

	func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {

		if let errorText = error?.localizedDescription {

			if meshLoggingEnabled { MeshLogger.log("🚫 didUpdateNotificationStateFor error: \(errorText)") }
		}
	}

    // MARK: Data Read / Update Characteristic Event
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
       
		if let e = error {
			
			print("🚫 didUpdateValueFor Characteristic error \(e)")

			let errorCode = (e as NSError).code
			
			if errorCode == 5 { // CBATTErrorDomain Code=5 "Authentication is insufficient."

				// BLE Pin connection error
				lastConnectionError = "🚫 BLE \(e.localizedDescription) Please try connecting again and check the PIN carefully."
				if meshLoggingEnabled { MeshLogger.log("🚫 BLE \(e.localizedDescription) Please try connecting again and check the PIN carefully.") }
				self.centralManager?.cancelPeripheralConnection(peripheral)

			}
			if errorCode == 15 { // CBATTErrorDomain Code=15 "Encryption is insufficient."

				// BLE Pin connection error
				lastConnectionError = "🚫 BLE \(e.localizedDescription) This may be a Meshtastic Firmware bug affecting BLE 4.0 devices."
				if meshLoggingEnabled { MeshLogger.log("🚫 BLE \(e.localizedDescription) Please try connecting again. You may need to forget the device under Settings > General > Bluetooth.") }
				self.centralManager?.cancelPeripheralConnection(peripheral)

			}
        }

        switch characteristic.uuid {

		case FROMRADIO_UUID:
			
			if characteristic.value == nil || characteristic.value!.isEmpty {
				return
			}

			var decodedInfo = FromRadio()
			decodedInfo = try! FromRadio(serializedData: characteristic.value!)

			switch decodedInfo.packet.decoded.portnum {
				
				// Handle Any local only packets we get over BLE
				case .unknownApp:
				
					if decodedInfo.myInfo.myNodeNum	!= 0 {
						
						let myInfo = myInfoPacket(myInfo: decodedInfo.myInfo, meshLogging: meshLoggingEnabled, context: context!)
						
						if myInfo != nil {
							
							self.connectedPeripheral.bitrate = myInfo!.bitrate
							self.connectedPeripheral.num = myInfo!.myNodeNum
							lastConnnectionVersion = myInfo?.firmwareVersion ??  myInfo!.firmwareVersion ?? "Unknown"
							self.connectedPeripheral.firmwareVersion = myInfo!.firmwareVersion ?? "Unknown"
							self.connectedPeripheral.name = myInfo!.bleName ?? "Unknown"
							
						}
						
					} else if decodedInfo.nodeInfo.num != 0 {

						let nodeInfo = nodeInfoPacket(nodeInfo: decodedInfo.nodeInfo, meshLogging: meshLoggingEnabled, context: context!)
						
						if nodeInfo != nil {
							
							self.connectedPeripheral.channelUtilization = decodedInfo.nodeInfo.deviceMetrics.channelUtilization
							self.connectedPeripheral.airTime = decodedInfo.nodeInfo.deviceMetrics.airUtilTx

							if self.connectedPeripheral != nil && self.connectedPeripheral.num == nodeInfo!.num {

								if nodeInfo!.user != nil {
									
									connectedPeripheral.name  = nodeInfo!.user!.longName ?? "Unknown"
									connectedPeripheral.shortName = nodeInfo!.user!.shortName ?? "?????"
									connectedPeripheral.longName = nodeInfo!.user!.longName ?? "Unknown"
								}
							}
						}
						
					} else if decodedInfo.config.isInitialized {
							
						localConfig(config: decodedInfo.config, meshlogging: meshLoggingEnabled, context: context!, nodeNum: self.connectedPeripheral.num, nodeLongName: self.connectedPeripheral.longName)
						
					} else {
						
						if decodedInfo.configCompleteID == 0 {
						
							if meshLoggingEnabled { MeshLogger.log("ℹ️ MESH PACKET received for Unknown App UNHANDLED \(try! decodedInfo.packet.jsonString())") }
						}
					}
				case .textMessageApp:
					textMessageAppPacket(packet: decodedInfo.packet, connectedNode: (self.connectedPeripheral != nil ? connectedPeripheral.num : 0), meshLogging: meshLoggingEnabled, context: context!)
				case .remoteHardwareApp:
					if meshLoggingEnabled { MeshLogger.log("ℹ️ MESH PACKET received for Remote Hardware App UNHANDLED \(try! decodedInfo.packet.jsonString())") }
				case .positionApp:
					positionPacket(packet: decodedInfo.packet, meshLogging: meshLoggingEnabled, context: context!)
			    case .waypointApp:
					if meshLoggingEnabled { MeshLogger.log("ℹ️ MESH PACKET received for Waypoint App UNHANDLED \(try! decodedInfo.packet.jsonString())") }
				case .nodeinfoApp:
					nodeInfoAppPacket(packet: decodedInfo.packet, meshLogging: meshLoggingEnabled, context: context!)
				case .routingApp:
					routingPacket(packet: decodedInfo.packet, meshLogging: meshLoggingEnabled, context: context!)
				case .adminApp:
					adminAppPacket(packet: decodedInfo.packet, meshLogging: meshLoggingEnabled, context: context!)
				case .replyApp:
					if meshLoggingEnabled { MeshLogger.log("ℹ️ MESH PACKET received for Reply App UNHANDLED \(try! decodedInfo.packet.jsonString())") }
				case .ipTunnelApp:
					if meshLoggingEnabled { MeshLogger.log("ℹ️ MESH PACKET received for IP Tunnel App UNHANDLED \(try! decodedInfo.packet.jsonString())") }
				case .serialApp:
					if meshLoggingEnabled { MeshLogger.log("ℹ️ MESH PACKET received for Serial App UNHANDLED \(try! decodedInfo.packet.jsonString())") }
				case .storeForwardApp:
					if meshLoggingEnabled { MeshLogger.log("ℹ️ MESH PACKET received for Store Forward App UNHANDLED \(try! decodedInfo.packet.jsonString())") }
				case .rangeTestApp:
					if meshLoggingEnabled { MeshLogger.log("ℹ️ MESH PACKET received for Range Test App UNHANDLED \(try! decodedInfo.packet.jsonString())") }
				case .telemetryApp:
					telemetryPacket(packet: decodedInfo.packet, meshLogging: meshLoggingEnabled, context: context!)
				case .textMessageCompressedApp:
					if meshLoggingEnabled { MeshLogger.log("ℹ️ MESH PACKET received for Text Message Compressed App UNHANDLED \(try! decodedInfo.packet.jsonString())") }
				case .zpsApp:
					if meshLoggingEnabled { MeshLogger.log("ℹ️ MESH PACKET received for ZPS App UNHANDLED \(try! decodedInfo.packet.jsonString())") }
				case .privateApp:
					if meshLoggingEnabled { MeshLogger.log("ℹ️ MESH PACKET received for Private App UNHANDLED \(try! decodedInfo.packet.jsonString())") }
				case .atakForwarder:
					if meshLoggingEnabled { MeshLogger.log("ℹ️ MESH PACKET received for ATAK Forwarder App UNHANDLED \(try! decodedInfo.packet.jsonString())") }
				case .UNRECOGNIZED(_):
					if meshLoggingEnabled { MeshLogger.log("ℹ️ MESH PACKET received for Other App UNHANDLED \(try! decodedInfo.packet.jsonString())") }
				case .max:
					print("MAX PORT NUM OF 511")
			}
			
			// MARK: Check for an All / Broadcast User
			let fetchBCUserRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "UserEntity")
			fetchBCUserRequest.predicate = NSPredicate(format: "num == %lld", Int64(broadcastNodeNum))
			
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

			// MARK: Share Location Position Update Timer
			// Use context to pass the radio name with the timer
			// Use a RunLoop to prevent the timer from running on the main UI thread
			if userSettings?.provideLocation ?? false {
				
				if self.positionTimer != nil {
					self.positionTimer!.invalidate()
				}
				let context = ["name": "@\(peripheral.name ?? "Unknown")"]
				self.positionTimer = Timer.scheduledTimer(timeInterval: TimeInterval((userSettings?.provideLocationInterval ?? 900)), target: self, selector: #selector(positionTimerFired), userInfo: context, repeats: true)
				RunLoop.current.add(self.positionTimer!, forMode: .common)
			}

			if decodedInfo.configCompleteID != 0 && decodedInfo.configCompleteID == configNonce {

				if meshLoggingEnabled { MeshLogger.log("🤜 BLE Config Complete Packet Id: \(decodedInfo.configCompleteID)") }
				self.connectedPeripheral.subscribed = true
				peripherals.removeAll(where: { $0.peripheral.state == CBPeripheralState.disconnected })
				// Config conplete returns so we don't read the characteristic again
				return
			}

		case FROMNUM_UUID :
		
			print("🗞️ BLE FROMNUM (Notify) characteristic, value will be read next")

		default:
			
			print("🚨 Unhandled Characteristic UUID: \(characteristic.uuid)")
        }
		
		// Either Read the config complete value or from num notify value
		peripheral.readValue(for: FROMRADIO_characteristic)
	}

	public func sendMessage(message: String, toUserNum: Int64, isEmoji: Bool, replyID: Int64) -> Bool {
		
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
					newMessage.isEmoji = isEmoji
					
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
					meshPacket.id = UInt32(newMessage.messageId)
					meshPacket.to = UInt32(toUserNum)
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

					if meshLoggingEnabled { MeshLogger.log("📲 New messageId \(newMessage.messageId) sent to \(newMessage.toUser?.longName! ?? "Unknown")") }

					if connectedPeripheral!.peripheral.state == CBPeripheralState.connected {
						
						connectedPeripheral.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
						do {

							try context!.save()
							if meshLoggingEnabled { MeshLogger.log("💾 Saved a new sent message from \(connectedPeripheral.num) to \(toUserNum)") }
							success = true

						} catch {

							context!.rollback()

							let nsError = error as NSError
							if meshLoggingEnabled { MeshLogger.log("💥 Unresolved Core Data error in Send Message Function it is likely that your database is corrupted deleting and re-installing the app should clear the corrupted data. Error: \(nsError)") }
						}
					}
				}

			} catch {

			}
		}
		return success
	}
	
	public func sendPosition(destNum: Int64,  wantResponse: Bool) -> Bool {
		
		var success = false
		
		let fromNodeNum = connectedPeripheral.num
		
		if fromNodeNum <= 0 || (LocationHelper.currentLocation.latitude == LocationHelper.DefaultLocation.latitude && LocationHelper.currentLocation.longitude == LocationHelper.DefaultLocation.longitude) {
			
			return false
		}
		
		let fetchNode: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
		fetchNode.predicate = NSPredicate(format: "num == %lld", fromNodeNum)

		do {

			let fetchedNode = try context?.fetch(fetchNode) as! [NodeInfoEntity]
			

			if fetchedNode.count == 1 {
				
				var positionPacket = Position()
				positionPacket.latitudeI = Int32(LocationHelper.currentLocation.latitude * 1e7)
				positionPacket.longitudeI = Int32(LocationHelper.currentLocation.longitude * 1e7)
				positionPacket.time = UInt32(LocationHelper.currentTimestamp.timeIntervalSince1970)
				positionPacket.altitude = Int32(LocationHelper.currentAltitude)
				positionPacket.groundSpeed = UInt32(LocationHelper.currentSpeed)
				positionPacket.groundTrack = UInt32(LocationHelper.currentHeading)
				
				var meshPacket = MeshPacket()
				meshPacket.to = UInt32(destNum)
				meshPacket.from	= 0 // Send 0 as from from phone to device to avoid warning about client trying to set node num
				meshPacket.wantAck = wantResponse
				
				var dataMessage = DataMessage()
				dataMessage.payload = try! positionPacket.serializedData()
				dataMessage.portnum = PortNum.positionApp
				
				meshPacket.decoded = dataMessage

				var toRadio: ToRadio!
				toRadio = ToRadio()
				toRadio.packet = meshPacket
				let binaryData: Data = try! toRadio.serializedData()
				
				if meshLoggingEnabled { MeshLogger.log("📍 Sent a Position Packet from the Apple device GPS to node: \(fromNodeNum)") }
				
				if connectedPeripheral!.peripheral.state == CBPeripheralState.connected {
					
					connectedPeripheral.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
					success = true

				}
			}
			
		} catch {
			success = false
		}
		
		return success
	}
	
	@objc func positionTimerFired(timer: Timer) {
		
		// Check for connected node
		if connectedPeripheral != nil {

			// Send a position out to the mesh if "share location with the mesh" is enabled in settings
			if userSettings!.provideLocation {
				
				let success = sendPosition(destNum: connectedPeripheral.num, wantResponse: false)
				if !success {
					
					print("Failed to send positon to device")
					
				}
			}
		}
	}
	
	public func sendShutdown(destNum: Int64,  wantResponse: Bool) -> Bool {
		
		var adminPacket = AdminMessage()
		adminPacket.shutdownSeconds = 10
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(connectedPeripheral.num)
		meshPacket.from	= 0 //UInt32(connectedPeripheral.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = wantResponse

		meshPacket.hopLimit = 0
		
		var dataMessage = DataMessage()
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		
		meshPacket.decoded = dataMessage

		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket

		let binaryData: Data = try! toRadio.serializedData()
		
		if connectedPeripheral!.peripheral.state == CBPeripheralState.connected {
			
			connectedPeripheral.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
			
			return true
		}
		
		return false
	}
	
	public func sendReboot(destNum: Int64,  wantResponse: Bool) -> Bool {
		
		var adminPacket = AdminMessage()
		adminPacket.rebootSeconds = 10
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(connectedPeripheral.num)
		meshPacket.from	= 0 //UInt32(connectedPeripheral.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = wantResponse
		meshPacket.hopLimit = 0
		
		var dataMessage = DataMessage()
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		
		meshPacket.decoded = dataMessage

		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket

		let binaryData: Data = try! toRadio.serializedData()
		
		if connectedPeripheral!.peripheral.state == CBPeripheralState.connected {
			
			connectedPeripheral.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
			
			return true
		}
		
		return false
	}
	
	public func sendFactoryReset(destNum: Int64,  wantResponse: Bool) -> Bool {
		
		var deviceConfig = Config.DeviceConfig()
		deviceConfig.factoryReset = true
		
		var adminPacket = AdminMessage()
		adminPacket.setConfig.device = deviceConfig
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(connectedPeripheral.num)
		meshPacket.from	= 0 //UInt32(connectedPeripheral.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = wantResponse
		meshPacket.hopLimit = 0
		
		var dataMessage = DataMessage()
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		
		meshPacket.decoded = dataMessage

		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket

		let binaryData: Data = try! toRadio.serializedData()
		
		if connectedPeripheral!.peripheral.state == CBPeripheralState.connected {
			
			connectedPeripheral.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
			
			return true
		}
		
		return false
	}
	
	public func saveDeviceConfig(config: Config.DeviceConfig,  destNum: Int64,  wantResponse: Bool) -> Bool {
		
		var adminPacket = AdminMessage()
		adminPacket.setConfig.device = config
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(connectedPeripheral.num)
		meshPacket.from	= 0 //UInt32(connectedPeripheral.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = wantResponse
		meshPacket.hopLimit = 0
		
		var dataMessage = DataMessage()
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		
		meshPacket.decoded = dataMessage

		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket

		let binaryData: Data = try! toRadio.serializedData()
		
		if connectedPeripheral!.peripheral.state == CBPeripheralState.connected {
			
			connectedPeripheral.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
			
			return true
		}
		
		return false
	}
	
	public func saveDisplayConfig(config: Config.DisplayConfig,  destNum: Int64,  wantResponse: Bool) -> Bool {
		
		var adminPacket = AdminMessage()
		adminPacket.setConfig.display = config
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(connectedPeripheral.num)
		meshPacket.from	= 0 //UInt32(connectedPeripheral.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = wantResponse
		meshPacket.hopLimit = 0
		
		var dataMessage = DataMessage()
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		
		meshPacket.decoded = dataMessage

		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket

		let binaryData: Data = try! toRadio.serializedData()
		
		if connectedPeripheral!.peripheral.state == CBPeripheralState.connected {
			
			connectedPeripheral.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
			
			return true
		}
		
		return false
	}
	
	public func saveLoRaConfig(config: Config.LoRaConfig,  destNum: Int64,  wantResponse: Bool) -> Bool {
		
		var adminPacket = AdminMessage()
		adminPacket.setConfig.lora = config
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(connectedPeripheral.num)
		meshPacket.from	= 0 //UInt32(connectedPeripheral.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = wantResponse
		meshPacket.hopLimit = 0
		
		var dataMessage = DataMessage()
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		
		meshPacket.decoded = dataMessage

		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket

		let binaryData: Data = try! toRadio.serializedData()
		
		if connectedPeripheral!.peripheral.state == CBPeripheralState.connected {
			
			connectedPeripheral.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
			
			return true
		}
		
		return false
	}
	
	public func savePositionConfig(config: Config.PositionConfig,  destNum: Int64,  wantResponse: Bool) -> Bool {
		
		var adminPacket = AdminMessage()
		adminPacket.setConfig.position = config
		
		var meshPacket: MeshPacket = MeshPacket()
		meshPacket.to = UInt32(connectedPeripheral.num)
		meshPacket.from	= 0 //UInt32(connectedPeripheral.num)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority =  MeshPacket.Priority.reliable
		meshPacket.wantAck = wantResponse
		meshPacket.hopLimit = 0
		
		var dataMessage = DataMessage()
		dataMessage.payload = try! adminPacket.serializedData()
		dataMessage.portnum = PortNum.adminApp
		
		meshPacket.decoded = dataMessage

		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket

		let binaryData: Data = try! toRadio.serializedData()
		
		if connectedPeripheral!.peripheral.state == CBPeripheralState.connected {
			
			connectedPeripheral.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
			
			return true
		}
		
		return false
	}
}
