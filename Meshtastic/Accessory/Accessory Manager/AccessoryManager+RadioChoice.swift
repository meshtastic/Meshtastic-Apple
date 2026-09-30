//
//  AccessoryManager+RadioChoice.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation
import MeshtasticProtobufs
import OSLog
import SwiftData

// MARK: - One radio's connection (feature 021, D-19, T300)

/// One radio's connection, as the window that shows the radio reads it: the same for every radio,
/// whether or not it's the first one.
struct RadioLinkStatus {
	/// `.connecting` through `.subscribed` while it connects or is connected; otherwise what's
	/// left: `.idle`, or for the first radio the manager's own state (`.discovering`).
	var state: AccessoryManagerState
	/// Whether Disconnect applies: it's connecting or connected.
	var canDisconnect: Bool
	/// Why it needs the user: locked, or its firmware is too old.
	var attention: RadioAttention?
	/// Why its last connect failed, until its next connect starts.
	var lastError: Error?

	var firmwareUpdateRequired: Bool {
		if case .firmwareTooOld = attention { return true }
		return false
	}

	/// Connected, as `AccessoryManager.isConnected` counts it: subscribed, or getting its node DB.
	var isConnected: Bool {
		switch state {
		case .subscribed, .retrievingDatabase: return true
		default: return false
		}
	}

	/// Connecting, as `AccessoryManager.isConnecting` counts it.
	var isConnecting: Bool {
		switch state {
		case .connecting, .communicating, .retrying: return true
		default: return false
		}
	}
}

extension AccessoryManager {

	/// The radio whose state is the manager's own (`state`, `allowDisconnect`,
	/// `lastConnectionError`, `firmwareUpdateRequired`): the first radio, else the one connecting as the first
	/// radio, or the preferred radio when neither.
	var firstDeviceId: UUID? {
		activeConnection?.device.id
			?? connectAttempts.values.first(where: \.isFirst)?.device.id
			?? UUID(uuidString: PreferredRadio.peripheralId)
	}

	/// Radio `deviceId`'s connection. The first radio's comes from the manager's fields, any
	/// other's from its connect attempt, its session and `radioConnectErrors`. The first radio's
	/// stay on the manager, as on `main` (T315 dropped); windows read this rather than either.
	func linkStatus(of deviceId: UUID) -> RadioLinkStatus {
		if deviceId == firstDeviceId {
			var attention: RadioAttention?
			if let session = activeConnection {
				if firmwareUpdateRequired {
					attention = .firmwareTooOld(version: session.device.firmwareVersion ?? "?")
				} else {
					attention = lockdownAttention(for: session)
				}
			}
			return RadioLinkStatus(state: state, canDisconnect: allowDisconnect, attention: attention, lastError: lastConnectionError)
		}
		let session = additionalRadios[deviceId]
		let attempt = connectAttempts[deviceId]
		let state: AccessoryManagerState
		if let attempt {
			state = attempt.status
		} else if session?.device.connectionState == .connected {
			state = .subscribed
		} else {
			state = .idle
		}
		return RadioLinkStatus(state: state, canDisconnect: attempt != nil || session != nil, attention: session?.attention, lastError: radioConnectErrors[deviceId])
	}
}

// MARK: - Sending through a chosen radio (feature 021, T084/T085)

extension AccessoryManager {

	/// The connected session for `radioNum`: the first one when `radioNum` is nil or is the
	/// first radio, otherwise the additional radio with that node number.
	func connectedSession(forRadio radioNum: Int64?) -> RadioSession? {
		guard let radioNum else { return activeConnection }
		if activeConnection?.nodeNum == radioNum {
			return activeConnection
		}
		return additionalRadios.values.first { $0.nodeNum == radioNum }
	}

	/// True when `radioNum` is connected, the first radio or another.
	func isRadioConnected(nodeNum radioNum: Int64) -> Bool {
		connectedSession(forRadio: radioNum) != nil
	}

