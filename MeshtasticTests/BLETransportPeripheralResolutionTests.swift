//
//  BLETransportPeripheralResolutionTests.swift
//  MeshtasticTests
//
//  Regression coverage for the connect path that broke after #2183's follow-up fix
//  ("actually await discovery/scan shutdown before Step 1 pairs").
//
//  `BLETransport.connect(to:)` resolved its `CBPeripheral` *only* from the
//  `discoveredPeripherals` scan cache. `stopScanning()` clears that cache, and Step 0 of
//  `AccessoryManager.connect(to:)` deliberately stops discovery before Step 1 connects — so once
//  that stop became genuinely awaited (rather than a detached Task that usually lost the race),
//  the cache was *always* empty by the time `connect(to:)` ran. It threw immediately and
//  `centralManager.connect(_:)` was never called at all.
//
//  The fix: on a cache miss, fall back to `retrievePeripherals(withIdentifiers:)`.
//
//  `CBPeripheral` has no public initializer (`CBPeer.init` is `NS_UNAVAILABLE`) and can't be
//  produced in a test, so these tests assert the observable half of the contract: that the
//  cache-miss fallback is *consulted*, with the right identifier. That is exactly what regressed.
//  If anyone reinstates a cache-only lookup, the retriever goes uncalled and these tests fail.
//  The success half — retriever returns a peripheral, cache gets re-seeded, a second resolve hits
//  the cache — is not reachable through this seam and remains uncovered.
//

import CoreBluetooth
import Foundation
import Testing

@testable import Meshtastic

/// Records the identifiers the cache-miss fallback was asked for. A class + lock rather than an
/// actor because the retriever seam is a synchronous `@Sendable` closure, so it can't `await`.
private final class PeripheralLookupRecorder: @unchecked Sendable {
	private let lock = NSLock()
	private var _requestedIdentifiers: [UUID] = []

	var requestedIdentifiers: [UUID] {
		lock.lock()
		defer { lock.unlock() }
		return _requestedIdentifiers
	}

	var callCount: Int { requestedIdentifiers.count }

	func record(_ uuid: UUID) {
		lock.lock()
		defer { lock.unlock() }
		_requestedIdentifiers.append(uuid)
	}
}

// Bounded for the same reason as `BLETransportStatusUpdatesTests`: `connect(to:)` suspends on a
// `withCheckedThrowingContinuation` that only a `CBCentralManagerDelegate` callback resumes, and
// no such callback ever arrives on a simulator. Today every test here fails the `resolvePeripheral`
// guard before reaching that continuation, but a future test that gets past it would hang
// indefinitely rather than fail.
@Suite("BLETransport peripheral resolution", .timeLimit(.minutes(1)))
struct BLETransportPeripheralResolutionTests {

	/// `id` and `identifier` are deliberately *different* UUIDs. `resolvePeripheral(for:)` parses
	/// `identifier` (the CoreBluetooth peripheral UUID), not `id`; these two fields genuinely
	/// diverge for other transports (`SerialTransport` hashes a port path into `id`,
	/// `TCPTransport` hashes a connection string), so a fixture that made them equal would let an
	/// `id`/`identifier` mix-up pass unnoticed.
	private func makeDevice(id: UUID = UUID(), peripheralUUID: UUID) -> Device {
		Device(id: id, name: "Mock Radio", transportType: .ble, identifier: peripheralUUID.uuidString)
	}

	/// `AccessoryError` is not `Equatable`, so `#expect(throws:)` can only match the *type* — and
	/// `connect(to:)` throws four distinct `.connectionFailed` payloads within a dozen lines
	/// ("Peripheral not found", "Connect request while an active connection exists", "BLE
	/// transport is busy: already connecting or connected", "Bluetooth not initialized"). A
	/// type-only assertion stays green if a regression makes the connect fail for one of the other
	/// three reasons, so pin the exact case and message instead.
	private func expectPeripheralNotFound(
		_ context: String,
		_ body: () async throws -> Void
	) async {
		do {
			try await body()
			Issue.record("\(context): connect(to:) must throw when the peripheral can't be resolved")
		} catch AccessoryError.connectionFailed(let message) {
			#expect(message == "Peripheral not found", "\(context): unexpected connectionFailed payload")
		} catch {
			Issue.record("\(context): expected AccessoryError.connectionFailed, got \(error)")
		}
	}

	/// The core regression: with an empty discovery cache — the guaranteed state after Step 0's
	/// `stopDiscovery()` — `connect(to:)` must still try to resolve the peripheral through
	/// CoreBluetooth instead of bailing out immediately.
	@Test func cacheMissConsultsCoreBluetoothFallback() async {
		let recorder = PeripheralLookupRecorder()
		let transport = BLETransport(peripheralRetriever: { uuid in
			recorder.record(uuid)
			return nil
		})

		let peripheralUUID = UUID()
		let device = makeDevice(peripheralUUID: peripheralUUID)
		#expect(device.id != peripheralUUID, "fixture must keep id and identifier distinct or the assertion below is vacuous")

		// Still throws, because the seam can't manufacture a CBPeripheral. The point is *when*
		// it throws: after consulting CoreBluetooth, not before.
		await expectPeripheralNotFound("cache miss") {
			_ = try await transport.connect(to: device)
		}

		#expect(
			recorder.requestedIdentifiers == [peripheralUUID],
			"a cache miss must fall back to retrievePeripherals(withIdentifiers:) exactly once, asked for the device's own identifier — the cache-only guard was the #2183 follow-up regression"
		)
	}

	/// Same assertion, reached through `stopActiveDiscovery()` — the call Step 0 makes, and the
	/// one that wipes `discoveredPeripherals`. Note this exercises the cache-clearing half only:
	/// `discoverDevices()` is never started, so `discoverySetupTask` is nil and
	/// `stopActiveDiscovery()`'s cancel-and-await path is skipped.
	@Test func fallbackIsConsultedAfterStopActiveDiscovery() async {
		let recorder = PeripheralLookupRecorder()
		let transport = BLETransport(peripheralRetriever: { uuid in
			recorder.record(uuid)
			return nil
		})

		await transport.stopActiveDiscovery()

		let peripheralUUID = UUID()
		let device = makeDevice(peripheralUUID: peripheralUUID)
		await expectPeripheralNotFound("after stopActiveDiscovery") {
			_ = try await transport.connect(to: device)
		}

		#expect(
			recorder.requestedIdentifiers == [peripheralUUID],
			"stopActiveDiscovery() clears discoveredPeripherals, so the connect path must not depend on that cache alone"
		)
	}

	/// A non-UUID identifier used to hit `UUID(uuidString:)!` and crash the app. It should be a
	/// thrown error, and it should short-circuit before any CoreBluetooth lookup.
	@Test func nonUUIDIdentifierThrowsInsteadOfCrashing() async {
		let recorder = PeripheralLookupRecorder()
		let transport = BLETransport(peripheralRetriever: { uuid in
			recorder.record(uuid)
			return nil
		})

		let device = Device(id: UUID(), name: "Bad Identifier", transportType: .ble, identifier: "not-a-uuid")
		await expectPeripheralNotFound("non-UUID identifier") {
			_ = try await transport.connect(to: device)
		}

		#expect(recorder.callCount == 0, "an unparseable identifier can't be looked up, so CoreBluetooth should never be asked")
	}
}
