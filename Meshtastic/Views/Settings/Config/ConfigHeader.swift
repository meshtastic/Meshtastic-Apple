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
			Text("no_metadata_response".localized)
				.font(.callout)
				.foregroundColor(.orange)

		} else if node != nil && node?.num ?? 0 != bleManager.connectedPeripheral?.num ?? 0 {
			if node?[keyPath: config] == nil {
				Text(String(format: "config_data_requested".localized, title))
					.font(.callout)
					.foregroundColor(.orange)
			} else {
				Text(String(format: "remote_administration_for".localized, node?.user?.longName ?? "Unknown"))
					.font(.title3)
					.onAppear(perform: onAppear)
			}
		} else if node != nil && node?.num ?? 0 == bleManager.connectedPeripheral?.num ?? -1 {
			Text(String(format: "configuration_for".localized, node?.user?.longName ?? "Unknown"))
		} else {
			Text("connect_to_radio".localized)
				.font(.callout)
				.foregroundColor(.orange)
		}
	}
}

