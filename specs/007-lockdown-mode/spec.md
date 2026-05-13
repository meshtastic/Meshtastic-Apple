# Feature Specification: Lockdown Mode

**Feature Branch**: `007-lockdown-mode`
**Created**: 2026-05-13
**Status**: Draft
**Input**: User description: "Implement lockdown mode for Meshtastic-Apple using the new lockdown protobufs (meshtastic/protobufs PR #911) and the ATAK plugin's proof-of-concept (meshtastic/pluginmeshtastic PR #2)"
**Cross-Platform Spec**: Companion to Meshtastic-Android lockdown spec — protocol is identical, this spec adapts the client UX and storage to Apple platforms (iOS + macCatalyst).

## Summary

Lockdown mode protects unattended Meshtastic nodes from unauthorized physical access. When enabled on firmware, a connecting client must provide a passphrase before it can view or modify the node's actual configuration. The Apple app needs to detect locked nodes over its CoreBluetooth GATT connection, prompt for authentication via SwiftUI, cache credentials in the Keychain, display session status, and provide a "Lock Now" action to immediately re-lock the device.

## Clarifications

### Session 2026-05-13

- Q: Should lockdown block all navigation (full-screen modal) or only gate config screens? → A: Full-screen blocking sheet — when the connected node is `LOCKED` or `NEEDS_PROVISION`, the app presents a non-dismissable `.fullScreenCover` (or `.sheet(isPresented:)` with interactive dismiss disabled) so the user cannot reach settings, message threads, or the node list until they resolve lockdown.
- Q: Should the app expose TTL fields (`boots_remaining`, `valid_until_epoch`) to the user or always use firmware defaults? → A: Optional fields — show "boots remaining" and "hours until expiry" as optional inputs in the passphrase form, default to 0 (which the firmware interprets as "use defaults") when left empty.
- Q: How should the coordinator be structured? Single class, MVVM ViewModel, or actor? → A: Swift `@Observable` (or `ObservableObject` if iOS 16 support required) coordinator owned at app scope, injected via `Environment`; the BluetoothManager forwards inbound `LockdownStatus` to it. Keychain access goes through the existing `KeychainHelper`.
- Q: Should "Lock Now" use a client-side flag to await firmware ACK, or fire-and-disconnect immediately? → A: Client-side flag — track `pendingLockNow`, route the next inbound `LOCKED` status (or BLE disconnect, whichever comes first) to a `lockNowAcknowledged` state, then disconnect gracefully. Mirrors the Android coordinator's behaviour.
- Q: Should all action-prompting banners be gated on lockdown auth, or only the region-unset banner? → A: All action-prompting banners — suppress any banner or in-context callout that asks the user to change config they cannot reach while locked.

## Goals

1. Enable users to authenticate against locked-down nodes so they can access real device configuration over BLE.
2. Allow first-time passphrase provisioning on unprovisioned hardened nodes.
3. Provide clear visibility into the current lockdown state (locked, unlocked, session TTL).
4. Allow users to immediately re-lock a device with a single action from Security settings.
5. Cache passphrases per-node in the Keychain so reconnections don't require re-entry.

## Non-Goals

- Implementing lockdown logic in firmware (firmware handles encryption, token management, DEK generation).
- Modifying the protobuf definitions (these come from the `MeshtasticProtobufs` Swift package, generated from the upstream `meshtastic/protobufs` submodule).
- Providing remote lock/unlock over the mesh network (lockdown is local connection only).
- Managing lockdown across multiple nodes simultaneously in a single flow.
- Implementing a passphrase strength meter or password policy enforcement.
- Supporting USB Serial (the Apple app is BLE-only).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Unlock a Locked Node (Priority: P1)

A user connects to a node that has lockdown mode enabled and is currently locked. The app detects `LockdownStatus.LOCKED` from the firmware and presents a passphrase entry sheet. On a correct passphrase the node unlocks and the user can view/edit configurations normally.

**Why this priority**: Without unlock, lockdown-enabled nodes are inaccessible from the app.

**Independent Test**: Connect to a locked node via BLE, enter the correct passphrase, verify that the Connect / Nodes / Settings tabs become reachable and that real config values (not redacted defaults) appear in Settings → Config.

