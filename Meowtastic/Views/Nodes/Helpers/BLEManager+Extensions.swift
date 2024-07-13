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
}
