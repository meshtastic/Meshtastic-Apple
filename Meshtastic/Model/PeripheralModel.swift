import Foundation
import CoreBluetooth

struct Peripheral: Identifiable {
	var id: String
	var num: Int64
	var name: String
	var shortName: String
	var longName: String
	var lastFourCode: String
	var firmwareVersion: String
	var rssi: Int
	var bitrate: Float?
	var channelUtilization: Float?
	var airTime: Float?
	var maxChannels: Int32
	var lastUpdate: Date
	var subscribed: Bool
	var peripheral: CBPeripheral

	init(id: String, num: Int64, name: String, shortName: String, longName: String, lastFourCode: String, firmwareVersion: String, rssi: Int, bitrate: Float?, channelUtilization: Float?, airTime: Float?, maxChannels: Int32, lastUpdate: Date, subscribed: Bool, peripheral: CBPeripheral) {
		self.id = id
		self.num = num
		self.name = name
		self.shortName = shortName
		self.longName = longName
		self.lastFourCode = lastFourCode
		self.firmwareVersion = firmwareVersion
		self.rssi = rssi
		self.bitrate = bitrate
		self.channelUtilization = channelUtilization
		self.airTime = airTime
		self.maxChannels = maxChannels
		self.lastUpdate = lastUpdate
		self.subscribed = subscribed
		self.peripheral = peripheral
	}
}
