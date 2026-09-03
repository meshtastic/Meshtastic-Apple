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

/// A factory-erased radio throws away the pairing this device still holds. Reconnecting
/// cannot fix it, so it must not be retried, and the advice differs from the one for a
/// mistyped PIN even though iOS reports both under the same codes.
///
/// Serialized: these share the persisted `pairedPeripheralIds`, so they must not run in
/// parallel with each other or with the hint suite above.
@Suite("Lost BLE bond", .serialized)
final class LostBondTests {

	private let radio = UUID(uuidString: "00000000-0000-0000-0000-0000000000CC")!
	private let originalPairedIds: [String]

	init() {
		originalPairedIds = UserDefaults.pairedPeripheralIds
		UserDefaults.pairedPeripheralIds = []
	}

	deinit {
		UserDefaults.pairedPeripheralIds = originalPairedIds
	}

	private func isBondLost(_ error: Error) -> Bool {
		guard let accessoryError = error as? AccessoryError, case .bondLost = accessoryError else { return false }
		return true
	}

	private static let pairingCodes: [Error] = [
		CBError(.peerRemovedPairingInformation),
		CBError(.encryptionTimedOut),
		CBATTError(.insufficientAuthentication),
		CBATTError(.insufficientEncryption),
		CBATTError(.insufficientAuthorization)
	]

	// MARK: - Never retried

	@Test func pairingFailuresAreNeverReconnected() {
		// This is what stops the connect: `shouldReconnect == false` sends the error out as
		// `errorWithoutReconnect`, which disables auto-reconnect and cancels the whole connect
		// process instead of retrying it into "Too Many Retries".
		for code in Self.pairingCodes {
			#expect(BLEConnection.shouldReconnect(after: code) == false, "\(code) must not reconnect")
		}
		#expect(BLEConnection.shouldReconnect(after: AccessoryError.bondLost) == false)
	}

	@Test func theThreeRecoverableErrorsStillReconnect() {
		#expect(BLEConnection.shouldReconnect(after: CBATTError(.insufficientResources)))
		#expect(BLEConnection.shouldReconnect(after: CBError(.connectionTimeout)))
		#expect(BLEConnection.shouldReconnect(after: CBError(.peripheralDisconnected)))
	}

	@Test func unrelatedErrorsDoNotReconnect() {
		#expect(BLEConnection.shouldReconnect(after: CBATTError(.writeNotPermitted)) == false)
		#expect(BLEConnection.shouldReconnect(after: NSError(domain: "com.example.test", code: 42)) == false)
	}

	// MARK: - Which advice

	@Test func aRadioWePairedWithBeforeReportsALostBond() {
		for code in Self.pairingCodes {
			UserDefaults.rememberPairedPeripheral(radio)

			let reported = BLEConnection.bondLostError(for: radio, error: code)

			#expect(isBondLost(reported), "\(code) should report a lost bond")
			// Read before clear, in one step: reversing them would answer from an already
			// cleared hint and report the wrong advice.
			#expect(UserDefaults.isPairedPeripheral(radio) == false,
					"the stale pairing is forgotten, so the next attempt gets the long pairing window")
		}
	}

	@Test func aFirstPairingAttemptKeepsItsOwnError() {
		// Never paired with this radio: the same codes mean a wrong or cancelled PIN, which
		// needs the opposite advice, so the original error has to survive.
		let reported = BLEConnection.bondLostError(for: radio, error: CBATTError(.insufficientAuthentication))

		#expect(isBondLost(reported) == false)
		#expect((reported as? CBATTError)?.code == .insufficientAuthentication)
	}

	@Test func benignErrorsPassThroughAndKeepTheBond() {
		UserDefaults.rememberPairedPeripheral(radio)

		let reported = BLEConnection.bondLostError(for: radio, error: CBATTError(.requestNotSupported))

		#expect(isBondLost(reported) == false)
		#expect((reported as? CBATTError)?.code == .requestNotSupported)
		#expect(UserDefaults.isPairedPeripheral(radio), "a benign error is not a bond failure")
	}

	// MARK: - Ignore or end the connection

	@Test func aPairingFailureEndsTheConnectWhereverItLands() {
		// An encryption failure typically hits every subscription, including ones the connect
		// does not gate on.
		for code in Self.pairingCodes {
			let action = BLEConnection.notifyFailure(error: code, isAwaitingConfirmation: true, gatesConnect: false)
			guard case .endConnection = action else {
				Issue.record("\(code) should end the connect")
				continue
			}
		}
	}

	@Test func abenignErrorOnANonGatingCharacteristicIsIgnored() {
		// A radio that does not support notifications on FROMRADIO must not fail an
		// otherwise-good connect.
		let action = BLEConnection.notifyFailure(
			error: CBATTError(.requestNotSupported), isAwaitingConfirmation: true, gatesConnect: false
		)
		guard case .ignore = action else {
			Issue.record("a benign error off the gating path should be ignored")
			return
		}
	}

	@Test func aFailureOnTheGatingCharacteristicEndsTheConnect() {
		let action = BLEConnection.notifyFailure(
			error: CBATTError(.requestNotSupported), isAwaitingConfirmation: true, gatesConnect: true
		)
		guard case .endConnection = action else {
			Issue.record("the connect waits on this subscription, so it cannot be ignored")
			return
		}
	}

	@Test func nothingHappensWhenTheConnectIsNotWaiting() {
		let action = BLEConnection.notifyFailure(
			error: CBError(.peerRemovedPairingInformation), isAwaitingConfirmation: false, gatesConnect: true
		)
		guard case .ignore = action else {
			Issue.record("no connect in flight, nothing to end")
			return
		}
	}

	@Test func theMessageSaysHowToFixIt() {
		let message = AccessoryError.bondLost.errorDescription ?? ""
		#expect(message.contains("forget the radio"))
		#expect(message == AccessoryError.coreBluetoothError(CBError(.peerRemovedPairingInformation)).errorDescription,
				"however it arrives, it reads the same")
	}
}
