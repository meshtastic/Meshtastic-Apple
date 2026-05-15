//
//  LockdownPassphraseStoreTests.swift
//  MeshtasticTests
//
//  Round-trip tests for LockdownPassphraseStore. Uses the real iOS Keychain
//  on the simulator with a test-only service string so production entries are
//  never touched. Each test wipes its key in tearDown.
//
//  These tests require a signed test bundle to write to the Keychain. When
//  running with CODE_SIGNING_ALLOWED=NO (CI without a signing identity, or
//  the project's default xcodebuild invocation in this branch), SecItemAdd
//  returns errSecMissingEntitlement (-34018). setUp probes and skips so the
//  suite doesn't false-fail in unsigned environments. Run with signing
//  enabled to actually exercise the store.
//
import XCTest
@testable import Meshtastic

final class LockdownPassphraseStoreTests: XCTestCase {

	private var store: LockdownPassphraseStore!
	private var testPeripheralID: UUID!

	override func setUpWithError() throws {
		try super.setUpWithError()
		// Probe whether this run can use the Keychain at all.
		let probeKey = "lockdown-tests-probe-\(UUID().uuidString)"
		let probeService = "meshtastic.lockdown.passphrase.tests"
		let status = KeychainHelper.standard.save(
			key: probeKey,
			value: "ok",
			service: probeService,
			accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
			synchronizable: false
		)
		KeychainHelper.standard.delete(key: probeKey, service: probeService, synchronizable: false)
		guard status == errSecSuccess else {
			throw XCTSkip("Keychain unavailable (OSStatus \(status)); test target needs code signing to write to the Keychain.")
		}

		store = LockdownPassphraseStore()
		testPeripheralID = UUID()
	}

	override func tearDown() {
		store?.delete(peripheralID: testPeripheralID)
		store = nil
		testPeripheralID = nil
		super.tearDown()
	}

	func testRead_returnsNilForUnknownPeripheral() {
		XCTAssertNil(store.get(peripheralID: testPeripheralID))
	}

	func testSaveThenRead_roundtripsPassphraseAndTTL() {
		let entry = StoredPassphrase(passphrase: "hunter2",
									 bootsRemaining: 5,
									 validUntilEpoch: 1_234_567)
		XCTAssertTrue(store.save(peripheralID: testPeripheralID, entry))

		let read = store.get(peripheralID: testPeripheralID)
		XCTAssertEqual(read, entry)
	}

	func testSave_overwritesPreviousEntry() {
		let first = StoredPassphrase(passphrase: "first", bootsRemaining: 1, validUntilEpoch: 0)
		let second = StoredPassphrase(passphrase: "second", bootsRemaining: 9, validUntilEpoch: 7)
		XCTAssertTrue(store.save(peripheralID: testPeripheralID, first))
		XCTAssertTrue(store.save(peripheralID: testPeripheralID, second))

		XCTAssertEqual(store.get(peripheralID: testPeripheralID), second)
	}

	func testDelete_removesEntry() {
		let entry = StoredPassphrase(passphrase: "x", bootsRemaining: 0, validUntilEpoch: 0)
		store.save(peripheralID: testPeripheralID, entry)
		XCTAssertNotNil(store.get(peripheralID: testPeripheralID))

		XCTAssertTrue(store.delete(peripheralID: testPeripheralID))
		XCTAssertNil(store.get(peripheralID: testPeripheralID))
	}

	func testDelete_unknownPeripheral_returnsTrue() {
		// delete() returns true for both success and errSecItemNotFound; the
		// store API treats "wasn't there" as a successful no-op.
		XCTAssertTrue(store.delete(peripheralID: UUID()))
	}

	func testEntries_isolatedByPeripheralID() {
		let other = UUID()
		defer { store.delete(peripheralID: other) }

		store.save(peripheralID: testPeripheralID,
				   StoredPassphrase(passphrase: "a", bootsRemaining: 0, validUntilEpoch: 0))
		store.save(peripheralID: other,
				   StoredPassphrase(passphrase: "b", bootsRemaining: 0, validUntilEpoch: 0))

		XCTAssertEqual(store.get(peripheralID: testPeripheralID)?.passphrase, "a")
		XCTAssertEqual(store.get(peripheralID: other)?.passphrase, "b")
	}
}
