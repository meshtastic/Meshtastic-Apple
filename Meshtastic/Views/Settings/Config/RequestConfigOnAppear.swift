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
	section: String,
	request: @escaping (_ fromUser: UserEntity, _ toUser: UserEntity) async throws -> Void,
	requestForConnectedNode: Bool = false,
	force: Bool = false
) {
	guard let deviceNum = accessoryManager.activeDeviceNum,
		  let node,
		  let connectedNode = getNodeInfo(id: deviceNum, context: context)
	else { return }

	if requestForConnectedNode && node.num == deviceNum && configIsNil(node) {
		Task {
			do {
				guard let fromUser = connectedNode.user, let toUser = node.user else {
					return
				}
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
		if force || expiration < Date() || configIsNil(node) {
			let operationID = accessoryManager.beginRemoteAdminConfigOperation(kind: .request, targetNodeNum: node.num, section: section)
			guard let operationID else { return }
			Task {
				do {
					guard let fromUser = connectedNode.user, let toUser = node.user else {
						accessoryManager.remoteAdminConfigTracker.fail(operationID, with: AccessoryError.appError("Missing user identity"))
						return
					}
					Logger.mesh.info("⚙️ Empty or expired config requesting via PKI admin")
				try await RemoteAdminConfigTracker.$currentOperationID.withValue(operationID) {
					try await request(fromUser, toUser)
				}
				if case .failed(let message) = accessoryManager.remoteAdminConfigTracker.finish(operationID) {
					accessoryManager.remoteAdminConfigFeedback = (node.num, message)
				}
			} catch {
				accessoryManager.remoteAdminConfigTracker.fail(operationID, with: error)
				Logger.mesh.error("🚨 Config request failed")
				}
			}
		}
	} else {
		Logger.mesh.info("☠️ Using insecure legacy admin that is no longer supported, please upgrade your firmware.")
	}
}
