import Foundation
import CoreBluetooth

struct Peripheral: Identifiable {
	var id: String
	var name: String
	var rssi: Int
	var subscribed: Bool
	var peripheral: CBPeripheral
	
	var myInfo: MyInfoModel?
	
	init(id: String, name: String, rssi: Int, subscribed: Bool, peripheral: CBPeripheral, myInfo: MyInfoModel?) {
		self.id = id
		self.name = name
		self.rssi = rssi
		self.subscribed = subscribed
		self.peripheral = peripheral
		self.myInfo = myInfo
	}
}
