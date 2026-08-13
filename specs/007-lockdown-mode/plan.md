# Implementation Plan: Lockdown Mode

**Branch**: `007-lockdown-mode` | **Date**: 2026-05-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/007-lockdown-mode/spec.md`

## Summary

Add client-side lockdown handling to Meshtastic-Apple. On the wire: react to `FromRadio.lockdown_status` (field 18) and emit `AdminMessage.lockdown_auth` (field 104) per `meshtastic/protobufs` PR #911. On the client: a single `ObservableObject` coordinator owns the per-connection lockdown state, the existing `BluetoothManager` gains one new send method, the existing `MeshPackets` dispatcher gains one new case, and a new SwiftUI sheet renders the four UI states (provision / locked / unlock-failed / backoff). Cached passphrases live in the iOS Keychain via the existing `KeychainHelper`, keyed by `CBPeripheral.identifier`. A "Lock Now" row goes in `Settings → Security`.

## Technical Context

**Language/Version**: Swift 5.9+ (project ships SwiftPM + Xcode 15)
**Primary Dependencies**: SwiftUI, Combine, CoreBluetooth, SwiftProtobuf (via `MeshtasticProtobufs` local SPM), Keychain Services
**Storage**: iOS Keychain via `Meshtastic/Helpers/KeychainHelper.swift` (existing) — per-peripheral passphrase entries
**Testing**: XCTest under `MeshtasticTests/` (existing target)
**Target Platform**: iOS 16.4+, macCatalyst 14.6+ (deployment targets from `Meshtastic.xcodeproj/project.pbxproj`)
**Project Type**: Native mobile app (single Xcode target with macCatalyst variant)
**Performance Goals**: Submit-to-unlocked ≤ 5 s on a standard BLE link; sheet-render perceptual latency under one frame after state change
**Constraints**: No new third-party dependencies; passphrase bytes never logged at any `Logger` level; the lockdown gate must not block the BLE I/O queue (coordinator state mutations live on `@MainActor`, BLE writes flow through the existing serial queue in `BluetoothManager`)
**Scale/Scope**: One coordinator instance, one connected peripheral at a time, ≤ 32-byte passphrase, ≤ ~200 LOC of net Swift across coordinator + state + store + UI wiring (excluding the new sheet view)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` exists but is unfilled (template placeholders). **No project-level principles to evaluate against.** Recommendation: run `/speckit.constitution` after this plan lands so future features have real gates. For this feature, no gate violations apply.

## Project Structure

### Documentation (this feature)

```text
specs/007-lockdown-mode/
├── spec.md                        # /speckit.specify output (208 lines)
├── plan.md                        # this file
├── research.md                    # Phase 0 output (resolves the three open items in checklists/requirements.md)
├── data-model.md                  # Phase 1 output (LockdownState enum + StoredPassphrase struct)
├── contracts/
│   └── coordinator-protocol.md    # Phase 1 output — public surface of LockdownCoordinator and LockdownSender
├── quickstart.md                  # Phase 1 output — how to drive a manual end-to-end test against a hardened device
├── checklists/
│   └── requirements.md            # /speckit.specify quality checklist (existing)
└── tasks.md                       # /speckit.tasks output (not produced by /speckit.plan)
```

### Source Code (repository root)

```text
Meshtastic/
├── Helpers/
│   ├── BluetoothManager.swift          # MODIFY — add sendLockdownAuth(...), forward inbound LockdownStatus
│   ├── MeshPackets.swift               # MODIFY — handle FromRadio.lockdownStatus payload variant
│   ├── KeychainHelper.swift            # MODIFY — add optional accessibility: parameter (default unchanged)
│   ├── LockdownCoordinator.swift       # NEW — ObservableObject; owns state, drives auto-replay + pendingLockNow
│   └── LockdownPassphraseStore.swift   # NEW — thin wrapper around KeychainHelper; keyed by peripheral UUID
├── Model/
│   └── LockdownState.swift             # NEW — enum + payloads (locked reason, unlocked TTL, backoff seconds)
├── Views/
│   ├── ContentView.swift               # MODIFY — present LockdownSheet as .fullScreenCover when state requires
│   ├── Lockdown/                       # NEW directory
│   │   └── LockdownSheet.swift         # NEW — provisioning / passphrase / failed / backoff variants
│   └── Settings/Config/
│       └── SecurityConfig.swift        # MODIFY — "Lock Now" row, session TTL display
└── MeshtasticApp.swift                 # MODIFY — instantiate LockdownCoordinator, inject via .environmentObject

MeshtasticTests/
└── Helpers/
    ├── LockdownCoordinatorTests.swift  # NEW — state-machine unit tests
    └── LockdownPassphraseStoreTests.swift  # NEW — keychain CRUD tests (mocked)
```

**Structure Decision**: Match the existing Apple-app convention — flat `Helpers/`, `Model/`, `Views/` directories under `Meshtastic/`. New files added to existing groups (no new Xcode group or target required). Tests live alongside existing `MeshtasticTests/` files. No SPM package additions.

