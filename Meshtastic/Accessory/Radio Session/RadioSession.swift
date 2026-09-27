//
//  RadioSession.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation
import MeshtasticProtobufs

/// One live connection to one radio, and everything that belongs to it: its event loop,
/// heartbeats, handshake waits, config refresh, what it reported, its MQTT client proxy and its
/// lock-down state.
///
/// Every connected radio has one and runs the same connect steps (feature 021, D-17). The
/// focused radio's is `AccessoryManager.activeConnection`; the others are in
/// `AccessoryManager.additionalRadios`. Everything that arrives from a radio is handled against
/// the session it came from, never against whichever radio happens to be focused.
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

	// MARK: - What the radio reported (feature 021, T069)

	/// How many nodes the radio's MyInfo said its node DB holds (the Connect tab's progress).
	var expectedNodeDBSize: Int?
	/// Nodes received since this connection asked for its node DB (connect Step 5).
	var databaseNodeCount = 0
	/// The firmware edition from its MyInfo (event firmware and the like).
	var firmwareEdition: FirmwareEditions = .vanilla
	/// The region → legal preset map it advertised in the config handshake (2.8+).
	var loRaRegionPresets: [Config.LoRaConfig.RegionCode: RegionPresetInfo] = [:]

	// MARK: - Services (T100, T071c)

	/// Its MQTT client proxy, when its config asks for one.
	var mqtt: RadioMqttClient?
	/// Its range test module is on: range test packets it receives are stored as messages.
	var wantRangeTestPackets = false
	/// A lock-down passphrase saved for this radio has been sent on this connection (T065).
	var lockdownAutoAttempted = false
	/// The last lock-down status it reported, so the focused radio's sheet and Settings
	/// section show it when it takes the focus without reconnecting (T072).
	var lastLockdownStatus: LockdownStatus?
	/// Why it needs the user, when it does (T073; set through `AccessoryManager.setAttention`).
	var attention: RadioAttention?
}
