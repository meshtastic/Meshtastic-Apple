//
//  MeshShareSnapshotBuilder.swift
//  Meshtastic
//

import Foundation
import MeshtasticProtobufs
import OSLog
import SwiftData

enum MeshShareSnapshotBuilder {
	enum BuildError: LocalizedError {
		case missingNode
		case missingIdentity
		case missingLoRaConfig

		var errorDescription: String? {
			switch self {
			case .missingNode:
				return "The recently connected radio is not in the local database."
			case .missingIdentity:
				return "The recently connected radio has no shareable identity."
			case .missingLoRaConfig:
				return "The recently connected radio has no LoRa configuration."
			}
		}
	}

	@MainActor
	static func make(node: NodeInfoEntity, refreshedAt: Date = .now) throws -> MeshShareSnapshot {
		let nodeInfo = node.toProto()
		guard ShareContactQR.canShareContact(for: nodeInfo) else {
			throw BuildError.missingIdentity
		}
		guard let loRaConfig = node.loRaConfig else {
			throw BuildError.missingLoRaConfig
		}

		var contact = SharedContact()
		contact.nodeNum = nodeInfo.num
		contact.user = nodeInfo.user
		contact.manuallyVerified = true
		let contactURL = try MeshContactURL.urlString(for: contact, exchangeRequested: true)

		let channels = try (node.myInfo?.channels ?? [])
			.filter { $0.role > 0 }
			.sorted { $0.index < $1.index }
			.map { channel in
				let settings = channel.settingsProto
				return MeshShareChannel(
					index: channel.index,
					name: displayName(for: channel),
					isEncrypted: settings.psk.count >= 3,
					settingsData: try settings.serializedData()
				)
			}

		return MeshShareSnapshot(
			radioNodeNum: nodeInfo.num,
			radioLongName: nodeInfo.user.longName,
			radioShortName: nodeInfo.user.shortName,
			contactURL: contactURL,
			loraConfigData: try loRaConfig.toProto().serializedData(),
			channels: channels,
			refreshedAt: refreshedAt
		)
	}

	@MainActor
	static func refresh(nodeNum: Int64, context: ModelContext) {
		guard let node = getNodeInfo(id: nodeNum, context: context) else {
			Logger.services.error("Could not refresh Messages sharing snapshot: recent radio was not found.")
			return
		}
		do {
			try MeshShareStore.save(make(node: node))
			Logger.services.info("Updated Messages sharing snapshot for the recently connected radio.")
		} catch {
			Logger.services.error("Could not refresh Messages sharing snapshot: \(error.localizedDescription, privacy: .public)")
		}
	}

	private static func displayName(for channel: ChannelEntity) -> String {
		if channel.index == 0 && (channel.name?.isEmpty ?? true) {
			return "Primary"
		}
		return (channel.name?.isEmpty ?? true) ? "Channel \(channel.index)" : (channel.name ?? "Channel \(channel.index)")
	}
}