## Phase 0: Research

Resolve the three open items from `checklists/requirements.md`. Full detail captured in `research.md`. Summary:

1. **`KeychainHelper` API surface** — confirmed: `KeychainHelper.standard` exposes `save(key:value:service:)`, `read(key:service:)`, `delete(key:service:)` using `kSecClassGenericPassword`, default accessibility `kSecAttrAccessibleWhenUnlocked`. Decision: extend `KeychainHelper` with an optional `accessibility:` parameter (default unchanged) so `LockdownPassphraseStore` can opt into `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Layer the store on top with `service = "meshtastic.lockdown.passphrase"` and `key = peripheralID.uuidString`.

2. **`@Observable` vs `ObservableObject`** — confirmed: deployment target is iOS 16.4 / macOS 14.6, so `@Observable` (iOS 17+) is not usable across all supported configurations. Decision: `class LockdownCoordinator: ObservableObject` with `@Published` properties, matching `LocationsHandler` / `MapDataManager`. Inject via `@EnvironmentObject`.

3. **SwiftProtobuf-generated type names** — to be verified empirically once `MeshtasticProtobufs` regenerates from upstream master. Expected names per SwiftProtobuf 1.x convention:
   - Messages: `Meshtastic_AdminMessage`, `Meshtastic_FromRadio`, `Meshtastic_LockdownAuth`, `Meshtastic_LockdownStatus`
   - Oneof cases: `.lockdownAuth(Meshtastic_LockdownAuth)`, `.lockdownStatus(Meshtastic_LockdownStatus)`
   - Fields: `passphrase: Data`, `bootsRemaining`, `validUntilEpoch`, `lockNow`; `state`, `lockReason`, `bootsRemaining`, `validUntilEpoch`, `backoffSeconds`
   - Enum: `Meshtastic_LockdownStatus.State.{stateUnspecified, needsProvision, locked, unlocked, unlockFailed}`

   Verification step during `/speckit.implement`: bump the `MeshtasticProtobufs` package's protobufs revision and confirm names; surface any divergence in the implementation PR.

## Phase 1: Design

### Data model (data-model.md)

```swift
enum LockdownState: Equatable {
    case none                                            // pre-handshake or non-lockdown firmware
    case needsProvision
    case locked(reason: String)
    case unlocked(bootsRemaining: UInt32, validUntilEpoch: UInt32)
    case unlockFailed
    case unlockBackoff(secondsRemaining: Int, deadline: Date)   // deadline so a foreground/background cycle preserves the countdown
    case lockNowAcknowledged
}

struct StoredPassphrase: Equatable {
    let passphrase: String
    let bootsRemaining: UInt32   // 0 = firmware default
    let validUntilEpoch: UInt32  // 0 = no wall-clock TTL
}
```

### Coordinator contract (contracts/coordinator-protocol.md)

Public surface of `LockdownCoordinator`:

```swift
@MainActor
final class LockdownCoordinator: ObservableObject {
    @Published private(set) var state: LockdownState = .none
    @Published private(set) var sessionAuthorized: Bool = false

    // BluetoothManager calls these:
    func onConnect(peripheralID: UUID)
    func onDisconnect()
    func handle(_ status: Meshtastic_LockdownStatus)

    // UI calls these:
    func submitPassphrase(_ passphrase: String,
                          bootsRemaining: UInt32,
                          validUntilEpoch: UInt32)
    func lockNow()
    func forgetCachedPassphrase()
}
```

`LockdownSender` is the protocol the coordinator depends on for outbound packets (concrete impl: `BluetoothManager` conforms):

```swift
protocol LockdownSender: AnyObject {
    var myNodeNum: UInt32 { get }                       // 0 if not yet received
    func sendLockdownAuth(passphrase: Data,
                          bootsRemaining: UInt32,
                          validUntilEpoch: UInt32,
                          lockNow: Bool)
}
```

### Quickstart (quickstart.md)

Manual smoke test against a hardened-firmware node:

1. Flash a Meshtastic device with `MESHTASTIC_LOCKDOWN` build flag (firmware PR #10349 or later).
2. Run the Apple app on a real iPhone (lockdown can't be exercised in the simulator — no real BLE peripheral).
3. Pair the device in the Connect tab; observe the provisioning sheet appears at `NEEDS_PROVISION`.
4. Enter `test-passphrase` with both TTL fields blank; verify transition to `.unlocked` and that Settings → Config now shows real values.
5. Force-quit the app, reopen, reconnect to the same peripheral; verify auto-replay (no sheet).
6. Settings → Security → Lock Now; confirm; verify device reboots and reconnect prompts for passphrase again (auto-replay first, then succeeds).
7. Enter a wrong passphrase three times in quick succession; verify `UnlockBackoff` countdown appears.

### Constitution re-check post-design

Unchanged — no constitution to re-evaluate against. No complexity-tracking entries.

## Complexity Tracking

No violations — feature stays within the existing patterns (one new `ObservableObject`, one new SwiftUI sheet, no architectural deviations).
