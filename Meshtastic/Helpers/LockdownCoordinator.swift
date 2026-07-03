//
//  LockdownCoordinator.swift
//  Meshtastic
//
//  Drives the per-BLE-connection lockdown state machine for hardened-firmware
//  nodes (MESHTASTIC_LOCKDOWN). Contract: specs/007-lockdown-mode/contracts/coordinator-protocol.md.
//
//  Threading: all public state mutation is @MainActor. Inbound BLE callbacks
//  forwarded from AccessoryManager already hop to MainActor via the existing
//  receive path; outbound BLE sends flow through AccessoryManager's serial
//  send path without further coordination.
//
import Foundation
import OSLog
import MeshtasticProtobufs

/// Outbound dependency the coordinator needs from AccessoryManager.
/// Implementations MUST build the AdminMessage.lockdown_auth packet with:
///   - MeshPacket.to = myNodeNum
///   - MeshPacket.from unset (proto default 0; firmware treats as local PhoneAPI)
///   - MeshPacket.channel = 0, wantAck = true
///   - MeshPacket.hopLimit = hopStart = 7, priority = .reliable
///   - MeshPacket.decoded.portnum = .adminApp
///   - MeshPacket.decoded.payload = AdminMessage{lockdownAuth: ...}.serializedData()
///   - MeshPacket.pkiEncrypted MUST NOT be set
@MainActor
protocol LockdownSender: AnyObject {
	/// Connected device's myNodeNum (0 if MyInfo not yet received).
	var myNodeNum: UInt32 { get }
	func sendLockdownAuth(passphrase: Data,
						  bootsRemaining: UInt32,
						  validUntilEpoch: UInt32,
						  maxSessionSeconds: UInt32,
						  lockNow: Bool)
}

@MainActor
final class LockdownCoordinator: ObservableObject {

	// MARK: Observable

	@Published private(set) var state: LockdownState = .none

	/// `true` iff `state == .unlocked(...)`. Convenience for views that gate
	/// banners or actions on the session being authorized.
	var sessionAuthorized: Bool {
		if case .unlocked = state { return true }
		return false
	}

	/// `true` when the current state requires the user to act before they can
	/// reach normal app surface. Non-lockdown firmware leaves state at .none,
	/// which returns false here. Views use this to suppress action-prompting
	/// banners that target config the user cannot reach. See FR-013.
	var isBlockingSession: Bool {
		switch state {
		case .needsProvision, .locked, .unlockFailed, .unlockBackoff:
			return true
		case .none, .unlocked, .lockNowAcknowledged:
			return false
		}
	}

	// MARK: Collaborators

	private weak var sender: LockdownSender?
	private let store: LockdownPassphraseStoring
	private let logger = Logger(subsystem: "gvh.MeshtasticClient", category: "Lockdown")

	// MARK: Internal per-connection flags

	private var currentPeripheralID: UUID?
	private var wasAutoAttempt = false
	private var pendingPassphrase: String?
	private var pendingBootsRemaining: UInt32 = 0
	private var pendingValidUntilEpoch: UInt32 = 0
	private var pendingMaxSessionSeconds: UInt32 = 0
	private var pendingLockNow = false

	/// Returns the coordinator to passphrase entry when an unlock backoff
	/// deadline passes. Without this the non-dismissable sheet counts down to
	/// "0 s" and stays there — the firmware only reports backoff in response to
	/// an attempt; it does not push a new status when the window elapses.
	private var backoffExpiryTask: Task<Void, Never>?

	// MARK: Init

	init(sender: LockdownSender? = nil,
		 store: LockdownPassphraseStoring = LockdownPassphraseStore.shared) {
		self.sender = sender
		self.store = store
	}

	/// AccessoryManager wires itself in after both objects exist (avoids an
	/// init-order cycle in MeshtasticApp).
	func setSender(_ sender: LockdownSender) {
		self.sender = sender
	}

	// MARK: BLE lifecycle

	/// Called when a fresh BLE connection comes up. Firmware requires re-auth
	/// on every new connection, even if storage is already unlocked.
	func onConnect(peripheralID: UUID) {
		currentPeripheralID = peripheralID
		wasAutoAttempt = false
		clearPendingPassphrase()
		pendingLockNow = false
		cancelBackoffExpiry()
		state = .none
	}

	func onDisconnect() {
		// If Lock Now was in flight, the BLE drop is itself the ack.
		if pendingLockNow {
			pendingLockNow = false
			state = .lockNowAcknowledged
		} else {
			state = .none
		}
		wasAutoAttempt = false
		clearPendingPassphrase()
		cancelBackoffExpiry()
		currentPeripheralID = nil
	}

	// MARK: Inbound

	/// Route an inbound LockdownStatus. Caller is the FromRadio dispatcher in
	/// AccessoryManager, which has already destructured the oneof.
	func handle(_ status: LockdownStatus) {
		logger.info("LockdownStatus state=\(String(describing: status.state)) reason='\(status.lockReason, privacy: .public)' boots=\(status.bootsRemaining) until=\(status.validUntilEpoch) backoff=\(status.backoffSeconds)")
		// A fresh status supersedes any running backoff countdown; entering a new
		// backoff re-arms it in enterBackoff.
		cancelBackoffExpiry()
		switch status.state {
		case .needsProvision:
			state = .needsProvision
		case .locked:
			handleLocked(reason: status.lockReason)
		case .unlocked:
			handleUnlocked(bootsRemaining: status.bootsRemaining,
						   validUntilEpoch: status.validUntilEpoch)
		case .unlockFailed:
			handleUnlockFailed(backoffSeconds: status.backoffSeconds)
		case .disabled:
			// Lockdown supported but not active (never provisioned, or explicitly
			// disabled). Functionally equivalent to .none: no blocking UI.
			state = .none
		case .unspecified, .UNRECOGNIZED:
			// Forward-compat: ignore. spec.md Assumptions calls this out.
			logger.warning("Ignoring LockdownStatus with unspecified/unrecognized state")
		}
	}

