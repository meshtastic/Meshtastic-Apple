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
		  let toUser = node?.user
	else {
		Logger.mesh.warning("⚠️ Cannot save config: missing connected node or user entities")
		return
	}

	Task {
		do {
			try await save(fromUser, toUser)
			hasChanges.wrappedValue = false
			dismiss()
		} catch {
			Logger.mesh.error("🚨 Config save failed: \(error.localizedDescription)")
		}
	}
}
