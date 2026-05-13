# Contracts: LockdownCoordinator + LockdownSender

## `LockdownCoordinator` — public surface

```swift
@MainActor
final class LockdownCoordinator: ObservableObject {

    // ---- Observable state ----
    @Published private(set) var state: LockdownState
    @Published private(set) var sessionAuthorized: Bool

    // ---- Init ----
    init(sender: LockdownSender, store: LockdownPassphraseStore)

    // ---- Called by BluetoothManager ----

    /// Connection came up; reset per-connection state. Firmware requires
    /// re-auth on every new BLE connection regardless of storage state.
    func onConnect(peripheralID: UUID)

    /// Connection dropped. Resolves `pendingLockNow` to `.lockNowAcknowledged`
    /// if set, otherwise transitions to `.none`. Always sets
    /// `sessionAuthorized = false` and clears `pendingPassphrase`.
    func onDisconnect()

    /// Route an inbound `LockdownStatus` packet (already extracted from
    /// FromRadio.payloadVariant). Coordinator decides:
    ///   • NEEDS_PROVISION → `.needsProvision`
    ///   • LOCKED → auto-replay if cache hit, else `.locked(reason:)`
    ///              (or `.lockNowAcknowledged` if `pendingLockNow == true`)
    ///   • UNLOCKED → save passphrase if it came from a fresh user submit,
    ///                transition to `.unlocked(...)`, set `sessionAuthorized = true`
    ///   • UNLOCK_FAILED → `.unlockFailed` or `.unlockBackoff(...)` depending on
    ///                      `backoff_seconds`; clear cache if `wasAutoAttempt`
    func handle(_ status: Meshtastic_LockdownStatus)

    // ---- Called by UI ----

    /// User-initiated. Pre-conditions: state ∈ {`.needsProvision`, `.locked`,
    /// `.unlockFailed`}. Validation (1..32 byte UTF-8) is the caller's job;
    /// coordinator trusts inputs. Stores `pendingPassphrase` and sends the
    /// LockdownAuth packet via the `LockdownSender`.
    func submitPassphrase(_ passphrase: String,
                          bootsRemaining: UInt32,
                          validUntilEpoch: UInt32)

    /// User-initiated. Sets `pendingLockNow = true` and sends an empty-passphrase
    /// LockdownAuth with `lock_now = true`. UI should also disable navigation
    /// until `state` reaches `.lockNowAcknowledged`.
    func lockNow()

    /// Drop the cached passphrase for the currently-connected peripheral.
    /// No-op if not connected.
    func forgetCachedPassphrase()
}
```

### State-mutation invariants

1. `state` mutations always happen on the main actor.
2. Every inbound `handle(_:)` results in at most one `state` write.
3. `sessionAuthorized` is only `true` while `state == .unlocked(...)`. Any other state implies `sessionAuthorized == false`.
4. `pendingPassphrase` is non-nil only between a `submitPassphrase(...)` call and the next `handle(...)` (success or failure).
5. `pendingLockNow` is non-nil only between a `lockNow()` call and the next `LOCKED` status or disconnect.

## `LockdownSender` — dependency the coordinator needs from BluetoothManager

```swift
protocol LockdownSender: AnyObject {
    /// The connected device's myNodeNum (0 if MyInfo not yet received).
    /// Coordinator uses this for the MeshPacket.to field; the sender method
    /// is also free to no-op (or log) if 0.
    var myNodeNum: UInt32 { get }

    /// Build and send an AdminMessage.lockdown_auth ToRadio packet.
    /// Implementation MUST set:
    ///   • MeshPacket.to    = myNodeNum
    ///   • MeshPacket.from  unset (proto default 0; firmware treats as local PhoneAPI)
    ///   • MeshPacket.channel = 0
    ///   • MeshPacket.wantAck = true
    ///   • MeshPacket.hopLimit / hopStart = 7
    ///   • MeshPacket.priority = .reliable
    ///   • MeshPacket.decoded.portnum = .adminApp
    ///   • MeshPacket.decoded.payload = AdminMessage{lockdownAuth: ...}.serializedData()
    ///   • MeshPacket.pkiEncrypted MUST NOT be set
    func sendLockdownAuth(passphrase: Data,
                          bootsRemaining: UInt32,
                          validUntilEpoch: UInt32,
                          lockNow: Bool)
}
```

`BluetoothManager` conforms by adding `sendLockdownAuth(...)`; the coordinator depends on the protocol so tests can inject a fake.

## Test seams

```swift
// MeshtasticTests/Helpers/LockdownCoordinatorTests.swift
final class FakeLockdownSender: LockdownSender { … }
final class FakeLockdownPassphraseStore: LockdownPassphraseStore { … }
```

Each unit test drives the coordinator through one transition path using fake collaborators. No CoreBluetooth, no Keychain, no XCTestExpectation for BLE timing.
