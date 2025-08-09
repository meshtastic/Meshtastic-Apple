import SwiftUI
import CoreData

struct ConfigHeader<T>: View {
	@EnvironmentObject var accessoryManager: AccessoryManager

	let title: String
	let config: KeyPath<NodeInfoEntity, T?>
	let node: NodeInfoEntity?
	let onAppear: () -> Void

	var body: some View {
		if node != nil && node?.metadata == nil && node?.num ?? 0 != accessoryManager.activeDeviceNum ?? 0 {
			Text("There has been no response to a request for device metadata via PKC admin for this node.")
				.font(.callout)
				.foregroundColor(.orange)

		} else if node != nil && node?.num ?? 0 != accessoryManager.activeDeviceNum ?? 0 {
			// Let users know what is going on if they are using remote admin and don't have the config yet
			let expiration = node?.sessionExpiration ?? Date()
			if node?[keyPath: config] == nil  || expiration < node?.sessionExpiration ?? Date() {
				Text("\(title) config data was requested via PKC admin but no response has been returned from the remote node.")
					.font(.callout)
					.foregroundColor(.orange)
			} else {
				Text("Remote administration for: \(node?.user?.longName ?? "Unknown")")
					.onFirstAppear(onAppear)
					.font(.title3)
			}
		} else if node != nil && node?.num ?? 0 == accessoryManager.activeDeviceNum ?? -1 {
			Text("Configuration for: \(node?.user?.longName ?? "Unknown")")
				.onFirstAppear(onAppear)
		} else {
			Text("Please connect to a radio to configure settings.")
				.font(.callout)
				.foregroundColor(.orange)
		}
	}
}
