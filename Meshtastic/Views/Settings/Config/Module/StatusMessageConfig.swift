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
	/// The value the field was prefilled with (configured value, or the live broadcast
	/// status when no config value exists yet). `hasChanges` is computed relative to this
	/// so the programmatic prefill — which fires `onChange` — is not mistaken for a user
	/// edit (which would wrongly enable Save and trigger a discard prompt on a blank open).
	@State private var baselineStatus: String = ""

	var body: some View {
		Form {
			ConfigHeader(title: "Status Message", config: \.statusMessageConfig, node: node, onAppear: setStatusMessageValues)

			Section(header: Text("Status Message Config")) {
				VStack(alignment: .leading) {
					HStack {
						// Single-line input per the design spec; the 80-byte enforcement below is
						// independent of presentation. Placeholder kept as the existing localized
						// "Node Status" key (translated in 10 locales) rather than a new string.
						TextField("Node Status", text: $nodeStatus)
							.onChange(of: nodeStatus) { _, newValue in
								// Enforce 80 byte UTF-8 limit
								let clamped = Self.clampedToStatusByteLimit(newValue)
								if clamped != newValue {
									nodeStatus = clamped
								}
								// Track edits relative to the prefilled baseline so adopting the
								// prefill value isn't reported as an unsaved change.
								hasChanges = nodeStatus != baselineStatus
							}
						if !nodeStatus.isEmpty {
							Button {
								nodeStatus = ""
							} label: {
								Image(systemName: "xmark.circle.fill")
									.foregroundColor(.secondary)
							}
							.buttonStyle(.plain)
							.accessibilityLabel(String(localized: "Clear", comment: "VoiceOver label for the clear text button"))
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
		.navigationTitle("Status Message")
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

	/// Clamp a status to the 80-byte UTF-8 limit the firmware enforces, dropping whole trailing
	/// characters so the result is never split mid-scalar. Applied to the prefill as well as live
	/// edits so an over-long live broadcast can't desync `nodeStatus` from `baselineStatus` and
	/// flip `hasChanges` on a fresh open with no user edit.
	static func clampedToStatusByteLimit(_ value: String) -> String {
		var clamped = value
		while clamped.utf8.count > 80 {
			clamped.removeLast()
		}
		return clamped
	}

	func setStatusMessageValues() {
		// Match Android: prefer the configured value, but if it has no displayable content fall
		// back to the node's live broadcast status (NODE_STATUS_APP) so the field reflects what the
		// node is currently advertising rather than appearing empty. Uses the same displayable
		// filtering as `statusMessageDisplay` so whitespace-/invisible-only configured values are
		// treated as blank here too, matching what the cards/detail show.
		let prefill = Self.clampedToStatusByteLimit(
			NodeInfoEntity.statusMessagePrefill(
				configured: node?.statusMessageConfig?.nodeStatus,
				live: node?.nodeStatus
			)
		)
		self.nodeStatus = prefill
		// Record the prefill as the change baseline so the onChange this assignment triggers
		// doesn't flip hasChanges on a fresh open with no user edit.
		self.baselineStatus = prefill
		self.hasChanges = false
	}
}

#Preview {
	StatusMessageConfig(node: nil)
		.environmentObject(AccessoryManager.shared)
		.modelContainer(PersistenceController.preview.container)
}