	/// The channel slot the first radio reaches `node` on. Once other radios hear the node,
	/// `node.channel` can be another radio's slot number, so the first radio's own observation
	/// decides, and primary (0) when it has none (T143). While only the first radio has heard
	/// the node this is `node.channel`, as before. Read when a request is sent, not in a view body.
	func channelSlot(toReach node: NodeInfoEntity, fromRadio: Int64? = nil) -> Int32 {
		guard let context = node.modelContext else { return node.channel }
		let radioNum = fromRadio ?? activeDeviceNum
		let nodeNum = node.num
		let descriptor = FetchDescriptor<NodeObservationEntity>(predicate: #Predicate { $0.nodeNum == nodeNum })
		let observations = (try? context.fetch(descriptor)) ?? []
		guard observations.contains(where: { $0.radioNum != radioNum }) else { return node.channel }
		return observations.first { $0.radioNum == radioNum }?.channel ?? 0
	}

	/// Node numbers of every connected radio, starting with the first radio.
	var connectedRadioNums: [Int64] {
		connectedRadios.compactMap(\.num)
	}

	/// Sends through `session`. The first radio keeps its own path (`send(_:debugDescription:)`,
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

	// MARK: - Admin routing (T089)

	/// The connected radio an admin packet goes through:
	/// - addressed to one of the user's connected radios: that radio, on its own connection. The
	///   firmware takes whatever a phone sends it as local admin, so Settings can configure any
	///   connected radio from its own window, and no session passkey is involved;
	/// - otherwise the radio in `from`, when it's connected: the relay for remote admin;
	/// - otherwise the first radio.
	/// Nil with no radio connected.
	func adminRoute(for packet: MeshPacket) -> RadioSession? {
		if let target = connectedSession(forRadio: Int64(packet.to)) {
			return target
		}
		if let relay = connectedSession(forRadio: Int64(packet.from)) {
			return relay
		}
		return activeConnection
	}

	/// `packet` as `session` sends it. Remote admin relayed by a radio other than the first one
	/// carries that radio's own session passkey for the node (T045: each radio gets its own), in
	/// place of the node's, which is the first radio's. Everything else is unchanged.
	func adminPacket(_ packet: MeshPacket, relayedBy session: RadioSession) -> MeshPacket {
		guard session !== activeConnection,
			  let relayNum = session.nodeNum, Int64(packet.to) != relayNum,
			  packet.decoded.portnum == .adminApp,
			  var admin = try? AdminMessage(serializedBytes: packet.decoded.payload),
			  !admin.sessionPasskey.isEmpty else {
			return packet
		}
		let nodeNum = Int64(packet.to)
		let descriptor = FetchDescriptor<NodeObservationEntity>(predicate: #Predicate {
			$0.radioNum == relayNum && $0.nodeNum == nodeNum
		})
		guard let passkey = (try? context.fetch(descriptor).first)?.sessionPasskey, !passkey.isEmpty,
			  passkey != admin.sessionPasskey else {
			return packet
		}
		admin.sessionPasskey = passkey
		guard let payload = try? admin.serializedData() else { return packet }
		var relayed = packet
		relayed.decoded.payload = payload
		return relayed
	}

	// MARK: - Local admin on every radio (D-11)

	/// Sends an admin message addressed to one of the user's own radios through that radio. The
	/// first radio, or a radio that isn't connected, keeps the old path (`send`).
	func sendLocalAdmin(_ data: ToRadio, to radioNum: Int64, debugDescription: String? = nil) async throws {
		if let session = connectedSession(forRadio: radioNum), session !== activeConnection {
			try await send(data, via: session, debugDescription: debugDescription)
		} else {
			try await send(data, debugDescription: debugDescription)
		}
	}

	/// Sets the user's choice on every radio's observation of `node`, so the node's combined flag
	/// (any radio, T164) is what the user chose until a radio's node DB says otherwise. Saved
	/// with the node.
	/// `radios` limits it to those radios' observations.
	private func recordChoice(on node: NodeInfoEntity, radios: [Int64]? = nil, _ apply: (NodeObservationEntity) -> Void) {
		guard let context = node.modelContext else { return }
		let nodeNum = node.num
		let observations = (try? context.fetch(FetchDescriptor<NodeObservationEntity>(predicate: #Predicate { $0.nodeNum == nodeNum }))) ?? []
		for observation in observations where radios?.contains(observation.radioNum) ?? true {
			apply(observation)
		}
	}

	/// Favorites or unfavorites `node` on every connected radio (D-11), starting with the first radio.
	/// `radios` narrows that to some of them (still in connection order). Throws only if the
	/// first radio fails; another radio's failure is logged, since the node is still favorited
	/// where it matters most and the next node DB will show the rest.
	func setFavorite(_ favorite: Bool, node: NodeInfoEntity, radios: [Int64]? = nil) async throws {
		recordChoice(on: node, radios: radios) { $0.favorite = favorite }
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
		recordChoice(on: node) { $0.ignored = ignored }
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
