import CoreBluetooth
import Foundation

struct Device: Identifiable, Equatable {
	var id: String
	var num: Int64
	var name: String
	var shortName: String
	var longName: String
	var firmwareVersion: String
	var rssi: Int
	var lastUpdate: Date
	var peripheral: CBPeripheral

	static func == (lhs: Device, rhs: Device) -> Bool {
		lhs.id == rhs.id
	}

	func getSignalStrength() -> BLESignalStrength {
		if rssi > -65 {
			return BLESignalStrength.strong
		}
		else if rssi > -85 {
			return BLESignalStrength.normal
		}
		else {
			return BLESignalStrength.weak
		}
	}
}