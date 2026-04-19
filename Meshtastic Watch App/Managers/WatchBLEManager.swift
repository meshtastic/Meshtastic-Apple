//
//  WatchBLEManager.swift
//  Meshtastic Watch App
//
//  Copyright(c) Meshtastic 2025.
//

import Foundation
import CoreBluetooth
import MeshtasticProtobufs
import os

// MARK: - Meshtastic BLE UUIDs (same as the main app)
private let meshtasticServiceUUID  = CBUUID(string: "6BA1B218-15A8-461F-9FA8-5DCAE273EAFD")
private let toRadioUUID            = CBUUID(string: "F75C76D2-129E-4DAD-A1DD-7866124401E7")
private let fromRadioUUID          = CBUUID(string: "2C55E69E-4993-11ED-B878-0242AC120002")
private let fromNumUUID            = CBUUID(string: "ED9DA18C-A800-4F66-A670-AA7547E34453")

/// Standalone BLE manager that lets the watch connect directly to a
/// Meshtastic radio without relying on the paired iPhone.
///
/// It discovers Meshtastic peripherals, connects, requests the node
/// database, and keeps the `nodes` dictionary up-to-date as position
/// packets arrive.
@MainActor
final class WatchBLEManager: NSObject, ObservableObject {

	// MARK: - Published state

	/// Discovered but not-yet-connected peripherals.
	@Published var discoveredDevices: [DiscoveredDevice] = []

	/// All mesh nodes we know about, keyed by node number.
	@Published var nodes: [UInt32: MeshNode] = [:]

	/// Current connection state.
	@Published var connectionState: WatchConnectionState = .disconnected

	/// Name of the connected peripheral (if any).
	@Published var connectedDeviceName: String?

	/// Whether the central manager is currently scanning.
	@Published var isScanning = false

	// MARK: - Internal state

	private let logger = Logger(subsystem: "gvh.MeshtasticClient.watchkitapp", category: "🛜 BLE")
	private var centralManager: CBCentralManager!
	private var connectedPeripheral: CBPeripheral?
	private var toRadioCharacteristic: CBCharacteristic?
	private var fromRadioCharacteristic: CBCharacteristic?
	private var fromNumCharacteristic: CBCharacteristic?

	/// Our own node number, learned from `MyNodeInfo`.
	private var myNodeNum: UInt32?

	/// Nonce we send in the wantConfig request so we can identify the
	/// `configCompleteId` response.
	private let wantConfigNonce: UInt32 = 69421 // matches NONCE_ONLY_DB

	// MARK: - Lifecycle

	override init() {
		super.init()
		centralManager = CBCentralManager(delegate: self, queue: nil)
	}

	// MARK: - Public API

