//
//  AccessoryManagerBLEStatusTests.swift
//  MeshtasticTests
//
//  Covers #2175: nothing read BLETransport.status before this, so once the system "Bluetooth
//  is turned off" alert was intentionally suppressed (#2162), a BLE user had no in-app signal
//  for why no devices were appearing in Connect's Available Radios — even though #2161/#2163
//  had already fixed the status value itself. AccessoryManager.observeBLETransportStatus()
//  mirrors BLETransport's status stream onto @Published bleTransportStatus, and
//  isBluetoothPoweredOff derives the Connect tab's boolean from it.
//

import CoreBluetooth
import Testing

@testable import Meshtastic

@MainActor
@Suite("AccessoryManager BLE status mirroring (#2175)")
struct AccessoryManagerBLEStatusTests {

	/// `handleCentralState` only touches its `central:` parameter in the `.poweredOn` branch;
	/// a plain, delegate-less manager is enough to satisfy the signature without touching real
	/// Bluetooth hardware/authorization.
	private func unusedCentralManager() -> CBCentralManager {
		CBCentralManager(delegate: nil, queue: nil)
	}

	/// `BLETransport.init()` creates a *real* `CBCentralManager` on its own delegate whenever
	/// `CBCentralManager.authorization` is already determined — true on the simulator, where
	/// there's no permission prompt to wait on. That manager asynchronously reports genuine
	/// (simulator) hardware state exactly once, shortly after construction (typically
	/// `.unsupported`, since simulators have no real radio), completely independently of
	/// anything a test scripts. If that incidental transition lands *after* a test has already
	/// driven and observed its own scripted state, it silently clobbers `bleTransportStatus`
	/// and flakes the very next assertion. Giving it a moment to settle — before constructing the
	/// `AccessoryManager` under test and before scripting anything — makes the one-time incidental
	/// transition land (and be reflected in `bleTransport.status`) ahead of
	/// `observeBLETransportStatus()`'s subscription, so its replay already carries the settled
	/// value and no further incidental transition remains to race a later scripted one.
	private func settleIncidentalHardwareStatus(for transport: BLETransport, timeout: Duration = .milliseconds(500)) async {
		try? await Task.sleep(for: timeout)
	}

	/// `observeBLETransportStatus()` mirrors status via a background `Task` consuming an
	/// `AsyncStream`, so the `@Published` update lands asynchronously relative to
	/// `handleCentralState` returning. Poll with a bounded timeout instead of a fixed sleep to
	/// keep this fast on a quiet CI runner and non-flaky on a loaded one.
	private func waitUntil(timeout: Duration = .milliseconds(500), _ condition: @escaping () -> Bool) async {
		let deadline = ContinuousClock.now + timeout
		while !condition(), ContinuousClock.now < deadline {
			try? await Task.sleep(for: .milliseconds(10))
		}
	}

	@Test func startsFalseBeforeAnyTransition() async {
		let bleTransport = BLETransport()
		await settleIncidentalHardwareStatus(for: bleTransport)

		let manager = AccessoryManager(transports: [bleTransport])
		#expect(manager.isBluetoothPoweredOff == false)
	}

	@Test func becomesTrueWhenBLEPowersOff() async {
		let bleTransport = BLETransport()
		await settleIncidentalHardwareStatus(for: bleTransport)

		let manager = AccessoryManager(transports: [bleTransport])
		await bleTransport.handleCentralState(.poweredOff, central: unusedCentralManager())
		await waitUntil { manager.isBluetoothPoweredOff }

		#expect(manager.isBluetoothPoweredOff)
		#expect(manager.bleTransportStatus == .error(BLETransport.poweredOffStatusMessage))
	}

	@Test func clearsWhenBLEPowersBackOn() async {
		let bleTransport = BLETransport()
		await settleIncidentalHardwareStatus(for: bleTransport)

		let manager = AccessoryManager(transports: [bleTransport])
		let central = unusedCentralManager()

		await bleTransport.handleCentralState(.poweredOff, central: central)
		await waitUntil { manager.isBluetoothPoweredOff }
		#expect(manager.isBluetoothPoweredOff)

		await bleTransport.handleCentralState(.poweredOn, central: central)
		await waitUntil { !manager.isBluetoothPoweredOff }
		#expect(manager.isBluetoothPoweredOff == false)
	}

	/// A manager with no BLE transport at all (e.g. a future macOS-only build) must not crash
	/// wiring up the observer, and simply reports "not powered off" — there's no BLE to be off.
	@Test func noOpsWithoutABLETransport() {
		let manager = AccessoryManager(transports: [])
		#expect(manager.isBluetoothPoweredOff == false)
	}
}
