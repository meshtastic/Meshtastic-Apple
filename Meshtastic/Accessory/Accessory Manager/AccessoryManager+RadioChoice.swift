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
}
