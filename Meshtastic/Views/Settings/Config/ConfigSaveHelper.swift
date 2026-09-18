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
	onError: ((String) -> Void)? = nil,
	save: @escaping (_ fromUser: UserEntity, _ toUser: UserEntity) async throws -> Void
) {
	guard let deviceNum = accessoryManager.activeDeviceNum,
		  let connectedNode = getNodeInfo(id: deviceNum, context: context),
		  let fromUser = connectedNode.user,
		  let toUser = node?.user
	else {
		// The Save button only checks for a connection and a change, so this can be
		// reached from a tap. Say so rather than doing nothing.
		Logger.mesh.warning("⚠️ Cannot save config: missing connected node or user entities")
		onError?(String(localized: "The connected radio or this node's user record is missing, so nothing was saved.",
						comment: "Config save could not start"))
		return
	}

	Task {
		do {
			try await save(fromUser, toUser)
			hasChanges.wrappedValue = false
			dismiss()
		} catch {
			Logger.mesh.error("🚨 Config save failed: \(error.localizedDescription)")
			onError?(error.localizedDescription)
		}
	}
}
