//
//  AccessoryManager+RadioChoice.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation
import MeshtasticProtobufs
import OSLog

// MARK: - Sending through a chosen radio (feature 021, T084/T085)

extension AccessoryManager {

	/// The connected session for `radioNum`: the focused one when `radioNum` is nil or is the
	/// focused radio, otherwise the additional radio with that node number.
	func connectedSession(forRadio radioNum: Int64?) -> RadioSession? {
		guard let radioNum else { return activeConnection }
		if activeConnection?.nodeNum == radioNum {
			return activeConnection
		}
		return additionalRadios.values.first { $0.session.nodeNum == radioNum }?.session
	}

	/// True when `radioNum` is connected, focused or not.
	func isRadioConnected(nodeNum radioNum: Int64) -> Bool {
		connectedSession(forRadio: radioNum) != nil
	}

	/// Node numbers of every connected radio, the focused one first.
	var connectedRadioNums: [Int64] {
		connectedRadios.compactMap(\.num)
	}

	/// Sends through `session`. The focused radio keeps its own path (`send(_:debugDescription:)`,
	/// with its counters); an additional radio sends on its own connection.
	func send(_ data: ToRadio, via session: RadioSession, debugDescription: String? = nil) async throws {
		if session === activeConnection {
			try await send(data, debugDescription: debugDescription)
			return
		}
		guard additionalRadio(for: session) != nil, await session.connection.isConnected else {
			throw AccessoryError.connectionFailed("That radio is no longer connected")
		}
		try await session.connection.send(data)
		if let debugDescription {
			Logger.transport.info("📻 [\(session.device.shortName ?? session.device.name, privacy: .public)] \(debugDescription, privacy: .public)")
		}
	}

	// MARK: - Local admin on every radio (D-11)

	/// Sends an admin message addressed to one of the user's own radios through that radio. The
	/// focused radio, or a radio that isn't connected, keeps the old path (`send`).
	func sendLocalAdmin(_ data: ToRadio, to radioNum: Int64, debugDescription: String? = nil) async throws {
		if let session = connectedSession(forRadio: radioNum), session !== activeConnection {
			try await send(data, via: session, debugDescription: debugDescription)
		} else {
			try await send(data, debugDescription: debugDescription)
		}
	}

	/// Favorites or unfavorites `node` on every connected radio (D-11), the focused one first.
	/// `radios` narrows that to some of them (still in connection order). Throws only if the
	/// first radio fails; another radio's failure is logged, since the node is still favorited
	/// where it matters most and the next node DB will show the rest.
	func setFavorite(_ favorite: Bool, node: NodeInfoEntity, radios: [Int64]? = nil) async throws {
		let targets = connectedRadioNums.filter { radios?.contains($0) ?? true }
		for (offset, radioNum) in targets.enumerated() where radioNum != node.num {
			do {
				if favorite {
					try await setFavoriteNode(node: node, connectedNodeNum: radioNum)
				} else {
					try await removeFavoriteNode(node: node, connectedNodeNum: radioNum)
				}
			} catch where offset > 0 {
				Logger.admin.error("Could not update favorite \(node.num.toHex(), privacy: .public) on \(radioNum.toHex(), privacy: .public): \(error.localizedDescription, privacy: .public)")
			}
		}
	}

	/// Ignores or un-ignores `node` on every connected radio (D-11), like `setFavorite`.
	func setIgnored(_ ignored: Bool, node: NodeInfoEntity) async throws {
		for (offset, radioNum) in connectedRadioNums.enumerated() where radioNum != node.num {
			do {
				if ignored {
					try await setIgnoredNode(node: node, connectedNodeNum: radioNum)
				} else {
					try await removeIgnoredNode(node: node, connectedNodeNum: radioNum)
				}
			} catch where offset > 0 {
				Logger.admin.error("Could not update ignored \(node.num.toHex(), privacy: .public) on \(radioNum.toHex(), privacy: .public): \(error.localizedDescription, privacy: .public)")
			}
		}
	}
}
