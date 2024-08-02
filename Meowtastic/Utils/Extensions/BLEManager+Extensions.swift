import CoreBluetooth
import Foundation

extension BLEManager {
	var isNodeConnected: Bool {
		connectedPeripheral != nil
	}

	var connectedNodeName: String {
		if let name = connectedPeripheral?.shortName {
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
		if uuid == connectedPeripheral.id {
			connectedPeripheral.rssi = RSSI.intValue
		}

		// some other peripheral
		let updatedPeripheralIndex = peripherals.firstIndex(where: { peripheral in
			peripheral.id == uuid
		})

		guard let updatedPeripheralIndex else {
			return
		}

		let old = peripherals[updatedPeripheralIndex]
		let new = Peripheral(
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
		peripherals[updatedPeripheralIndex] = new
	}
}
