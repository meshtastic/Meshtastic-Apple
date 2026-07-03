//
//  LockdownState.swift
//  Meshtastic
//
//  Per-BLE-connection lockdown state, driven by FromRadio.lockdown_status.
//  See specs/007-lockdown-mode/data-model.md for the state diagram.
//
import Foundation

enum LockdownState: Equatable {
	/// Pre-handshake, non-lockdown firmware, or post-disconnect reset.
	case none

	/// Firmware has never been provisioned. Show "set a passphrase" UI.
	case needsProvision

	/// Storage is locked or this connection has not authed yet.
	/// `reason` is the firmware-supplied `lock_reason` string
	/// (e.g. "needs_auth", "token_expired"); unknown values are still locked.
	case locked(reason: String)

	/// Session authorized. TTL fields mirror firmware:
	///   - `bootsRemaining == 0` means firmware default applies
	///   - `validUntilEpoch == 0` means no wall-clock expiry
	case unlocked(bootsRemaining: UInt32, validUntilEpoch: UInt32)

	/// Wrong passphrase, no rate-limit. UI re-enables the Submit button.
	case unlockFailed

	/// Rate-limited. `deadline` is captured at receive time so the countdown
	/// survives a foreground/background cycle; views derive seconds remaining
	/// from `deadline.timeIntervalSinceNow`.
	case unlockBackoff(deadline: Date)

	/// Synthetic. Resolved by the next inbound LOCKED status (or BLE
	/// disconnect, whichever first) after a user-initiated Lock Now. UI
	/// uses this to disconnect gracefully and show a brief confirmation.
	case lockNowAcknowledged
}
