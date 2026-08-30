//
//  BLEPairingHintTests.swift
//  MeshtasticTests
//
//  Covers the pure-logic pieces of the issue #2057 fix (custom-PIN BLE pairing sheet
//  auto-dismissing): the persisted paired-peripheral hint used to pick the connect
//  timeout, and the classification of notify-state errors into pairing failures vs.
//  benign per-characteristic errors.
//

import Foundation
import CoreBluetooth
import Testing

@testable import Meshtastic

// Serialized: these tests share global UserDefaults state (`pairedPeripheralIds`),
// so they must not run in parallel with each other.
@Suite("Paired peripheral hint", .serialized)
final class PairedPeripheralHintTests {

	private let idA = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
	private let idB = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!

	/// Snapshot of the real persisted value, captured before each test and restored in `deinit`
	/// so this suite leaves no residue for later tests to observe.
	private let originalPairedIds: [String]

	/// Swift Testing creates a fresh instance per test, so `init`/`deinit` act as per-test
	/// setup/teardown: start every test from a clean slate, then restore the original value.
	init() {
		originalPairedIds = UserDefaults.pairedPeripheralIds
		UserDefaults.pairedPeripheralIds = []
	}

	deinit {
		UserDefaults.pairedPeripheralIds = originalPairedIds
	}

	@Test func rememberMakesPeripheralKnown() {
		#expect(UserDefaults.isPairedPeripheral(idA) == false)

		UserDefaults.rememberPairedPeripheral(idA)

		#expect(UserDefaults.isPairedPeripheral(idA))
		#expect(UserDefaults.isPairedPeripheral(idB) == false)
	}

	@Test func rememberIsIdempotent() {
		UserDefaults.rememberPairedPeripheral(idA)
		UserDefaults.rememberPairedPeripheral(idA)

		#expect(UserDefaults.pairedPeripheralIds == [idA.uuidString])
	}

	@Test func forgetRemovesOnlyThatPeripheral() {
		UserDefaults.rememberPairedPeripheral(idA)
		UserDefaults.rememberPairedPeripheral(idB)

		UserDefaults.forgetPairedPeripheral(idA)

		#expect(UserDefaults.isPairedPeripheral(idA) == false)
		#expect(UserDefaults.isPairedPeripheral(idB))
	}

	@Test func forgetUnknownPeripheralIsNoOp() {
		UserDefaults.rememberPairedPeripheral(idB)

		UserDefaults.forgetPairedPeripheral(idA)

		#expect(UserDefaults.pairedPeripheralIds == [idB.uuidString])
	}

	@Test func storedIdsAreSorted() {
		UserDefaults.rememberPairedPeripheral(idB)
		UserDefaults.rememberPairedPeripheral(idA)

		#expect(UserDefaults.pairedPeripheralIds == [idA.uuidString, idB.uuidString].sorted())
	}
}

@Suite("BLE pairing failure classification")
struct BLEPairingFailureTests {

	@Test func authAndEncryptionAttErrorsArePairingFailures() {
		#expect(BLEConnection.isPairingFailure(CBATTError(.insufficientAuthentication)))
		#expect(BLEConnection.isPairingFailure(CBATTError(.insufficientEncryption)))
		#expect(BLEConnection.isPairingFailure(CBATTError(.insufficientAuthorization)))
	}

	@Test func benignAttErrorsAreNotPairingFailures() {
		// e.g. a characteristic that doesn't support notifications — must not fail an
		// otherwise-good connect.
		#expect(BLEConnection.isPairingFailure(CBATTError(.writeNotPermitted)) == false)
		#expect(BLEConnection.isPairingFailure(CBATTError(.requestNotSupported)) == false)
	}

	@Test func encryptionAndRemovedPairingCbErrorsArePairingFailures() {
		#expect(BLEConnection.isPairingFailure(CBError(.encryptionTimedOut)))
		#expect(BLEConnection.isPairingFailure(CBError(.peerRemovedPairingInformation)))
	}

	@Test func unrelatedCbErrorsAreNotPairingFailures() {
		#expect(BLEConnection.isPairingFailure(CBError(.connectionTimeout)) == false)
		#expect(BLEConnection.isPairingFailure(CBError(.peripheralDisconnected)) == false)
	}

	@Test func genericErrorsAreNotPairingFailures() {
		let generic = NSError(domain: "com.example.test", code: 42)
		#expect(BLEConnection.isPairingFailure(generic) == false)
	}
}
