# Data Model: Lockdown Mode

## `LockdownState` — Meshtastic/Model/LockdownState.swift (new)

```swift
import Foundation

/// Per-BLE-connection lockdown state, driven by FromRadio.lockdown_status.
/// `Equatable` so SwiftUI can diff it across view updates.
enum LockdownState: Equatable {
    /// Pre-handshake, non-lockdown firmware, or post-disconnect reset.
    case none

    /// Firmware has never been provisioned. Show "set a passphrase" UI.
    case needsProvision

    /// Storage is locked or this connection has not authed yet.
    /// `reason` is the firmware-supplied `lock_reason` string (e.g. "needs_auth", "token_expired").
    case locked(reason: String)

    /// Session authorized. TTL fields mirror firmware:
    ///   - `bootsRemaining == 0` means firmware default applies
    ///   - `validUntilEpoch == 0` means no wall-clock expiry
    case unlocked(bootsRemaining: UInt32, validUntilEpoch: UInt32)

    /// Wrong passphrase, no rate-limit. UI re-enables the Submit button.
    case unlockFailed

    /// Rate-limited. `deadline` is captured at receive time so the countdown
    /// survives an app background/foreground cycle (the user-visible
    /// `secondsRemaining` is recomputed from `deadline` on every render).
    case unlockBackoff(secondsRemaining: Int, deadline: Date)

    /// Synthetic state — resolved by the next inbound LOCKED status (or BLE
    /// disconnect, whichever first) after a user-initiated Lock Now.
    /// UI uses this to disconnect gracefully and show a brief confirmation.
    case lockNowAcknowledged
}
```

### State transitions

```
┌─────────┐
│  .none  │ ◀── onConnect() or onDisconnect()
└────┬────┘
     │
     │ handle(status) where status.state == NEEDS_PROVISION
     ▼
┌──────────────────┐
│ .needsProvision  │
└────┬─────────────┘
     │ submitPassphrase(...)
     │ handle(UNLOCKED) ──────────────┐
     ▼                                ▼
┌────────────────┐               ┌────────────┐
│ .locked(...)   │ ──────────▶   │ .unlocked  │
└────┬───────────┘ submit+OK    └────┬──────┘
     │                                │
     │ submit + UNLOCK_FAILED          │ lockNow()
     │  (backoff == 0)                 │ + handle(LOCKED) [or disconnect]
     ▼                                 ▼
┌────────────────┐               ┌──────────────────────┐
│ .unlockFailed  │               │ .lockNowAcknowledged │
└────────────────┘               └──────────────────────┘
     │ retry → back to .locked              │
     │                                       │ → BluetoothManager disconnect →
     │ submit + UNLOCK_FAILED                 │   onDisconnect() → .none
     │  (backoff > 0)                         │
     ▼
┌────────────────────┐
│ .unlockBackoff     │
└────────────────────┘
     │ deadline elapses
     │ user retries
     ▼ back to .locked
```

## `StoredPassphrase` — internal to Meshtastic/Helpers/LockdownPassphraseStore.swift

```swift
struct StoredPassphrase: Equatable {
    let passphrase: String
    let bootsRemaining: UInt32
    let validUntilEpoch: UInt32
}
```

Persistence layout in the Keychain (one item per peripheral):

| Field | Source |
|---|---|
| `kSecClass` | `kSecClassGenericPassword` |
| `kSecAttrService` | `"meshtastic.lockdown.passphrase"` |
| `kSecAttrAccount` | `peripheralID.uuidString` |
| `kSecValueData` | JSON-encoded `StoredPassphrase` (passphrase + UInt32 TTL fields) |
| `kSecAttrAccessible` | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` |

`StoredPassphrase` is encoded with `JSONEncoder()` before being passed to `KeychainHelper.save(...)`. JSON keeps the schema explicit; CBOR would save ~20 bytes and isn't worth a new dependency.

## Internal coordinator state (not persisted)

```swift
final class LockdownCoordinator: ObservableObject {
    @Published private(set) var state: LockdownState
    @Published private(set) var sessionAuthorized: Bool

    private var currentPeripheralID: UUID?
    private var wasAutoAttempt: Bool
    private var pendingPassphrase: String?
    private var pendingBootsRemaining: UInt32
    private var pendingValidUntilEpoch: UInt32
    private var pendingLockNow: Bool
}
```

- `pendingPassphrase` exists only between submit and the response; cleared on success or failure.
- `pendingLockNow` is set by `lockNow()` and cleared when the next `LOCKED` status arrives or the peripheral disconnects.
- `wasAutoAttempt` distinguishes silent-replay failures (clear cached entry) from user-typed failures (preserve cache, show error).
