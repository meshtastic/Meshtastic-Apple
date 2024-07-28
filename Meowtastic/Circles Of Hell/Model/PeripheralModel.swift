import Foundation
import CoreBluetooth

struct Peripheral: Identifiable {
	var id: String
	var num: Int64
	var name: String
	var shortName: String
	var longName: String
	var firmwareVersion: String
	var rssi: Int
	var lastUpdate: Date
	var peripheral: CBPeripheral

	func getSignalStrength() -> BLESignalStrength {
		if NSNumber(value: rssi).compare(NSNumber(-65)) == ComparisonResult.orderedDescending {
			return BLESignalStrength.strong
		} else if NSNumber(value: rssi).compare(NSNumber(-85)) == ComparisonResult.orderedDescending {
			return BLESignalStrength.normal
		} else {
			return BLESignalStrength.weak
		}
	}
}
