//
//  LockdownCoordinatorTests.swift
//  MeshtasticTests
//
//  State-machine unit tests for LockdownCoordinator covering all transitions
//  enumerated in specs/007-lockdown-mode/data-model.md. Tests use a fake
//  LockdownSender and a fake LockdownPassphraseStoring so no BLE or Keychain
//  is touched.
//
import XCTest
@testable import Meshtastic
@testable import MeshtasticProtobufs

@MainActor
final class LockdownCoordinatorTests: XCTestCase {

	// MARK: Fakes

	final class FakeLockdownSender: LockdownSender {
		var myNodeNum: UInt32 = 0x1234_5678

		struct Call: Equatable {
			let passphrase: Data
			let bootsRemaining: UInt32
			let validUntilEpoch: UInt32
			let maxSessionSeconds: UInt32
			let lockNow: Bool
		}
		var calls: [Call] = []

		func sendLockdownAuth(passphrase: Data,
							  bootsRemaining: UInt32,
							  validUntilEpoch: UInt32,
							  maxSessionSeconds: UInt32,
							  lockNow: Bool) {
			calls.append(.init(passphrase: passphrase,
							   bootsRemaining: bootsRemaining,
							   validUntilEpoch: validUntilEpoch,
							   maxSessionSeconds: maxSessionSeconds,
							   lockNow: lockNow))
		}
	}

	final class FakePassphraseStore: LockdownPassphraseStoring {
		var entries: [UUID: StoredPassphrase] = [:]

		func get(peripheralID: UUID) -> StoredPassphrase? { entries[peripheralID] }

		@discardableResult
		func save(peripheralID: UUID, _ stored: StoredPassphrase) -> Bool {
			entries[peripheralID] = stored
			return true
		}

		@discardableResult
		func delete(peripheralID: UUID) -> Bool {
			entries.removeValue(forKey: peripheralID) != nil
		}
	}

	// MARK: Helpers

	private let peripheralID = UUID(uuidString: "12345678-1234-1234-1234-123456789012")!

	private func makeCoordinator() -> (LockdownCoordinator, FakeLockdownSender, FakePassphraseStore) {
		let sender = FakeLockdownSender()
		let store = FakePassphraseStore()
		let coordinator = LockdownCoordinator(sender: sender, store: store)
		return (coordinator, sender, store)
	}

	private func makeStatus(state: LockdownStatus.State,
							lockReason: String = "",
							bootsRemaining: UInt32 = 0,
							validUntilEpoch: UInt32 = 0,
							backoffSeconds: UInt32 = 0) -> LockdownStatus {
		var s = LockdownStatus()
		s.state = state
		s.lockReason = lockReason
		s.bootsRemaining = bootsRemaining
		s.validUntilEpoch = validUntilEpoch
		s.backoffSeconds = backoffSeconds
		return s
	}

	// MARK: Initial state

	func testInitialState_isNone() {
		let (coordinator, _, _) = makeCoordinator()
		XCTAssertEqual(coordinator.state, .none)
		XCTAssertFalse(coordinator.sessionAuthorized)
	}

	// MARK: NEEDS_PROVISION (US-2)

	func testHandle_needsProvision_transitionsToNeedsProvision() {
		let (coordinator, _, _) = makeCoordinator()
		coordinator.onConnect(peripheralID: peripheralID)
		coordinator.handle(makeStatus(state: .needsProvision))
		XCTAssertEqual(coordinator.state, .needsProvision)
		XCTAssertFalse(coordinator.sessionAuthorized)
	}

