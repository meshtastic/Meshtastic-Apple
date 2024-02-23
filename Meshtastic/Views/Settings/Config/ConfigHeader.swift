import SwiftUI
import CoreData

struct ConfigHeader<T>: View {
	@EnvironmentObject var bleManager: BLEManager

	let title: String
	let config: KeyPath<NodeInfoEntity, T?>
	let node: NodeInfoEntity?
	let onAppear: () -> Void

	var body: some View {
		if node != nil && node?.metadata == nil && node?.num ?? 0 != bleManager.connectedPeripheral?.num ?? 0 {
			Text("There has been no response to a request for device metadata over the admin channel for this node.")
				.font(.callout)
				.foregroundColor(.orange)

		} else if node != nil && node?.num ?? 0 != bleManager.connectedPeripheral?.num ?? 0 {
			// Let users know what is going on if they are using remote admin and don't have the config yet
			if node?[keyPath: config] == nil {
				Text("\(title) config data was requested over the admin channel but no response has been returned from the remote node. You can check the status of admin message requests in the admin message log.")
					.font(.callout)
					.foregroundColor(.orange)
			} else {
				Text("Remote administration for: \(node?.user?.longName ?? "Unknown")")
					.font(.title3)
					.onAppear(perform: onAppear)
			}
		} else if node != nil && node?.num ?? 0 == bleManager.connectedPeripheral?.num ?? -1 {
			Text("Configuration for: \(node?.user?.longName ?? "Unknown")")
		} else {
			Text("Please connect to a radio to configure settings.")
				.font(.callout)
				.foregroundColor(.orange)
		}
	}
}
