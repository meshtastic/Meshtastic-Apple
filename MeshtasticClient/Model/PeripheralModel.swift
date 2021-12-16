import Foundation
import CoreBluetooth

struct Peripheral: Identifiable {
	var id: String
	var name: String
	var shortName: String
	var longName: String
	var firmwareVersion: String
	var rssi: Int
	var subscribed: Bool
	var peripheral: CBPeripheral

	//var myInfo: MyInfoModel?

	init(id: String, name: String, shortName: String, longName: String, firmwareVersion: String, rssi: Int, subscribed: Bool, peripheral: CBPeripheral) {//, myInfo: MyInfoModel?) {
		self.id = id
		self.name = name
		self.shortName = shortName
		self.longName = longName
		self.firmwareVersion = firmwareVersion
		self.rssi = rssi
		self.subscribed = subscribed
		self.peripheral = peripheral
		//self.myInfo = myInfo
	}
}
