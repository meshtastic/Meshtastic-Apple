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
struct PairedPeripheralHintTests {

	private let idA = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
	private let idB = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!

	/// Start every test from a clean slate so global UserDefaults state doesn't leak.
	private func reset() {
		UserDefaults.pairedPeripheralIds = []
	}

	@Test func rememberMakesPeripheralKnown() {
		reset()
		#expect(UserDefaults.isPairedPeripheral(idA) == false)

		UserDefaults.rememberPairedPeripheral(idA)

		#expect(UserDefaults.isPairedPeripheral(idA))
		#expect(UserDefaults.isPairedPeripheral(idB) == false)
	}

	@Test func rememberIsIdempotent() {
		reset()
		UserDefaults.rememberPairedPeripheral(idA)
		UserDefaults.rememberPairedPeripheral(idA)

		#expect(UserDefaults.pairedPeripheralIds == [idA.uuidString])
	}

	@Test func forgetRemovesOnlyThatPeripheral() {
		reset()
		UserDefaults.rememberPairedPeripheral(idA)
		UserDefaults.rememberPairedPeripheral(idB)

		UserDefaults.forgetPairedPeripheral(idA)

		#expect(UserDefaults.isPairedPeripheral(idA) == false)
		#expect(UserDefaults.isPairedPeripheral(idB))
	}

	@Test func forgetUnknownPeripheralIsNoOp() {
		reset()
		UserDefaults.rememberPairedPeripheral(idB)

		UserDefaults.forgetPairedPeripheral(idA)

		#expect(UserDefaults.pairedPeripheralIds == [idB.uuidString])
	}

	@Test func storedIdsAreSorted() {
		reset()
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
