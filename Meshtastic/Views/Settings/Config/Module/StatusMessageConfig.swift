//
//  StatusMessageConfig.swift
//  Meshtastic
//

import MeshtasticProtobufs
import OSLog
import SwiftUI

struct StatusMessageConfig: View {

	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var goBack
	let node: NodeInfoEntity?
	@State var hasChanges: Bool = false
	@State var nodeStatus: String = ""

	var body: some View {
		Form {
			ConfigHeader(title: "Status Message", config: \.statusMessageConfig, node: node, onAppear: setStatusMessageValues)

			Section(header: Text("Status")) {
				VStack(alignment: .leading) {
					HStack {
						TextField("Node Status", text: $nodeStatus, axis: .vertical)
							.lineLimit(3...5)
							.onChange(of: nodeStatus) { _, newValue in
								// Enforce 80 byte UTF-8 limit
								if newValue.utf8.count > 80 {
									var trimmed = newValue
									while trimmed.utf8.count > 80 {
										trimmed.removeLast()
									}
									nodeStatus = trimmed
								}
								if nodeStatus != node?.statusMessageConfig?.nodeStatus ?? "" {
									hasChanges = true
								}
							}
						if !nodeStatus.isEmpty {
							Button {
								nodeStatus = ""
								hasChanges = true
							} label: {
								Image(systemName: "xmark.circle.fill")
									.foregroundColor(.secondary)
							}
							.buttonStyle(.plain)
						}
					}
					Text("\(nodeStatus.utf8.count)/80 bytes")
						.font(.caption)
						.foregroundColor(nodeStatus.utf8.count > 70 ? .orange : .secondary)
				}
				Text("A status message that is broadcast to the mesh. Other nodes will see this status in the node list.")
					.font(.callout)
					.foregroundColor(.gray)
			}
		}
		.scrollDismissesKeyboard(.interactively)
		.disabled(!accessoryManager.isConnected || node?.statusMessageConfig == nil)
		.safeAreaInset(edge: .bottom, alignment: .center) {
			HStack(spacing: 0) {
			SaveConfigButton(node: node, hasChanges: $hasChanges) {
				performConfigSave(
					node: node,
					context: context,
					accessoryManager: accessoryManager,
					hasChanges: $hasChanges,
					dismiss: goBack
				) { fromUser, toUser in
					var smc = ModuleConfig.StatusMessageConfig()
					smc.nodeStatus = self.nodeStatus
					_ = try await accessoryManager.saveStatusMessageModuleConfig(config: smc, fromUser: fromUser, toUser: toUser)
				}
			}
			}
		}
		.navigationTitle("Status Message Config")
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
			}
		}
		.onFirstAppear {
			requestRemoteConfig(
				node: node,
				context: context,
				accessoryManager: accessoryManager,
				configIsNil: { $0.statusMessageConfig == nil },
				request: accessoryManager.requestStatusMessageModuleConfig
			)
		}
	}

	func setStatusMessageValues() {
		// Match Android: prefer the configured value, but if it's blank fall back to the
		// node's live broadcast status (NODE_STATUS_APP) so the field reflects what the
		// node is currently advertising rather than appearing empty.
		let configValue = node?.statusMessageConfig?.nodeStatus ?? ""
		let liveValue = node?.nodeStatus ?? ""
		self.nodeStatus = configValue.isEmpty && !liveValue.isEmpty ? liveValue : configValue
		self.hasChanges = false
	}
}

#Preview {
	StatusMessageConfig(node: nil)
		.environmentObject(AccessoryManager.shared)
		.modelContainer(PersistenceController.preview.container)
}
