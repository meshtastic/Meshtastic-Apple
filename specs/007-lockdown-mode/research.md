# Phase 0 Research: Lockdown Mode

Resolutions for the three open items in `checklists/requirements.md`.

## R1 — `KeychainHelper` API surface

**Question**: Does `KeychainHelper` expose per-account get/set, or only a single shared item?

**Investigation**:
- `Meshtastic/Helpers/KeychainHelper.swift:10` — `class KeychainHelper { static let standard = KeychainHelper() }`.
- Public surface (lines 14–27):
  - `save(key: String, value: String, service: String = Bundle.main.bundleIdentifier!) -> OSStatus`
  - `read(key: String, service: String = ...) -> String?`
  - `delete(key: String, service: String = ...) -> OSStatus`
- Uses `kSecClassGenericPassword` with `(key, service)` as the composite identifier.
- Accessibility hardcoded to `kSecAttrAccessibleWhenUnlocked` (line 25).

**Decision**:
- Per-peripheral keying works: use `key = peripheralID.uuidString`, `service = "meshtastic.lockdown.passphrase"`.
- Default accessibility (`WhenUnlocked`) is insufficient for unattended foreground auto-replay after a fresh app launch from a locked device. **Extend `KeychainHelper`** to accept an optional `accessibility: CFString` parameter (default `kSecAttrAccessibleWhenUnlocked` — preserves behaviour for existing callers); `LockdownPassphraseStore` passes `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- A thin `LockdownPassphraseStore` struct wraps the three operations; one file, no protocol abstraction needed (testable via dependency injection on the coordinator).

## R2 — `@Observable` vs `ObservableObject`

**Question**: Which observability mechanism does the codebase use, and which is mandated by the deployment target?

**Investigation**:
- `grep -nE "@Observable|ObservableObject|@Published" Meshtastic/Helpers/*.swift Meshtastic/Model/*.swift` → only `ObservableObject + @Published` (e.g. `LocationsHandler`, `MapDataManager`). Zero `@Observable` usage.
- Deployment targets (`Meshtastic.xcodeproj/project.pbxproj`): `IPHONEOS_DEPLOYMENT_TARGET = 16.4` and `17.5` (varies by target), `MACOSX_DEPLOYMENT_TARGET = 14.6`.
- `@Observable` macro requires iOS 17 / macOS 14 minimum; mixing with a 16.4 deployment target on the main app target is unsupported without availability annotations and an `@Observable` fallback.

**Decision**: `class LockdownCoordinator: ObservableObject`, properties marked `@Published`. Inject at app scope via `MeshtasticApp.swift`:

```swift
@StateObject private var lockdownCoordinator = LockdownCoordinator(...)
…
ContentView()
    .environmentObject(lockdownCoordinator)
```

Consumers (`ContentView`, `LockdownSheet`, `SecurityConfig`) read with `@EnvironmentObject var lockdown: LockdownCoordinator`.

## R3 — SwiftProtobuf-generated type names

**Question**: After the `MeshtasticProtobufs` package regenerates from upstream master (with PR #911 merged), what are the exact Swift type names?

**Investigation**:
- SwiftProtobuf 1.x convention: each proto message becomes `Meshtastic_<MessageName>` (proto `package meshtastic;` → Swift prefix `Meshtastic_`). Fields convert snake_case → camelCase. Enums become nested types.
- Apple repo currently does not have these types yet — proto submodule predates PR #911.

**Verified names (after submodule bump to `1c62540`):**

This repo's `protoc --swift_out` invocation does **not** include `--swift_opt=FileNaming=DropPath` or a Swift-side package prefix, so the generated types are **unprefixed** (just `AdminMessage`, `FromRadio`, `LockdownAuth`, `LockdownStatus`) — not `Meshtastic_*` as the original SwiftProtobuf default would have produced. Likely effect of `.proto` files lacking a `swift_prefix` / `swift_package` option.

| Proto | Swift |
|---|---|
| `message LockdownAuth` | `LockdownAuth` |
| `message LockdownStatus` | `LockdownStatus` |
| `LockdownStatus.State` | `LockdownStatus.State` |
| `LockdownStatus.State.STATE_UNSPECIFIED` | **`.unspecified`** (not `.stateUnspecified`; the proto omits the `STATE_` prefix per the generator's stripping rules) |
| `LockdownStatus.State.NEEDS_PROVISION` | `.needsProvision` |
| `LockdownStatus.State.LOCKED` | `.locked` |
| `LockdownStatus.State.UNLOCKED` | `.unlocked` |
| `LockdownStatus.State.UNLOCK_FAILED` | `.unlockFailed` |
| `AdminMessage.payload_variant.lockdown_auth` | `AdminMessage.OneOf_PayloadVariant.lockdownAuth(LockdownAuth)` |
| `FromRadio.payload_variant.lockdown_status` | `FromRadio.OneOf_PayloadVariant.lockdownStatus(LockdownStatus)` |
| `LockdownAuth.passphrase` | `passphrase: Data` |
| `LockdownAuth.boots_remaining` | `bootsRemaining: UInt32` |
| `LockdownAuth.valid_until_epoch` | `validUntilEpoch: UInt32` |
| `LockdownAuth.lock_now` | `lockNow: Bool` |
| `LockdownStatus.state` | `state: LockdownStatus.State` |
| `LockdownStatus.lock_reason` | `lockReason: String` |
| `LockdownStatus.boots_remaining` | `bootsRemaining: UInt32` |
| `LockdownStatus.valid_until_epoch` | `validUntilEpoch: UInt32` |
| `LockdownStatus.backoff_seconds` | `backoffSeconds: UInt32` |

**Decision**: implementation uses the verified names; downstream artifacts (data-model.md, contracts/coordinator-protocol.md, tasks.md) reference the same. **Note**: the `STATE_UNSPECIFIED` Swift case is `.unspecified` — not `.stateUnspecified`.

## Out-of-scope deferrals

- **Constitution**: `.specify/memory/constitution.md` is unfilled. Defer to a separate `/speckit.constitution` run; this feature's plan has no project-level gates to satisfy.
- **Localization**: strings will be added to `Localizable.xcstrings` during implement; not a research item.
- **Snapshot tests for the sheet**: `MeshtasticTests` does not currently use snapshot testing. Skip — XCTest unit coverage on the coordinator state machine is sufficient.
