import Foundation

final class ConnectedDevice: ObservableObject, Equatable {
	@Published
	var device: Device?

	static func == (lhs: ConnectedDevice, rhs: ConnectedDevice) -> Bool {
		lhs.device?.id == rhs.device?.id
	}

	func getConnectedDevice() -> Device? {
		guard let device, device.peripheral.state == .connected else {
			return nil
		}

		return device
	}

	func clear() {
		self.device = nil
	}
}