**Acceptance Scenarios**:

1. **Given** the app connects to a node and the next `FromRadio` payload after `config_complete_id` carries `lockdown_status` with `state == LOCKED`, **When** that packet is processed, **Then** the app presents a full-screen passphrase sheet over the active tab.
2. **Given** the user enters the correct passphrase, **When** the `AdminMessage.lockdown_auth` ToRadio packet is sent, **Then** the firmware responds with `LockdownStatus.state == UNLOCKED` and the app dismisses the sheet, re-requests config (existing `wantConfig` flow), and displays the real device configuration.
3. **Given** the user enters an incorrect passphrase, **When** the firmware responds with `state == UNLOCK_FAILED` and `backoff_seconds == 0`, **Then** the app shows an inline error in the sheet and re-enables the Submit button for immediate retry.
4. **Given** the firmware responds with `UNLOCK_FAILED` and `backoff_seconds > 0`, **When** the error is received, **Then** the app shows a countdown (seconds remaining) and disables the Submit button until the backoff elapses.

---

### User Story 2 - Provision a New Lockdown Passphrase (Priority: P1)

A user connects to a hardened firmware node that has never been provisioned (no passphrase set). The app detects `state == NEEDS_PROVISION` and prompts the user to create a passphrase. On successful provisioning the firmware generates a DEK and the node is unlocked for the current session.

**Why this priority**: Without provisioning, a hardened node cannot be secured — this is the setup path.

**Independent Test**: Connect to an unprovisioned node, set a passphrase via the provisioning sheet, verify the node transitions to `UNLOCKED` and the chosen passphrase is cached in the Keychain under the node's BLE peripheral identifier.

**Acceptance Scenarios**:

1. **Given** the app connects to a node and the inbound `lockdown_status` reports `state == NEEDS_PROVISION`, **When** the packet is processed, **Then** the app presents the provisioning sheet with the hint text "First-time setup — pick a passphrase you can re-enter".
2. **Given** the user enters and confirms a passphrase (1–32 UTF-8 bytes), **When** `AdminMessage.lockdown_auth` is sent with `lock_now == false`, **Then** the firmware responds with `UNLOCKED` and the app caches the passphrase keyed by peripheral UUID.
3. **Given** the user is in the provisioning flow, **When** they attempt to submit an empty passphrase or one that exceeds 32 bytes, **Then** the Submit button is disabled and a validation message is shown.

---

### User Story 3 - Lock Now (Priority: P2)

A user with an unlocked session wants to immediately re-lock the device. They tap "Lock Now" in Settings → Security. The device revokes session authorization and reboots locked.

**Why this priority**: Provides active security control; the device will also lock on its own when the token expires.

**Independent Test**: With an unlocked node, tap "Lock Now" and verify the node reboots; the subsequent reconnect requires a passphrase.

**Acceptance Scenarios**:

1. **Given** the connected node is in `UNLOCKED` state, **When** the user taps "Lock Now" in Settings → Security and confirms the alert, **Then** the app sends `AdminMessage.lockdown_auth` with `lock_now == true` and sets the coordinator's `pendingLockNow` flag.
2. **Given** the coordinator has `pendingLockNow == true`, **When** an inbound `LockdownStatus.state == LOCKED` arrives (or the BLE peripheral disconnects, whichever comes first), **Then** the coordinator transitions to `.lockNowAcknowledged`, the BluetoothManager calls `disconnectPeripheral()`, and the connection list shows the node as disconnected.
3. **Given** the user has tapped "Lock Now", **When** the device reboots and the user reconnects, **Then** the inbound status reports `LOCKED` and the app re-prompts for the passphrase (auto-replay attempts the cached value first per US-4).
4. **Given** the node is currently `LOCKED` or `NEEDS_PROVISION`, **When** the user navigates to Settings → Security, **Then** the "Lock Now" row is hidden or disabled with an explanatory caption.

---

### User Story 4 - Cached Passphrase Auto-Reconnect (Priority: P2)

A user who has previously authenticated to a node reconnects (after a brief disconnection, app relaunch, or device reboot). The app retrieves the cached passphrase from the Keychain and sends `lockdown_auth` automatically without showing the sheet.

