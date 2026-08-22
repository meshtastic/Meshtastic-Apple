# Issue 2336 maintenance UF2 research

## Required sequence

Meshtastic-Android prepares the selected application firmware before starting a
maintenance operation, then performs two UF2 passes: factory erase or bootloader
upgrade first, application firmware second. Its pass model treats the first pass
as destructive and does not expose an abort edge before reinstalling the
application.

Sources:

- [`MaintenanceUf2.kt`](https://github.com/meshtastic/Meshtastic-Android/blob/19bb682c9c028960a1c594d927872206a93bee92d/feature/firmware/src/commonMain/kotlin/org/meshtastic/feature/firmware/MaintenanceUf2.kt)
- [`UsbMaintenance.kt`](https://github.com/meshtastic/Meshtastic-Android/blob/19bb682c9c028960a1c594d927872206a93bee92d/feature/firmware/src/commonMain/kotlin/org/meshtastic/feature/firmware/UsbMaintenance.kt)

## OTAFIX selection

Bootloader images must be selected from the `Board-ID` in the mounted volume's
`INFO_UF2.TXT`. Target names and USB VID/PID are not authoritative. The Apple
implementation mirrors Android's release-pinned OTAFIX 2.2 BP1.4 catalog and
SHA-256 values from `MaintenanceUf2.kt`.

Release:
[`0.9.2-OTAFIX2.2-BP1.4`](https://github.com/meshtastic/Adafruit_nRF52_Bootloader_OTAFIX/releases/tag/0.9.2-OTAFIX2.2-BP1.4)

The release tag resolves to commit
[`18c3dc57dc6e52e06b17b040f72bf75aa505a034`](https://github.com/meshtastic/Adafruit_nRF52_Bootloader_OTAFIX/commit/18c3dc57dc6e52e06b17b040f72bf75aa505a034).
Its `Makefile` defines `UF2_VERSION` from the full Git tag, and `ghostfat.c`
writes that value on the first line of `INFO_UF2.TXT`. Apple records whether a
fresh second-pass volume reports the full OTAFIX release string. A mismatch is
reported, but it never blocks the mandatory application reinstall and never
causes an automatic retry.

## Factory erase

The published nRF52 erase images are linked for either S140 6.1.1 (`0x26000`)
or S140 7.3.0 (`0x27000`). The mounted volume's `SoftDevice` line is the
runtime authority. A mismatch between it and the application image start must
refuse the operation.

The current upstream erase program blocks at `while (!Serial)` before calling
`InternalFS.format()`. Android added a CDC/DTR unblock step. Generic USB CDC is
not available to a normal iOS app, so the published images cannot erase from
an iPhone or iPad.

Sources:

- [`nrf52_factory_erase/src/main.cpp` at c48244b](https://github.com/meshtastic/nrf52_factory_erase/blob/c48244bd65e54a04fac80de36e59eeb3a12289ad/src/main.cpp)
- [`UsbMaintenance.kt` CDC handling](https://github.com/meshtastic/Meshtastic-Android/blob/19bb682c9c028960a1c594d927872206a93bee92d/feature/firmware/src/commonMain/kotlin/org/meshtastic/feature/firmware/UsbMaintenance.kt)

This branch bundles two deterministic variants built from that pinned upstream
commit with only the CDC wait and diagnostic serial prints removed. They format
immediately, then call `enterDfuMode()` so the application firmware can be
written on the second pass. The patch, pinned build script, hashes, and binaries
live under `scripts/firmware/` and
`Meshtastic/Resources/FirmwareMaintenance/`.

## Apple implementation boundary

The maintenance flow is self-contained and leaves the existing ordinary UF2
export and Nordic BLE DFU paths unchanged. It does not require a connected,
running radio or a saved device profile before starting, so factory erase
remains usable when application firmware cannot boot. Factory erase does not
restore the erased owner, channels, keys, or settings.

## Safety decisions

- Download and hash-check every remote OTAFIX image before writing.
- Parse every UF2 block and reject malformed numbering, flags, payloads, or
  mixed family IDs.
- Reconcile erase image start address against the volume's reported SoftDevice.
- Persist the maintenance-writing phase before the first byte.
- Never retry an indeterminate maintenance or application write automatically.
- Require the application UF2 to be prepared before offering either operation.
- Continue to the application pass after an indeterminate maintenance copy.
- Match Android's 13-target OTAFIX UI gate exactly; select the actual image only
  after reading the volume's Board-ID.
- Report an unconfirmed OTAFIX version after reinstall without claiming the
  bootloader upgrade succeeded.
- Persist only maintenance phase and artifact identity. Do not couple the
  bootloader-level recovery path to generic UF2 installation, app-database
  backup, or device-profile restoration.
