//
//  AccessoryManagerScanDuringPairingTests.swift
//  MeshtasticTests
//
//  Covers a TestFlight report: the BLE pairing PIN sheet disappearing immediately when
//  connecting to a new radio. Root cause — CoreBluetooth scanning concurrently with a
//  first-ever BLE bond's encrypted-characteristic subscription races the pairing handshake;
//  iOS tears the system PIN sheet down almost instantly, surfacing as
//  CBATTErrorInsufficientEncryption on the FROMNUM notify subscription. This is a documented
//  CoreBluetooth interaction (scanning-while-pairing), not something the app can retry its way
//  out of once it happens.
//
//  Two fixes close this off:
//   1. AccessoryManager+Connect.swift's Step 0 now calls stopDiscovery() before Step 1 attempts
//      to connect/pair, for every attempt (first try and retries alike).
//   2. appDidBecomeActive() must not resurrect the scan mid-handshake. The system pairing sheet
//      is out-of-process UI, same category as the Bluetooth-power alert that blipped scenePhase
//      and was fixed in #2139/#2161 — if it does the same thing, a naive appDidBecomeActive()
//      would restart scanning right as the user is looking at the PIN prompt. This suite covers
//      that guard directly since it's plain @MainActor state, without needing a real
//      CoreBluetooth stack.
//

import Testing

@testable import Meshtastic

@MainActor
@Suite("AccessoryManager discovery during an in-flight connect")
struct AccessoryManagerScanDuringPairingTests {

	@Test func appDidBecomeActiveDoesNotRestartDiscoveryWhileConnecting() {
		let manager = AccessoryManager(transports: [])
		manager.updateState(.connecting)
		#expect(manager.discoveryTask == nil)

		manager.appDidBecomeActive()

		// A scenePhase blip mid-pairing (e.g. the system PIN sheet appearing/dismissing)
		// must not resurrect scanning while a connect attempt is in flight.
		#expect(manager.discoveryTask == nil)
	}

	@Test func appDidBecomeActiveDoesNotRestartDiscoveryWhileCommunicating() {
		// .communicating is the state Step 1 sets right after connection.connect() is called —
		// i.e. exactly the window the system PIN sheet is up during a first-ever BLE bond.
		let manager = AccessoryManager(transports: [])
		manager.updateState(.communicating)
		#expect(manager.discoveryTask == nil)

		manager.appDidBecomeActive()

		#expect(manager.discoveryTask == nil)
	}

	@Test func appDidBecomeActiveDoesNotRestartDiscoveryWhileRetrying() {
		// .retrying is the state Step 0 sets at the top of a retry attempt, before its
		// unconditional stopDiscovery() call runs — must not be treated as idle either.
		let manager = AccessoryManager(transports: [])
		manager.updateState(.retrying(attempt: 2, maxAttempts: 2))
		#expect(manager.discoveryTask == nil)

		manager.appDidBecomeActive()

		#expect(manager.discoveryTask == nil)
	}

	@Test func appDidBecomeActiveRestartsDiscoveryWhenIdle() async {
		// Existing behavior preserved: with no in-flight connect and no active connection,
		// coming back to the foreground still resumes scanning.
		let manager = AccessoryManager(transports: [])
		manager.updateState(.discovering)
		#expect(manager.discoveryTask == nil)

		manager.appDidBecomeActive()

		#expect(manager.discoveryTask != nil)

		await manager.stopDiscovery()
	}
}