	private func handleLocked(reason: String) {
		// Lock Now ack races the BLE disconnect; the first one wins.
		if pendingLockNow {
			pendingLockNow = false
			state = .lockNowAcknowledged
			return
		}
		// Auto-replay cached passphrase if we have one for this peripheral.
		if let peripheralID = currentPeripheralID,
		   let stored = store.get(peripheralID: peripheralID),
		   let data = stored.passphrase.data(using: .utf8) {
			logger.info("Auto-replaying cached passphrase (reason=\(reason, privacy: .public))")
			wasAutoAttempt = true
			pendingPassphrase = stored.passphrase
			pendingBootsRemaining = stored.bootsRemaining
			pendingValidUntilEpoch = stored.validUntilEpoch
			pendingMaxSessionSeconds = stored.maxSessionSeconds
			sender?.sendLockdownAuth(passphrase: data,
									 bootsRemaining: stored.bootsRemaining,
									 validUntilEpoch: stored.validUntilEpoch,
									 maxSessionSeconds: stored.maxSessionSeconds,
									 lockNow: false)
			return
		}
		state = .locked(reason: reason)
	}

	private func handleUnlocked(bootsRemaining: UInt32, validUntilEpoch: UInt32) {
		// If a user submit (or auto-replay) is in flight, persist the passphrase.
		if let peripheralID = currentPeripheralID,
		   let passphrase = pendingPassphrase {
			let stored = StoredPassphrase(passphrase: passphrase,
										  bootsRemaining: pendingBootsRemaining,
										  validUntilEpoch: pendingValidUntilEpoch,
										  maxSessionSeconds: pendingMaxSessionSeconds)
			let ok = store.save(peripheralID: peripheralID, stored)
			if !ok {
				logger.warning("Failed to save passphrase for peripheral \(peripheralID.uuidString, privacy: .public)")
			}
		}
		clearPendingPassphrase()
		wasAutoAttempt = false
		state = .unlocked(bootsRemaining: bootsRemaining, validUntilEpoch: validUntilEpoch)
	}

	private func handleUnlockFailed(backoffSeconds: UInt32) {
		let wasAuto = wasAutoAttempt
		wasAutoAttempt = false
		clearPendingPassphrase()
		if wasAuto {
			if backoffSeconds > 0 {
				logger.info("Auto-unlock rate-limited (backoff=\(backoffSeconds)s)")
				enterBackoff(seconds: backoffSeconds)
			} else {
				// Cached passphrase is wrong (likely rotated server-side).
				if let peripheralID = currentPeripheralID {
					store.delete(peripheralID: peripheralID)
				}
				logger.info("Auto-unlock wrong passphrase; cleared cache")
				state = .locked(reason: "auto_replay_wrong_passphrase")
			}
		} else {
			if backoffSeconds > 0 {
				enterBackoff(seconds: backoffSeconds)
			} else {
				state = .unlockFailed
			}
		}
	}

	private func enterBackoff(seconds: UInt32) {
		state = .unlockBackoff(deadline: Date(timeIntervalSinceNow: TimeInterval(seconds)))
		backoffExpiryTask?.cancel()
		backoffExpiryTask = Task { [weak self] in
			try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
			guard let self, !Task.isCancelled else { return }
			if case .unlockBackoff = self.state {
				self.state = .locked(reason: "needs_auth")
			}
		}
	}

	// MARK: UI-initiated

	func submitPassphrase(_ passphrase: String,
						  bootsRemaining: UInt32,
						  validUntilEpoch: UInt32,
						  maxSessionSeconds: UInt32 = 0) {
		guard let sender else {
			logger.error("submitPassphrase called but no sender wired")
			return
		}
		guard let data = passphrase.data(using: .utf8), !data.isEmpty, data.count <= 32 else {
			logger.error("Rejected submit: passphrase out of 1..32 byte range")
			return
		}
		pendingPassphrase = passphrase
		pendingBootsRemaining = bootsRemaining
		pendingValidUntilEpoch = validUntilEpoch
		pendingMaxSessionSeconds = maxSessionSeconds
		wasAutoAttempt = false
		// Hide the sheet while we wait for the firmware response.
		state = .none
		sender.sendLockdownAuth(passphrase: data,
								bootsRemaining: bootsRemaining,
								validUntilEpoch: validUntilEpoch,
								maxSessionSeconds: maxSessionSeconds,
								lockNow: false)
	}

	func lockNow() {
		guard let sender else { return }
		pendingLockNow = true
		sender.sendLockdownAuth(passphrase: Data(),
								bootsRemaining: 0,
								validUntilEpoch: 0,
								maxSessionSeconds: 0,
								lockNow: true)
	}

	func forgetCachedPassphrase() {
		guard let peripheralID = currentPeripheralID else { return }
		store.delete(peripheralID: peripheralID)
	}

	// MARK: Private helpers

	private func cancelBackoffExpiry() {
		backoffExpiryTask?.cancel()
		backoffExpiryTask = nil
	}

	/// Wipes the in-memory pending passphrase. Called at every state-transition
	/// boundary so the string lives in memory only for the request/response
	/// window. See NFR-002 in spec.md.
	private func clearPendingPassphrase() {
		pendingPassphrase = nil
		pendingBootsRemaining = 0
		pendingValidUntilEpoch = 0
		pendingMaxSessionSeconds = 0
	}
}