	func testSubmitPassphrase_fromNeedsProvision_sendsAuthAndCachesOnUnlocked() {
		let (coordinator, sender, store) = makeCoordinator()
		coordinator.onConnect(peripheralID: peripheralID)
		coordinator.handle(makeStatus(state: .needsProvision))

		coordinator.submitPassphrase("hunter2", bootsRemaining: 0, validUntilEpoch: 0)
		XCTAssertEqual(sender.calls.count, 1)
		XCTAssertEqual(sender.calls.first?.passphrase, "hunter2".data(using: .utf8))
		XCTAssertFalse(sender.calls.first?.lockNow ?? true)
		// During the wait, state is .none so the sheet hides.
		XCTAssertEqual(coordinator.state, .none)

		coordinator.handle(makeStatus(state: .unlocked, bootsRemaining: 7, validUntilEpoch: 99))
		XCTAssertEqual(coordinator.state, .unlocked(bootsRemaining: 7, validUntilEpoch: 99))
		XCTAssertTrue(coordinator.sessionAuthorized)
		XCTAssertEqual(store.entries[peripheralID]?.passphrase, "hunter2")
	}

	// MARK: LOCKED (US-1, US-4)

	func testHandle_locked_withoutCachedPassphrase_transitionsToLocked() {
		let (coordinator, sender, _) = makeCoordinator()
		coordinator.onConnect(peripheralID: peripheralID)

		coordinator.handle(makeStatus(state: .locked, lockReason: "needs_auth"))

		XCTAssertEqual(coordinator.state, .locked(reason: "needs_auth"))
		XCTAssertTrue(sender.calls.isEmpty, "no auto-replay when cache is empty")
	}

	func testHandle_locked_withCachedPassphrase_autoReplaysSilently() {
		let (coordinator, sender, store) = makeCoordinator()
		store.entries[peripheralID] = StoredPassphrase(passphrase: "cached", bootsRemaining: 3, validUntilEpoch: 42)
		coordinator.onConnect(peripheralID: peripheralID)

		coordinator.handle(makeStatus(state: .locked, lockReason: "needs_auth"))

		// Auto-replay fires; state stays .none so the sheet does not appear.
		XCTAssertEqual(coordinator.state, .none)
		XCTAssertEqual(sender.calls.count, 1)
		XCTAssertEqual(sender.calls.first?.passphrase, "cached".data(using: .utf8))
		XCTAssertEqual(sender.calls.first?.bootsRemaining, 3)
		XCTAssertEqual(sender.calls.first?.validUntilEpoch, 42)
	}

	// MARK: UNLOCK_FAILED (US-1, US-4)

	func testHandle_unlockFailed_userSubmit_withBackoffZero_transitionsToUnlockFailed() {
		let (coordinator, _, _) = makeCoordinator()
		coordinator.onConnect(peripheralID: peripheralID)
		coordinator.handle(makeStatus(state: .locked, lockReason: "needs_auth"))
		coordinator.submitPassphrase("wrong", bootsRemaining: 0, validUntilEpoch: 0)

		coordinator.handle(makeStatus(state: .unlockFailed, backoffSeconds: 0))

		XCTAssertEqual(coordinator.state, .unlockFailed)
		XCTAssertFalse(coordinator.sessionAuthorized)
	}

	func testHandle_unlockFailed_userSubmit_withBackoffNonZero_transitionsToBackoff() {
		let (coordinator, _, _) = makeCoordinator()
		coordinator.onConnect(peripheralID: peripheralID)
		coordinator.handle(makeStatus(state: .locked, lockReason: "needs_auth"))
		coordinator.submitPassphrase("x", bootsRemaining: 0, validUntilEpoch: 0)

		let before = Date()
		coordinator.handle(makeStatus(state: .unlockFailed, backoffSeconds: 30))
		let after = Date()

		guard case .unlockBackoff(let deadline) = coordinator.state else {
			XCTFail("Expected .unlockBackoff, got \(coordinator.state)")
			return
		}
		XCTAssertGreaterThanOrEqual(deadline.timeIntervalSince(before), 30)
		XCTAssertLessThanOrEqual(deadline.timeIntervalSince(after), 30)
	}

