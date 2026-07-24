//
//  BLETransportPoweredOffStatusTests.swift
//  MeshtasticTests
//
//  Covers the fix for issue #2161: BLETransport.handleCentralState's .poweredOff case set
//  `status = .error("Bluetooth is powered off")` and then immediately overwrote it with
//  `status = .ready` a few lines later in the same synchronous branch, so the transport's
//  own status never actually settled on the off-state — `.ready` (elsewhere in this file,
//  see stopScanning()) means "poweredOn and available", the opposite of powered off.
//
//  Found while reviewing #2139 (system BLE power alert suppression): that fix removed the
//  OS-level "Bluetooth is turned off" alert, which had accidentally been the only signal a
//  BLE-primary user got that Bluetooth was off. With the alert gone, this in-app status is
//  now the only signal left, so it needs to actually reflect reality.
//

import CoreBluetooth
import Testing

@testable import Meshtastic

@Suite("BLETransport .poweredOff status")
struct BLETransportPoweredOffStatusTests {

	/// `handleCentralState` only touches its `central:` parameter in the `.poweredOn` branch
	/// (to restart scanning); `.poweredOff` never reads it. A plain, delegate-less manager is
	/// enough to satisfy the signature without touching real Bluetooth hardware/authorization.
	private func unusedCentralManager() -> CBCentralManager {
		CBCentralManager(delegate: nil, queue: nil)
	}

	@Test func poweredOffSettlesOnError() async {
		let transport = BLETransport()

		await transport.handleCentralState(.poweredOff, central: unusedCentralManager())

		let status = await transport.status
		#expect(status == .error("Bluetooth is powered off"), "status must settle on .error, not be immediately overwritten by .ready (#2161)")
	}

	@Test func poweredOffNeverEndsAtReady() async {
		let transport = BLETransport()

		await transport.handleCentralState(.poweredOff, central: unusedCentralManager())

		let status = await transport.status
		#expect(status != .ready, ".ready means \"poweredOn and available\" elsewhere in BLETransport (see stopScanning()) — powered off is the opposite of that")
	}

	/// A transport that was previously discovering (poweredOn) and then loses power should
	/// still land on the off-state error, not silently revert to looking "ready".
	@Test func poweredOffAfterPoweredOnStillSettlesOnError() async {
		let transport = BLETransport()
		let manager = unusedCentralManager()

		await transport.handleCentralState(.poweredOn, central: manager)
		await transport.handleCentralState(.poweredOff, central: manager)

		let status = await transport.status
		#expect(status == .error("Bluetooth is powered off"))
	}

	/// A second poweredOff after recovering (poweredOn) and losing power again must still settle
	/// on the off-state error, not get stuck reflecting the intervening .discovering/.ready state.
	@Test func poweredOffAfterRecoveryRoundTripStillSettlesOnError() async {
		let transport = BLETransport()
		let manager = unusedCentralManager()

		await transport.handleCentralState(.poweredOff, central: manager)
		await transport.handleCentralState(.poweredOn, central: manager)
		await transport.handleCentralState(.poweredOff, central: manager)

		let status = await transport.status
		#expect(status == .error("Bluetooth is powered off"))
	}
}
