import CoreBluetooth
import Foundation

extension BLEManager {
	var isNodeConnected: Bool {
		deviceConnected != nil
	}

	var connectedNodeName: String {
		if let name = deviceConnected?.shortName {
			return name
		}
		else {
			return "N/A"
		}
	}

	func peripheral(
		_ peripheral: CBPeripheral,
		didReadRSSI RSSI: NSNumber,
		error: (any Error)?
	) {
		let uuid = peripheral.identifier.uuidString

		// connected peripheral
		if uuid == deviceConnected.id {
			deviceConnected.rssi = RSSI.intValue
		}

		// some other peripheral
		let updatedPeripheralIndex = devices.firstIndex(where: { peripheral in
			peripheral.id == uuid
		})

		guard let updatedPeripheralIndex else {
			return
		}

		let old = devices[updatedPeripheralIndex]
		let new = Device(
			id: old.id,
			num: old.num,
			name: old.name,
			shortName: old.shortName,
			longName: old.longName,
			firmwareVersion: old.firmwareVersion,
			rssi: RSSI.intValue,
			lastUpdate: old.lastUpdate,
			peripheral: old.peripheral
		)
		devices[updatedPeripheralIndex] = new
	}
}