**Why this priority**: Improves UX for frequent reconnections but not required for basic functionality.

**Independent Test**: Authenticate to a node, force-quit the app, reopen and reconnect to the same node — verify no passphrase sheet appears and the app reaches a usable state automatically.

**Acceptance Scenarios**:

1. **Given** the Keychain contains an entry for the connected peripheral's UUID, **When** the app reconnects and receives `state == LOCKED`, **Then** the coordinator sets `wasAutoAttempt = true` and sends `AdminMessage.lockdown_auth` with the cached passphrase silently (no sheet shown).
2. **Given** auto-replay was attempted and the firmware responds with `UNLOCK_FAILED` (`backoff_seconds == 0`), **When** the response is received, **Then** the coordinator deletes the Keychain entry for that peripheral and presents the manual passphrase sheet.
3. **Given** auto-replay was attempted and the firmware responds with `UNLOCK_FAILED` (`backoff_seconds > 0`), **When** the response is received, **Then** the coordinator preserves the cached passphrase, transitions to `unlockBackoff(seconds)`, and shows the countdown sheet (it is rate-limiting, not a wrong passphrase).
4. **Given** the user has never authenticated to a particular peripheral, **When** they connect for the first time, **Then** no auto-replay occurs and the standard prompt is shown.

---

### User Story 5 - View Session Token Status (Priority: P3)

A user with an unlocked session can view the remaining session lifetime (boots remaining, expiry time) in Settings → Security.

**Why this priority**: Informational; doesn't affect core functionality.

**Independent Test**: Unlock a node with explicit `boots_remaining=5` and `valid_until_epoch` set, verify both are displayed in human-readable form.

**Acceptance Scenarios**:

1. **Given** the node is `UNLOCKED` with `boots_remaining == 5` and `valid_until_epoch` set to a future timestamp, **When** the user opens Settings → Security, **Then** "Boots remaining: 5" and "Expires: <localized date/time>" are shown.
2. **Given** the node is `UNLOCKED` with `valid_until_epoch == 0`, **When** the user views session info, **Then** the expiry row reads "No time limit".

---

### Edge Cases

- **BLE drop mid-authentication**: CoreBluetooth raises `centralManager(_:didDisconnectPeripheral:error:)`; coordinator resets to `.none`, drops `pendingPassphrase`, and treats the next reconnect as a fresh attempt.
- **Another client unlocks/locks the node concurrently**: The firmware pushes an unsolicited `LockdownStatus` update; the coordinator processes it and updates UI state without user action.
- **Cached passphrase no longer valid because the node was re-provisioned**: Auto-replay fails with `UNLOCK_FAILED, backoff=0` → Keychain entry is deleted → manual sheet is shown.
- **Device clock skew causing `valid_until_epoch` to look expired**: The client displays firmware-reported state as-is; lockdown decisions remain firmware-side.
- **App backgrounded during backoff**: Coordinator records the absolute deadline (`Date(timeIntervalSinceNow: backoff_seconds)`) so the countdown remains correct after foregrounding.
- **MyNodeInfo not yet received when user tries to submit**: Submit button stays disabled until `BluetoothManager.connectedNode.num` is non-zero (required for `MeshPacket.to`).

## Architecture

### Key Components

