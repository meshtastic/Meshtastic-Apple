//
//  RequestConfigOnAppear.swift
//  Meshtastic
//

import OSLog
import SwiftData
import SwiftUI

/// Requests a radio configuration section from a remote node using PKI admin
/// if the session has expired or the config has not yet been received.
///
/// Call this inside `.onFirstAppear { }` to replace the duplicated config
/// request boilerplate in every config view.
@MainActor
func requestRemoteConfig(
	node: NodeInfoEntity?,
	context: ModelContext,
	accessoryManager: AccessoryManager,
	configIsNil: @escaping (NodeInfoEntity) -> Bool,
	request: @escaping (_ fromUser: UserEntity, _ toUser: UserEntity) async throws -> Void,
	requestForConnectedNode: Bool = false
) {
	guard let deviceNum = accessoryManager.activeDeviceNum,
		  let node,
		  let connectedNode = getNodeInfo(id: deviceNum, context: context)
	else { return }

	if requestForConnectedNode && node.num == deviceNum && configIsNil(node) {
		Task {
			do {
				guard let fromUser = connectedNode.user, let toUser = node.user else { return }
				Logger.mesh.info("⚙️ Config missing for connected node, requesting")
				try await request(fromUser, toUser)
			} catch {
				Logger.mesh.error("🚨 Config request failed for connected node")
			}
		}
		return
	}

	guard node.num != deviceNum else { return }

	if UserDefaults.enableAdministration {
		let expiration = node.sessionExpiration ?? Date()
		if expiration < Date() || configIsNil(node) {
			Task {
				do {
					guard let fromUser = connectedNode.user, let toUser = node.user else { return }
					Logger.mesh.info("⚙️ Empty or expired config requesting via PKI admin")
					try await request(fromUser, toUser)
				} catch {
					Logger.mesh.error("🚨 Config request failed")
				}
			}
		}
	} else {
		Logger.mesh.info("☠️ Using insecure legacy admin that is no longer supported, please upgrade your firmware.")
	}
}