	func startScanning() {
		guard centralManager.state == .poweredOn else {
			logger.warning("Cannot scan – Bluetooth not powered on (\(self.centralManager.state.rawValue))")
			return
		}
		logger.info("Starting BLE scan for Meshtastic devices")
		discoveredDevices.removeAll()
		centralManager.scanForPeripherals(withServices: [meshtasticServiceUUID],
										  options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
		isScanning = true
	}

	func stopScanning() {
		centralManager.stopScan()
		isScanning = false
	}

	func connect(to device: DiscoveredDevice) {
		stopScanning()
		connectionState = .connecting
		connectedDeviceName = device.name
		logger.info("Connecting to \(device.name, privacy: .public)")
		centralManager.connect(device.peripheral, options: nil)
	}

	func disconnect() {
		if let peripheral = connectedPeripheral {
			centralManager.cancelPeripheralConnection(peripheral)
		}
		cleanup()
	}

	// MARK: - Helpers

	private func cleanup() {
		connectedPeripheral = nil
		toRadioCharacteristic = nil
		fromRadioCharacteristic = nil
		fromNumCharacteristic = nil
		connectionState = .disconnected
		connectedDeviceName = nil
		myNodeNum = nil
	}

	/// Send a `ToRadio` protobuf to the connected radio.
	private func send(_ message: ToRadio) {
		guard let peripheral = connectedPeripheral,
			  let characteristic = toRadioCharacteristic,
			  let data = try? message.serializedData() else {
			logger.error("Cannot send – not connected or characteristic missing")
			return
		}
		let writeType: CBCharacteristicWriteType =
			characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
		peripheral.writeValue(data, for: characteristic, type: writeType)
	}

	/// Request the full node database from the radio.
	private func requestNodeDatabase() {
		var toRadio = ToRadio()
		toRadio.wantConfigID = wantConfigNonce
		send(toRadio)
		logger.info("Sent wantConfigID=\(self.wantConfigNonce)")
	}

	/// Read (drain) packets from the FROMRADIO characteristic until an empty
	/// response is received.
	private func drainFromRadio() {
		guard let peripheral = connectedPeripheral,
			  let characteristic = fromRadioCharacteristic else { return }
		peripheral.readValue(for: characteristic)
	}

	// MARK: - Packet handling

	private func handleFromRadio(_ data: Data) {
		guard !data.isEmpty else { return }
		guard let fromRadio = try? FromRadio(serializedBytes: data) else {
			logger.error("Failed to decode FromRadio packet (\(data.count) bytes)")
			return
		}

		switch fromRadio.payloadVariant {
		case .myInfo(let myInfo):
			myNodeNum = myInfo.myNodeNum
			logger.info("My node num: \(myInfo.myNodeNum)")

		case .nodeInfo(let nodeInfo):
			upsertNode(from: nodeInfo)

		case .packet(let meshPacket):
			handleMeshPacket(meshPacket)

		case .configCompleteID(let id):
			logger.info("Config complete (nonce=\(id))")
			connectionState = .connected

		default:
			break
		}
	}

	private func handleMeshPacket(_ packet: MeshPacket) {
		guard packet.hasDecoded else { return }
		let decoded = packet.decoded

		switch decoded.portnum {
		case .positionApp:
			if let position = try? Position(serializedBytes: decoded.payload) {
				upsertPosition(from: packet.from, position: position)
			}
		case .nodeInfoApp:
			if let user = try? User(serializedBytes: decoded.payload) {
				upsertUser(from: packet.from, user: user)
			}
		default:
			break
		}
	}

	// MARK: - Node management

	private func upsertNode(from nodeInfo: NodeInfo) {
		let num = nodeInfo.num
		var node = nodes[num] ?? MeshNode(num: num, longName: "Node \(String(num, radix: 16))", shortName: String(String(num, radix: 16).suffix(4)))

		if nodeInfo.hasUser {
			node.longName = nodeInfo.user.longName
			node.shortName = nodeInfo.user.shortName
		}
		if nodeInfo.hasPosition, nodeInfo.position.latitudeI != 0, nodeInfo.position.longitudeI != 0 {
			node.latitude = Double(nodeInfo.position.latitudeI) / 1e7
			node.longitude = Double(nodeInfo.position.longitudeI) / 1e7
			node.altitude = nodeInfo.position.altitude
			node.lastPositionTime = Date(timeIntervalSince1970: TimeInterval(nodeInfo.position.time))
		}
		if nodeInfo.lastHeard > 0 {
			node.lastHeard = Date(timeIntervalSince1970: TimeInterval(nodeInfo.lastHeard))
		}
		node.snr = nodeInfo.snr
		nodes[num] = node
	}

	private func upsertPosition(from nodeNum: UInt32, position: Position) {
		guard position.latitudeI != 0, position.longitudeI != 0 else { return }
		var node = nodes[nodeNum] ?? MeshNode(num: nodeNum, longName: "Node \(String(nodeNum, radix: 16))", shortName: String(String(nodeNum, radix: 16).suffix(4)))
		node.latitude = Double(position.latitudeI) / 1e7
		node.longitude = Double(position.longitudeI) / 1e7
		node.altitude = position.altitude
		node.lastPositionTime = Date()
		node.lastHeard = Date()
		nodes[nodeNum] = node
	}

	private func upsertUser(from nodeNum: UInt32, user: User) {
		var node = nodes[nodeNum] ?? MeshNode(num: nodeNum, longName: user.longName, shortName: user.shortName)
		node.longName = user.longName
		node.shortName = user.shortName
		node.lastHeard = Date()
		nodes[nodeNum] = node
	}
}

// MARK: - DiscoveredDevice
struct DiscoveredDevice: Identifiable {
	let id: UUID
	let peripheral: CBPeripheral
	let name: String
	let rssi: Int
}

// MARK: - ConnectionState
enum WatchConnectionState: Equatable {
	case disconnected
	case connecting
	case connected
}

// MARK: - CBCentralManagerDelegate
extension WatchBLEManager: @preconcurrency CBCentralManagerDelegate {

	nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
		Task { @MainActor in
			switch central.state {
			case .poweredOn:
				logger.info("Bluetooth powered on")
			case .poweredOff:
				logger.warning("Bluetooth powered off")
				cleanup()
			case .unauthorized:
				logger.warning("Bluetooth unauthorised")
			default:
				break
			}
		}
	}

	nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
									advertisementData: [String: Any], rssi RSSI: NSNumber) {
		Task { @MainActor in
			let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"
			if !discoveredDevices.contains(where: { $0.peripheral.identifier == peripheral.identifier }) {
				let device = DiscoveredDevice(id: peripheral.identifier, peripheral: peripheral, name: name, rssi: RSSI.intValue)
				discoveredDevices.append(device)
				logger.info("Discovered \(name, privacy: .public) RSSI=\(RSSI.intValue)")
			}
		}
	}

	nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
		Task { @MainActor in
			logger.info("Connected to \(peripheral.name ?? "Unknown", privacy: .public)")
			connectedPeripheral = peripheral
			peripheral.delegate = self
			peripheral.discoverServices([meshtasticServiceUUID])
		}
	}

	nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
		Task { @MainActor in
			logger.error("Failed to connect: \(error?.localizedDescription ?? "unknown", privacy: .public)")
			cleanup()
		}
	}

	nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
		Task { @MainActor in
			logger.info("Disconnected from \(peripheral.name ?? "Unknown", privacy: .public)")
			cleanup()
		}
	}
}

// MARK: - CBPeripheralDelegate
extension WatchBLEManager: @preconcurrency CBPeripheralDelegate {

	nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
		Task { @MainActor in
			guard error == nil, let services = peripheral.services else {
				logger.error("Service discovery error: \(error?.localizedDescription ?? "nil", privacy: .public)")
				return
			}
			for service in services where service.uuid == meshtasticServiceUUID {
				peripheral.discoverCharacteristics([toRadioUUID, fromRadioUUID, fromNumUUID], for: service)
			}
		}
	}

	nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
		Task { @MainActor in
			guard error == nil, let characteristics = service.characteristics else {
				logger.error("Characteristic discovery error: \(error?.localizedDescription ?? "nil", privacy: .public)")
				return
			}
			for characteristic in characteristics {
				switch characteristic.uuid {
				case toRadioUUID:
					toRadioCharacteristic = characteristic
				case fromRadioUUID:
					fromRadioCharacteristic = characteristic
				case fromNumUUID:
					fromNumCharacteristic = characteristic
					peripheral.setNotifyValue(true, for: characteristic)
				default:
					break
				}
			}
			if toRadioCharacteristic != nil && fromRadioCharacteristic != nil && fromNumCharacteristic != nil {
				logger.info("All characteristics discovered – requesting node database")
				requestNodeDatabase()
				drainFromRadio()
			}
		}
	}

	nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
		Task { @MainActor in
			guard error == nil else {
				logger.error("Value update error for \(characteristic.uuid): \(error!.localizedDescription, privacy: .public)")
				return
			}
			switch characteristic.uuid {
			case fromRadioUUID:
				if let data = characteristic.value, !data.isEmpty {
					handleFromRadio(data)
					// Continue draining
					drainFromRadio()
				}
			case fromNumUUID:
				// New data available – start draining
				drainFromRadio()
			default:
				break
			}
		}
	}

	nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
		Task { @MainActor in
			if let error {
				logger.error("Write error: \(error.localizedDescription, privacy: .public)")
			}
		}
	}
}
