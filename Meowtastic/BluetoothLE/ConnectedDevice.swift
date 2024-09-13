import CoreData
import Foundation

final class ConnectedDevice: ObservableObject, Equatable {
	@Published
	var device: Device?

	private let context: NSManagedObjectContext

	init(context: NSManagedObjectContext) {
		self.context = context
	}

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
