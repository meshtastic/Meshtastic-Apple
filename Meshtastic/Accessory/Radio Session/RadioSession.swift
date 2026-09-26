//
//  RadioSession.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation

/// One live connection to one radio.
///
/// Today `AccessoryManager` holds at most one of these (`activeConnection`). Everything that
/// arrives from a radio is handled against the session it came from rather than against
/// whichever radio happens to be current, so several sessions can run side by side later
/// (feature 021, see `specs/021-multi-radio-connections/plan.md`).
///
/// A class so its identity can be compared: an event from a session that is no longer the
/// active one (a late packet from a torn-down connection) can be told apart from a current one.
@MainActor
final class RadioSession: Identifiable {
	/// Unique per connection attempt. Reconnecting to the same radio makes a new session.
	let id = UUID()
	/// The radio as the app currently knows it. Updated in place by `AccessoryManager.updateDevice`.
	var device: Device
	let connection: any Connection
	let startedAt = Date()

	init(device: Device, connection: any Connection) {
		self.device = device
		self.connection = connection
	}

	/// The radio's node number, once MyInfo has arrived.
	var nodeNum: Int64? { device.num }

	// MARK: - Connection lifecycle (feature 021, T069)

	// State that belongs to this one connection, so each connected radio has its own
	// (plan.md › Every radio the same). `AccessoryManager` drives it for the focused radio.

	/// Delivers this connection's events to `AccessoryManager.didReceive(_:from:)`.
	var eventTask: Task<Void, Error>?
	/// For transports that need one: the idle heartbeat, and the timeout that closes the link
	/// when a heartbeat goes unanswered (firmware 2.7.4 and later).
	var heartbeatTimer: ResettableTimer?
	var heartbeatResponseTimer: ResettableTimer?
	/// Connect Step 5: resumed by the first NodeInfo of the node-DB dump, or by its completion.
	var firstDatabaseNodeInfoContinuation: CheckedContinuation<Void, Error>?
	/// Connect Step 5a: opened when the node-DB dump completes.
	let wantDatabaseGate = AsyncGate()
	/// A config-only want-config in progress (`AccessoryManager.sendWantConfig`), and its task.
	var automaticConfigRefresh: AutomaticConfigRefresh?
	var automaticConfigRefreshTask: Task<Void, Never>?
}