| Component | File | Purpose |
|-----------|------|---------|
| `LockdownCoordinator` | `Meshtastic/Helpers/LockdownCoordinator.swift` (new) | Owns `@Published`/`@Observable` lockdown state; processes inbound `LockdownStatus`; sends outbound `lockdown_auth` via the existing BluetoothManager send path. |
| `LockdownState` | `Meshtastic/Model/LockdownState.swift` (new) | Swift enum mirroring the Android sealed class (`.none`, `.needsProvision`, `.locked(reason)`, `.unlocked(boots, until)`, `.unlockFailed`, `.unlockBackoff(seconds)`, `.lockNowAcknowledged`). |
| `LockdownPassphraseStore` | `Meshtastic/Helpers/LockdownPassphraseStore.swift` (new) | Thin wrapper around `KeychainHelper`; per-peripheral get/save/clear of passphrase + optional TTL overrides. |
| Inbound dispatch | `Meshtastic/Helpers/MeshPackets.swift` (modified) | Add a branch in the `FromRadio.payloadVariant` switch for the new `lockdown_status` field; forward to `LockdownCoordinator.handle(_:)`. |
| Outbound builder | `Meshtastic/Helpers/BluetoothManager.swift` (modified) | New `sendLockdownAuth(passphrase:bootsRemaining:validUntilEpoch:lockNow:)` that builds a `MeshPacket` with `to = myNodeNum`, `from` unset, `wantAck = true`, `hopLimit = 7`, `hopStart = 7`, `priority = .reliable`, `decoded.portnum = .adminApp`, `decoded.payload = AdminMessage{lockdownAuth: …}.serializedData()`. **`pkiEncrypted` MUST remain unset.** |
| Lockdown sheet UI | `Meshtastic/Views/Lockdown/LockdownSheet.swift` (new) | SwiftUI sheet driven by `LockdownState` — passphrase entry, provisioning, unlock-failed error, backoff countdown. |
| App-level gate | `Meshtastic/Views/ContentView.swift` (modified) | Present `LockdownSheet` as a `.fullScreenCover` when `coordinator.state` is `.locked` or `.needsProvision`. |
| Lock Now control | `Meshtastic/Views/Settings/Config/SecurityConfig.swift` (modified) | New "Lock Now" row gated on `state == .unlocked`; confirmation alert before sending. |
| Banner suppression | `Meshtastic/Views/...` (existing banner sites) | Wrap action-prompting banners (e.g. region-unset) in `if coordinator.sessionAuthorized` checks. |

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: App MUST detect `FromRadio.lockdown_status` (field 18) in the packet stream and route it to the `LockdownCoordinator`.
- **FR-002**: App MUST present a passphrase entry sheet when the coordinator's state is `.locked(reason:)`.
- **FR-003**: App MUST present a passphrase creation sheet when the coordinator's state is `.needsProvision`.
- **FR-004**: App MUST send `AdminMessage.lockdown_auth` (field 104) with the user-supplied passphrase to unlock or provision.
- **FR-005**: App MUST expose optional "boots remaining" and "hours until expiry" input fields in the passphrase sheet; when left empty, send `0` so firmware defaults apply.
- **FR-006**: App MUST display error feedback when firmware reports `UNLOCK_FAILED`. When `backoff_seconds > 0`, display a live countdown derived from a stored deadline (`Date`).
- **FR-007**: App MUST provide a "Lock Now" action in Settings → Security that sends `AdminMessage.lockdown_auth` with `lock_now == true` and an empty passphrase.
- **FR-008**: App MUST cache passphrases in the iOS Keychain (`KeychainHelper`), keyed by the CoreBluetooth peripheral UUID.
- **FR-009**: App MUST auto-replay the cached passphrase on reconnection to a previously-authenticated locked node without showing a sheet.
- **FR-010**: App MUST clear the cached passphrase entry for a peripheral when auto-replay results in `UNLOCK_FAILED` with `backoff_seconds == 0`.
- **FR-011**: App MUST display session token TTL (`boots_remaining`, `valid_until_epoch`) in Settings → Security when the node is `.unlocked`.
- **FR-012**: App MUST present a full-screen, non-dismissable sheet when in `.locked` or `.needsProvision` state, preventing access to messages, node list, and other settings until lockdown is resolved.
- **FR-013**: App MUST suppress all action-prompting banners (e.g. "Region Unset") whenever the connected node is lockdown-enabled but the current connection is not authorized.
- **FR-014**: On BLE peripheral disconnect, the coordinator MUST reset session state (set `sessionAuthorized = false`, clear `pendingPassphrase`) so the next connection re-auths cleanly. If `pendingLockNow` was set, the disconnect itself MUST resolve the coordinator to `.lockNowAcknowledged`.

### Non-Functional Requirements

