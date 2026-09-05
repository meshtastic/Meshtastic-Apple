//
//  ConfigSaveHelper.swift
//  Meshtastic
//

import OSLog
import SwiftData
import SwiftUI

/// Performs the common save-config-and-dismiss pattern used across all config views.
///
/// This replaces the duplicated ~15-line boilerplate that previously appeared in every
/// `SaveConfigButton` closure. It safely unwraps the connected node's user and the
/// target node's user (no force-unwraps), flattens the nested `Task { @MainActor in }`
/// pattern, and logs failures.
///
/// Usage inside a `SaveConfigButton` closure:
/// ```swift
/// SaveConfigButton(node: node, hasChanges: $hasChanges) {
///     performConfigSave(
///         node: node,
///         context: context,
///         accessoryManager: accessoryManager,
///         hasChanges: $hasChanges,
///         dismiss: goBack
///     ) { fromUser, toUser in
///         var dc = Config.DeviceConfig()
///         // ... set fields ...
///         try await accessoryManager.saveDeviceConfig(config: dc, fromUser: fromUser, toUser: toUser)
///     }
/// }
/// ```
@MainActor
func performConfigSave(
	node: NodeInfoEntity?,
	context: ModelContext,
	accessoryManager: AccessoryManager,
	hasChanges: Binding<Bool>,
	dismiss: DismissAction,
	save: @escaping (_ fromUser: UserEntity, _ toUser: UserEntity) async throws -> Void
) {
	guard let deviceNum = accessoryManager.activeDeviceNum,
		  let connectedNode = getNodeInfo(id: deviceNum, context: context),
		  let fromUser = connectedNode.user,
		  let toUser = node?.user,
		  let targetNode = node
	else {
		Logger.mesh.warning("⚠️ Cannot save config: missing connected node or user entities")
		return
	}
	let operationID = targetNode.num == deviceNum
		? nil
		: accessoryManager.beginRemoteAdminConfigOperation(kind: .save, targetNodeNum: targetNode.num)
	if targetNode.num != deviceNum, operationID == nil {
		accessoryManager.remoteAdminConfigFeedback = (targetNode.num, "A configuration save is already in progress for this node. Please wait for it to finish.")
		return
	}

	Task {
		do {
			if let operationID {
				try await RemoteAdminConfigTracker.$currentOperationID.withValue(operationID) {
					try await save(fromUser, toUser)
				}
			} else {
				try await save(fromUser, toUser)
			}
			if targetNode.num == deviceNum {
				hasChanges.wrappedValue = false
				dismiss()
				return
			}
			guard let operationID else { return }
			switch accessoryManager.remoteAdminConfigTracker.finish(operationID) {
			case .succeeded:
				hasChanges.wrappedValue = false
				dismiss()
			case .failed(let message):
				accessoryManager.remoteAdminConfigFeedback = (targetNode.num, message)
				Logger.mesh.error("🚨 Config save rejected: \(message, privacy: .public)")
			case .timedOut:
				accessoryManager.remoteAdminConfigFeedback = (targetNode.num, "No confirmation was received from the remote node. Check that it is online and retry.")
				Logger.mesh.error("🚨 Config save timed out")
			}
		} catch {
			if let operationID {
				accessoryManager.remoteAdminConfigTracker.fail(operationID, with: error)
			}
			accessoryManager.remoteAdminConfigFeedback = (targetNode.num, error.localizedDescription)
			Logger.mesh.error("🚨 Config save failed: \(error.localizedDescription)")
		}
	}
}