	func testHandle_unlockFailed_autoReplay_withBackoffZero_clearsCacheAndTransitionsToLocked() {
		let (coordinator, _, store) = makeCoordinator()
		store.entries[peripheralID] = StoredPassphrase(passphrase: "stale", bootsRemaining: 0, validUntilEpoch: 0)
		coordinator.onConnect(peripheralID: peripheralID)

		// Triggers auto-replay because store has a hit.
		coordinator.handle(makeStatus(state: .locked, lockReason: "needs_auth"))
		// Firmware rejects.
		coordinator.handle(makeStatus(state: .unlockFailed, backoffSeconds: 0))

		XCTAssertEqual(coordinator.state, .locked(reason: "auto_replay_wrong_passphrase"))
		XCTAssertNil(store.entries[peripheralID], "cache should be cleared on auto-replay reject")
	}

	func testHandle_unlockFailed_autoReplay_withBackoffNonZero_preservesCacheAndTransitionsToBackoff() {
		let (coordinator, _, store) = makeCoordinator()
		store.entries[peripheralID] = StoredPassphrase(passphrase: "good", bootsRemaining: 0, validUntilEpoch: 0)
		coordinator.onConnect(peripheralID: peripheralID)

		coordinator.handle(makeStatus(state: .locked, lockReason: "needs_auth"))
		coordinator.handle(makeStatus(state: .unlockFailed, backoffSeconds: 15))

		if case .unlockBackoff = coordinator.state {
			// expected
		} else {
			XCTFail("Expected .unlockBackoff, got \(coordinator.state)")
		}
		XCTAssertEqual(store.entries[peripheralID]?.passphrase, "good", "cache should survive rate-limit")
	}

	func testHandle_unlockBackoff_deadlinePassed_returnsToPassphraseEntry() async throws {
		let (coordinator, _, _) = makeCoordinator()
		coordinator.onConnect(peripheralID: peripheralID)
		coordinator.handle(makeStatus(state: .locked, lockReason: "needs_auth"))
		coordinator.submitPassphrase("x", bootsRemaining: 0, validUntilEpoch: 0)
		coordinator.handle(makeStatus(state: .unlockFailed, backoffSeconds: 1))

		guard case .unlockBackoff = coordinator.state else {
			XCTFail("Expected .unlockBackoff, got \(coordinator.state)")
			return
		}

		// The firmware never pushes a status when the window elapses, so the
		// coordinator must return to entry on its own.
		try await Task.sleep(nanoseconds: 1_500_000_000)
		XCTAssertEqual(coordinator.state, .locked(reason: "needs_auth"),
					   "backoff expiry should return to passphrase entry")
	}

	// MARK: Lock Now (US-3)

	func testLockNow_setsPendingAndSendsEmptyPassphraseAuth() {
		let (coordinator, sender, _) = makeCoordinator()
		coordinator.onConnect(peripheralID: peripheralID)
		coordinator.handle(makeStatus(state: .unlocked, bootsRemaining: 5, validUntilEpoch: 0))

		coordinator.lockNow()

		XCTAssertEqual(sender.calls.count, 1)
		XCTAssertEqual(sender.calls.first?.passphrase, Data())
		XCTAssertTrue(sender.calls.first?.lockNow ?? false)
	}

	func testHandle_locked_withPendingLockNow_transitionsToLockNowAcknowledged() {
		// Keep `sender` named so the weak ref inside the coordinator stays alive.
		let (coordinator, sender, _) = makeCoordinator()
		_ = sender
		coordinator.onConnect(peripheralID: peripheralID)
		coordinator.handle(makeStatus(state: .unlocked, bootsRemaining: 5, validUntilEpoch: 0))
		coordinator.lockNow()

		coordinator.handle(makeStatus(state: .locked, lockReason: "needs_auth"))

		XCTAssertEqual(coordinator.state, .lockNowAcknowledged)
	}

