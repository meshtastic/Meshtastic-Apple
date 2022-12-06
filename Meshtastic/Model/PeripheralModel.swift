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

	init(id: String, num: Int64, name: String, shortName: String, longName: String, firmwareVersion: String, rssi: Int, lastUpdate: Date, peripheral: CBPeripheral) {
		self.id = id
		self.num = num
		self.name = name
		self.shortName = shortName
		self.longName = longName
		self.firmwareVersion = firmwareVersion
		self.rssi = rssi
		self.lastUpdate = lastUpdate
		self.peripheral = peripheral
	}
	
	func getSignalStrength() -> SignalStrength {
		if (NSNumber(value: rssi).compare(NSNumber(-65)) == ComparisonResult.orderedDescending) {
			return SignalStrength.strong
		}
		else if (NSNumber(value: rssi).compare(NSNumber(-85)) == ComparisonResult.orderedDescending) {
			return SignalStrength.normal
		}
		else {
			return SignalStrength.weak
		}
	}
}
