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
/// first radio's is `AccessoryManager.activeConnection`; the others are in
/// `AccessoryManager.additionalRadios`. Everything that arrives from a radio is handled against
/// the session it came from, never against whichever radio happens to be first.
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

	init(device: Device, connection: any Connection, passphraseStore: LockdownPassphraseStoring = LockdownPassphraseStore.shared) {
		self.device = device
		self.connection = connection
		self.lockdown = LockdownCoordinator(store: passphraseStore)
		lockdownSender.session = self
		lockdown.setSender(lockdownSender)
		// Firmware asks for the passphrase again on every new connection.
		lockdown.onConnect(peripheralID: device.id)
	}

	/// Its lock-down state: the saved passphrase tried once, the passphrase sheet, Lock Now
	/// (feature 021, T301). The same state machine for every radio.
	let lockdown: LockdownCoordinator
	/// What `lockdown` sends through, on this connection. Kept here: the coordinator holds it weakly.
	private let lockdownSender = SessionLockdownSender()

	/// The radio's node number, once MyInfo has arrived.
	var nodeNum: Int64? { device.num }

	// MARK: - Connection lifecycle (feature 021, T069)

	// State that belongs to this one connection, so each connected radio has its own
	// (plan.md › Every radio the same). `AccessoryManager` drives it for the first radio.

	/// Delivers this connection's events to `AccessoryManager.didReceive(_:from:)`.
	var eventTask: Task<Void, Error>?
	/// For transports that need one: the idle heartbeat, and the timeout that closes the link
	/// when a heartbeat goes unanswered (firmware 2.7.4 and later).
	var heartbeatTimer: ResettableTimer?
	var heartbeatResponseTimer: ResettableTimer?
	/// Connect Step 5: resumed by the first NodeInfo of the node-DB dump, or by its completion.
	var firstDatabaseNodeInfoContinuation: CheckedContinuation<Void, Error>?
	/// Set when the node-DB dump's first NodeInfo or its completion arrives, so Step 5 doesn't
	/// wait for one that came before it started waiting (T154).
	var databaseResponseArrived = false
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
	/// When it last finished sending its configuration, to tell a fresh readback from a stale
	/// cache (`AccessoryManager.lastConfigRefresh` is the first radio's).
	var lastConfigRefresh: Date?
	/// The region → legal preset map it advertised in the config handshake (2.8+).
	var loRaRegionPresets: [Config.LoRaConfig.RegionCode: RegionPresetInfo] = [:]

	// MARK: - Services (T100, T071c)

	/// Its MQTT client proxy, when its config asks for one.
	var mqtt: RadioMqttClient?
	/// Its range test module is on: range test packets it receives are stored as messages.
	var wantRangeTestPackets = false
	/// Why it needs the user, when it does (T073; set through `AccessoryManager.setAttention`).
	var attention: RadioAttention?
}
