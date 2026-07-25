//
//  BLETransportPeripheralResolutionTests.swift
//  MeshtasticTests
//
//  Regression coverage for the connect path that broke after #2183's follow-up fix
//  ("actually await discovery/scan shutdown before Step 1 pairs").
//
//  The failure: `BLETransport.connect(to:)` resolved its `CBPeripheral` *only* from the
//  `discoveredPeripherals` scan cache. `stopScanning()` clears that cache, and Step 0 of
//  `AccessoryManager.connect(to:)` deliberately stops discovery before Step 1 connects — so
//  once that stop became genuinely awaited (rather than a detached Task that usually lost the
//  race), the cache was *always* empty by the time `connect(to:)` ran. It threw
//  "Peripheral not found" immediately and `centralManager.connect(_:)` was never called, so the
//  radio never saw a connection attempt at all — it just kept advertising while the app looped
//  on "Attempt 2 of 2".
//
//  The fix: on a cache miss, fall back to `retrievePeripherals(withIdentifiers:)`, which is the
//  CoreBluetooth API intended for reconnecting to a known peripheral by identifier without
//  scanning first.
//
//  `CBPeripheral` has no public initializer and can't be produced in a test, so these tests
//  assert the observable half of the contract: that the cache-miss fallback is *consulted*, with
//  the right identifier. That is exactly what regressed — the old cache-only `guard` returned
//  without ever asking CoreBluetooth. If anyone reinstates a cache-only lookup, the retriever
//  goes uncalled and these tests fail.
//

import CoreBluetooth
import Foundation
import Testing

@testable import Meshtastic

/// Records the identifiers the cache-miss fallback was asked for. A class + lock rather than an
/// actor because the retriever seam is a synchronous `@Sendable` closure.
final class PeripheralLookupRecorder: @unchecked Sendable {
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

@Suite("BLETransport peripheral resolution")
struct BLETransportPeripheralResolutionTests {

	private func makeDevice(id: UUID = UUID()) -> Device {
		Device(id: id, name: "Mock Radio", transportType: .ble, identifier: id.uuidString)
	}

	/// The core regression: with an empty discovery cache — the guaranteed state after Step 0's
	/// `stopDiscovery()` — `connect(to:)` must still try to resolve the peripheral through
	/// CoreBluetooth instead of bailing out immediately.
	@Test func cacheMissConsultsCoreBluetoothFallback() async throws {
		let transport = BLETransport()
		let recorder = PeripheralLookupRecorder()
		await transport.setPeripheralRetrieverForTesting { uuid in
			recorder.record(uuid)
			return nil
		}

		let device = makeDevice()
		// Still throws, because the seam can't manufacture a CBPeripheral. The point is *when*
		// it throws: after consulting CoreBluetooth, not before.
		await #expect(throws: AccessoryError.self) {
			_ = try await transport.connect(to: device)
		}

		#expect(recorder.callCount == 1, "a cache miss must fall back to retrievePeripherals(withIdentifiers:) — the cache-only guard was the #2183 follow-up regression")
		#expect(recorder.requestedIdentifiers.first == device.id, "the fallback must be asked for the device's own identifier")
	}

	/// Same assertion, but reached the way the real bug did: discovery runs, gets stopped (which
	/// is what wipes the cache), and only then does the connect happen.
	@Test func fallbackIsConsultedAfterStopActiveDiscovery() async throws {
		let transport = BLETransport()
		let recorder = PeripheralLookupRecorder()
		await transport.setPeripheralRetrieverForTesting { uuid in
			recorder.record(uuid)
			return nil
		}

		await transport.stopActiveDiscovery()

		let device = makeDevice()
		await #expect(throws: AccessoryError.self) {
			_ = try await transport.connect(to: device)
		}

		#expect(recorder.callCount == 1, "stopActiveDiscovery() clears discoveredPeripherals, so the connect path must not depend on that cache alone")
	}

	/// A non-UUID identifier used to hit `UUID(uuidString:)!` and crash the app. It should be a
	/// thrown error, and it should short-circuit before any CoreBluetooth lookup.
	@Test func nonUUIDIdentifierThrowsInsteadOfCrashing() async throws {
		let transport = BLETransport()
		let recorder = PeripheralLookupRecorder()
		await transport.setPeripheralRetrieverForTesting { uuid in
			recorder.record(uuid)
			return nil
		}

		let device = Device(id: UUID(), name: "Bad Identifier", transportType: .ble, identifier: "not-a-uuid")
		await #expect(throws: AccessoryError.self) {
			_ = try await transport.connect(to: device)
		}

		#expect(recorder.callCount == 0, "an unparseable identifier can't be looked up, so CoreBluetooth should never be asked")
	}
}
