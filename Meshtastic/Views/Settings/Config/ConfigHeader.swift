import SwiftUI
import SwiftData

struct ConfigHeader<T>: View {
	@EnvironmentObject var accessoryManager: AccessoryManager

	let title: String
	let config: KeyPath<NodeInfoEntity, T?>
	let node: NodeInfoEntity?
	let onAppear: () -> Void
	var onRetry: (() -> Void)? = nil

	var body: some View {
		let request = node.flatMap { accessoryManager.remoteAdminConfigTracker.latest(for: $0.num, kind: .request, section: title) }
		if let request, !request.isFinished {
			ProgressView("Requesting \(title) configuration…")
				.font(.callout)
		} else if let request, let result = request.result, result != .succeeded {
			VStack(spacing: 8) {
				Text(result == .timedOut ? "No response was received from the remote node." : "The configuration request failed.")
					.font(.callout)
					.foregroundColor(.red)
				if let onRetry {
					Button("Retry", action: onRetry)
						.environment(\.isEnabled, accessoryManager.isConnected && UserDefaults.enableAdministration)
				}
			}
		} else if node != nil && node?.metadata == nil && node?.num ?? 0 != accessoryManager.activeDeviceNum ?? 0 {
			Text("There has been no response to a request for device metadata via PKC admin for this node.")
				.font(.callout)
				.foregroundColor(.orange)

		} else if node != nil && node?.num ?? 0 != accessoryManager.activeDeviceNum ?? 0 {
			// Let users know what is going on if they are using remote admin and don't have the config yet
			if node?[keyPath: config] == nil || node?.hasLiveAdminSession != true {
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

#Preview {
	ConfigHeader(
		title: "Bluetooth Configuration",
		config: \NodeInfoEntity.bluetoothConfig,
		node: nil,
		onAppear: { }
	)
	.environmentObject(AccessoryManager.shared)
}
