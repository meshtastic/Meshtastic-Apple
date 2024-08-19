import CoreBluetooth
import OSLog

extension CBPeripheral {
	public func readValue(for characteristic: CBCharacteristic?) {
		guard let characteristic else {
			Logger.app.error("Trying to read value from nil characteristic")
			return
		}

		self.readValue(for: characteristic)
	}

	public func writeValue(_ data: Data, for characteristic: CBCharacteristic?, type: CBCharacteristicWriteType) {
		guard let characteristic else {
			Logger.app.error("Trying to write value to nil characteristic")
			return
		}

		writeValue(data, for: characteristic, type: type)
	}
}
