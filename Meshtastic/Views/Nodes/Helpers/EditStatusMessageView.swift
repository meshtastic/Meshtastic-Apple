//
//  EditStatusMessageView.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/27/26.
//
//  Alert-based prompt to set the status message a node broadcasts to the mesh.
//

import MeshtasticProtobufs
import OSLog
import SwiftData
import SwiftUI

extension View {
	/// Presents a native alert with a text field to set a node's status message
	/// (firmware 2.8+, gated by `AccessoryManager.supportsStatusMessage` at the call site).
	/// Works for the connected node, or a remote node that has been successfully
	/// administered before (`NodeInfoEntity.hasBeenAdministered`).
	/// Driven by `node`: assign a node to present the alert, `nil` (or Cancel/Save) dismisses it.
	func statusMessageAlert(node: Binding<NodeInfoEntity?>) -> some View {
		modifier(StatusMessageAlertModifier(node: node))
	}
}

private struct StatusMessageAlertModifier: ViewModifier {
	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Binding var node: NodeInfoEntity?
	@State private var status = ""
	/// The value loaded when the alert appeared, so Save is only enabled on a real edit.
	@State private var initialStatus = ""

	/// The firmware caps a status message at 80 bytes of UTF-8.
	private static let maxBytes = 80

	func body(content: Content) -> some View {
		content
			.alert(
				"Status Message",
				isPresented: Binding(get: { node != nil }, set: { isPresented in if !isPresented { node = nil } }),
				presenting: node
			) { presentedNode in
				TextField("Node Status", text: $status)
					.onChange(of: status) { _, newValue in
						let clamped = Self.clampedToStatusByteLimit(newValue)
						if clamped != newValue { status = clamped }
					}
				Button("Cancel", role: .cancel) {
					node = nil
				}
				Button("Save") {
					save(for: presentedNode)
					node = nil
				}
				.disabled(status == initialStatus)
			} message: { _ in
				Text("A status message that is broadcast to the mesh. Other nodes will see this status in the node list.")
			}
			.onChange(of: node?.num) { _, _ in
				// Same prefill the old config screen used: the configured value, falling back to
				// the live broadcast when the configured value has no displayable content.
				let prefill = Self.clampedToStatusByteLimit(
					NodeInfoEntity.statusMessagePrefill(
						configured: node?.statusMessageConfig?.nodeStatus,
						live: node?.nodeStatus
					)
				)
				status = prefill
				initialStatus = prefill
			}
	}

	/// Clamp to the 80-byte UTF-8 limit the firmware enforces, dropping whole trailing
	/// characters so the result is never split mid-scalar.
	private static func clampedToStatusByteLimit(_ value: String) -> String {
		var clamped = value
		while clamped.utf8.count > Self.maxBytes {
			clamped.removeLast()
		}
		return clamped
	}

	/// Same save path the old Status Message config screen used.
	/// `fromUser` is always the connected node's user and `toUser` the presented node's user —
	/// `saveStatusMessageModuleConfig` attaches the session passkey when they differ. The presented
	/// node must be the connected node or one we have successfully administered before.
	private func save(for presentedNode: NodeInfoEntity) {
		guard let deviceNum = accessoryManager.activeDeviceNum,
			  presentedNode.num == deviceNum || presentedNode.hasBeenAdministered,
			  let connectedNode = getNodeInfo(id: deviceNum, context: context),
			  let fromUser = connectedNode.user,
			  let toUser = presentedNode.user
		else {
			Logger.mesh.warning("⚠️ Cannot save status message: missing connected node or user entities")
			return
		}
		var config = ModuleConfig.StatusMessageConfig()
		config.nodeStatus = status
		let newStatus = status
		Task {
			do {
				_ = try await accessoryManager.saveStatusMessageModuleConfig(config: config, fromUser: fromUser, toUser: toUser)
				// Update the main-context entity the node list renders from, so the row
				// changes now instead of waiting for the next broadcast to arrive.
				presentedNode.nodeStatus = newStatus.isEmpty ? nil : newStatus
				presentedNode.statusMessageConfig?.nodeStatus = newStatus
				try? context.save()
			} catch {
				Logger.mesh.error("🚨 Status message save failed: \(error.localizedDescription)")
			}
		}
	}
}
