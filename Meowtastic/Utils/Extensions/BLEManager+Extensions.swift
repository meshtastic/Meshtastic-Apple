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
		if peripheral.identifier.uuidString == connectedPeripheral.id {
			connectedPeripheral.rssi = RSSI.intValue
		}
	}
}