- **NFR-001**: Cached passphrases MUST be stored in the iOS Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` or stricter. Passphrases MUST NOT be written to UserDefaults, Core Data, or any file outside the Keychain.
- **NFR-002**: The passphrase TextField MUST use `.textContentType(.password)` and `SecureField` semantics. Passphrase bytes MUST NOT appear in `Logger` output at any level, including `.debug`. Passphrase strings held in memory by the coordinator (`pendingPassphrase`) MUST be cleared as soon as the corresponding `LockdownStatus` response (success or failure) is processed; never retained beyond that window.
- **NFR-003**: Unlock flow MUST complete within 5 seconds end-to-end on a standard BLE connection (user submit → coordinator state `.unlocked`).
- **NFR-004**: The full-screen lockdown sheet MUST honor system Reduce Motion and Increase Contrast settings; passphrase entry MUST be usable with VoiceOver.

## Design Standards Compliance

- [ ] Sheet UI reviewed against [Meshtastic design standards](https://raw.githubusercontent.com/meshtastic/design/refs/heads/master/standards/meshtastic_design_standards_latest.md).
- [ ] SF Symbols selected for lock states (`lock.fill`, `lock.open.fill`, `lock.trianglebadge.exclamationmark`).
- [ ] Accessibility: VoiceOver labels for all controls, Dynamic Type support, color-independent state cues (icons + text).
- [ ] Localization: all user-facing strings added to `Localizable.xcstrings`.

## Privacy Assessment

- [ ] No PII, location data, or cryptographic keys logged or exposed.
- [ ] Passphrases stored only in the iOS Keychain, never in plaintext or in any non-keychain store.
- [ ] No new network calls; lockdown is BLE-local only.
- [ ] `MeshtasticProtobufs` submodule unchanged (read-only upstream pull).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can unlock a locked node and access full configuration within 10 seconds of entering the correct passphrase.
- **SC-002**: A user connecting to an unprovisioned node can set a passphrase and reach `.unlocked` in a single flow without intermediate confusion (single sheet, single Submit).
- **SC-003**: "Lock Now" action results in the device rebooting to locked state within 5 seconds of confirmation.
- **SC-004**: Returning users with a cached passphrase reconnect without manual re-entry in ≥95% of cases (cache hit).
- **SC-005**: Zero passphrase bytes appear in any `os_log` / `Logger` output at any log level (verified by `log show` audit of a provisioning + unlock + lock-now session).

## Assumptions

- The `MeshtasticProtobufs` Swift package generates from `meshtastic/protobufs` master (commit including PR #911); `AdminMessage.LockdownAuth` and `MeshProtos.LockdownStatus` exist as Swift types named `Meshtastic_AdminMessage.OneOf_PayloadVariant.lockdownAuth(_:)` and `Meshtastic_FromRadio.OneOf_PayloadVariant.lockdownStatus(_:)` per SwiftProtobuf naming conventions.
- The existing `BluetoothManager` `wantConfig` handshake delivers `FromRadio.myInfo` before `lockdown_status`, so `myNodeNum` is available when the user submits.
- `KeychainHelper` exposes (or can be extended with) per-account get/set/delete; a thin `LockdownPassphraseStore` layered on top is acceptable.
- The Apple app supports iOS 16+ and macCatalyst; `@Observable` (Swift 5.9 / iOS 17+) is preferred if the deployment target allows, otherwise `ObservableObject` + `@Published`.
- The firmware correctly implements the `LockdownAuth` / `LockdownStatus` protobuf contract from `admin.proto` and `mesh.proto`.
- Passphrase length is constrained to 1–32 bytes UTF-8 per the proto definition.
- The app does not need to determine whether a node is "hardened" — it simply reacts to `LockdownStatus` presence in the packet stream.
- Token TTL parameters use firmware defaults when the user leaves the optional fields empty (sent as `0`).
- Passphrase cache survives app uninstall by design (iOS Keychain default behaviour for entries with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`); a fresh install on the same device will auto-reconnect to previously-paired hardened nodes. If a user wants to force re-prompting they can use Settings → Security → Forget Stored Passphrase (added in T021).
- `LockdownStatus` packets carrying `state == STATE_UNSPECIFIED` (proto default 0) MUST be ignored by the coordinator — no state mutation, no log entry beyond a single warning. This is the forward-compat behaviour for any future state values the client doesn't yet recognize.