	func testOnDisconnect_withPendingLockNow_transitionsToLockNowAcknowledged() {
		let (coordinator, sender, _) = makeCoordinator()
		_ = sender
		coordinator.onConnect(peripheralID: peripheralID)
		coordinator.handle(makeStatus(state: .unlocked, bootsRemaining: 5, validUntilEpoch: 0))
		coordinator.lockNow()

		coordinator.onDisconnect()

		XCTAssertEqual(coordinator.state, .lockNowAcknowledged)
	}

	func testOnDisconnect_withoutPendingLockNow_transitionsToNone() {
		let (coordinator, sender, _) = makeCoordinator()
		_ = sender
		coordinator.onConnect(peripheralID: peripheralID)
		coordinator.handle(makeStatus(state: .unlocked, bootsRemaining: 5, validUntilEpoch: 0))

		coordinator.onDisconnect()

		XCTAssertEqual(coordinator.state, .none)
	}

	// MARK: Forward-compat (analysis.md G3)

	func testHandle_stateUnspecified_isIgnored() {
		let (coordinator, sender, _) = makeCoordinator()
		coordinator.onConnect(peripheralID: peripheralID)
		coordinator.handle(makeStatus(state: .locked, lockReason: "needs_auth"))
		let stateBefore = coordinator.state

		coordinator.handle(makeStatus(state: .unspecified))

		XCTAssertEqual(coordinator.state, stateBefore, "UNSPECIFIED must not mutate state")
		XCTAssertTrue(sender.calls.isEmpty)
	}

	// MARK: Forget cached passphrase

	func testForgetCachedPassphrase_deletesEntryForConnectedPeripheral() {
		let (coordinator, _, store) = makeCoordinator()
		store.entries[peripheralID] = StoredPassphrase(passphrase: "x", bootsRemaining: 0, validUntilEpoch: 0)
		coordinator.onConnect(peripheralID: peripheralID)

		coordinator.forgetCachedPassphrase()

		XCTAssertNil(store.entries[peripheralID])
	}

	func testForgetCachedPassphrase_noPeripheral_isNoop() {
		let (coordinator, _, store) = makeCoordinator()
		let otherID = UUID()
		store.entries[otherID] = StoredPassphrase(passphrase: "x", bootsRemaining: 0, validUntilEpoch: 0)

		coordinator.forgetCachedPassphrase()

		XCTAssertEqual(store.entries[otherID]?.passphrase, "x")
	}

	// MARK: max_session_seconds (protobufs PR #916)

	func testSubmitPassphrase_threadsMaxSessionSecondsToSenderAndCache() {
		let (coordinator, sender, store) = makeCoordinator()
		coordinator.onConnect(peripheralID: peripheralID)
		coordinator.handle(makeStatus(state: .needsProvision))

		coordinator.submitPassphrase("secret",
									 bootsRemaining: 2,
									 validUntilEpoch: 0,
									 maxSessionSeconds: 1800)

		XCTAssertEqual(sender.calls.first?.maxSessionSeconds, 1800,
					   "Sender must receive the operator-supplied session cap")

		coordinator.handle(makeStatus(state: .unlocked, bootsRemaining: 2, validUntilEpoch: 0))
		XCTAssertEqual(store.entries[peripheralID]?.maxSessionSeconds, 1800,
					   "Session cap must persist with the cached passphrase")
	}

	func testHandle_locked_autoReplay_passesCachedMaxSessionSeconds() {
		let (coordinator, sender, store) = makeCoordinator()
		store.entries[peripheralID] = StoredPassphrase(passphrase: "cached",
													   bootsRemaining: 5,
													   validUntilEpoch: 0,
													   maxSessionSeconds: 600)
		coordinator.onConnect(peripheralID: peripheralID)

		coordinator.handle(makeStatus(state: .locked, lockReason: "needs_auth"))

		XCTAssertEqual(sender.calls.first?.maxSessionSeconds, 600,
					   "Auto-replay must reuse the cached session cap")
	}
}
