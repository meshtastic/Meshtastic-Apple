# Hang Risk Runtime Issues — 2026-10-02

Captured from the running Mac Catalyst debug build (PID 79938, `MeshtasticSxS` / `Debug-maccatalyst`)
via `log show --predicate 'subsystem == "com.apple.runtime-issues"'`, de-duplicated by backtrace and
symbolicated with `atos`.

- **Total log events:** 1,507 (all category `Hang Risk`)
- **Unique backtraces:** 13 (Xcode Issue Navigator showed 14; the extra one likely pre-dates the 3h log window)

## Common message (all issues)

> [Internal] Thread running at **User-initiated** quality-of-service class waiting on a lower QoS thread
> running at **Utility** quality-of-service class. Investigate ways to avoid priority inversions

## Common root cause

`Meshtastic/Accessory/Transports/Bluetooth Low Energy/BLETransport.swift:25`

```swift
private let centralQueue = DispatchQueue(label: "com.meshtastic.ble.central", qos: .utility)
```

`CBCentralManager` is created on this `.utility` queue. Every CoreBluetooth call made from Swift
Concurrency (user-initiated) contexts goes through `-[CBXpcConnection _sendBarrier]`, which synchronously
waits on the utility-QoS queue → priority inversion.

Shared top-of-stack for every issue:

```
-[CBXpcConnection _sendBarrier]
-[CBXpcConnection sendMsg:args:]
-[CBManager sendMsg:args:]
```

## Issues (sorted by occurrence count)

| # | Count | CoreBluetooth call | App call site |
|---|------:|--------------------|---------------|
| 1 | 591 | `-[CBPeripheral readValueForCharacteristic:]` | `closure #1 in BLEConnection.read()` — `BLEConnection.swift:662` (direct continuation) |
| 2 | 587 | `-[CBPeripheral readValueForCharacteristic:]` | `closure #1 in BLEConnection.read()` — `BLEConnection.swift:662` (via Swift Concurrency job resume) |
| 3 | 315 | `-[CBPeripheral readRSSI]` | `BLEConnection.requestRSSIRead()` — `BLEConnection.swift:306` ← `BLEConnection.startRSSITask()` closure — `BLEConnection.swift:297` |
| 4 | 5 | `-[CBPeripheral writeValue:forCharacteristic:type:]` | `closure #1 in closure #1 in BLEConnection.performWrite(_:to:type:)` — `BLEConnection.swift:630` |
| 5 | 1 | `-[CBCentralManager stopScan]` | `BLETransport.pauseScanningForConnection(to:)` — `BLETransport.swift:366` ← `BLETransport.connect(to:)` — `BLETransport.swift:418` |
| 6 | 1 | `-[CBCentralManager connectPeripheral:options:]` | `closure #1 in closure #1 in BLETransport.connect(to:)` — `BLETransport.swift:449` |
| 7 | 1 | `-[CBPeripheral discoverServices:]` | `closure #1 in BLEConnection.discoverServices()` — `BLEConnection.swift:247` |
| 8 | 1 | `-[CBPeripheral discoverCharacteristics:forService:]` | `BLEConnection.didDiscoverServices(error:)` — `BLEConnection.swift:327` ← `BLEConnectionDelegate.peripheral(_:didDiscoverServices:)` — `BLEConnection.swift:806` |
| 9 | 1 | `-[CBPeripheral setNotifyValue:forCharacteristic:]` | `BLEConnection.didDiscoverCharacteristicsFor(service:error:)` — `BLEConnection.swift:365` ← delegate — `BLEConnection.swift:810` |
| 10 | 1 | `-[CBPeripheral setNotifyValue:forCharacteristic:]` | `BLEConnection.didDiscoverCharacteristicsFor(service:error:)` — `BLEConnection.swift:360` ← delegate — `BLEConnection.swift:810` |
| 11 | 1 | `-[CBPeripheral setNotifyValue:forCharacteristic:]` | `BLEConnection.didDiscoverCharacteristicsFor(service:error:)` — `BLEConnection.swift:370` ← delegate — `BLEConnection.swift:810` |
| 12 | 1 | `-[CBPeripheral readRSSI]` | `BLEConnection.didUpdateNotificationState(characteristic:error:)` — `BLEConnection.swift:465` ← `BLEConnectionDelegate.peripheral(_:didUpdateNotificationStateFor:error:)` — `BLEConnection.swift:818` |
| 13 | 1 | `-[CBCentralManager _scanForPeripheralsWithServices:options:completion:]` | `BLETransport.resumeScanningIfPaused(for:)` — `BLETransport.swift:393` ← `BLETransport.resumeScanningAfterConnectionEstablished(for:)` — `BLETransport.swift:374` ← `AccessoryManager.connect(to:withConnection:…)` — `AccessoryManager+Connect.swift:188` |

Issues 1–4 are recurring (steady-state read loop, RSSI polling, writes). Issues 5–13 fire once per
connection (connect / discovery / subscribe / resume-scan).

## Image UUIDs (for reference)

| UUID | Image |
|------|-------|
| `5F1AC44E-1574-3C21-AD17-9B10AF749B66` | `Meshtastic.debug.dylib` |
| `E6D28E45-E086-33A4-A5DD-73DC21125CAA` | `CoreBluetooth` |
| `4E38D421-5AA2-3A24-8832-8AD221905A12` | `libswift_Concurrency.dylib` |
| `29387E4E-B15A-3719-B1F2-8CDF2759680B` | `libdispatch.dylib` |
| `D0A2264A-D61B-34EE-A71D-0E8DBCE5ECD2` | `libsystem_pthread.dylib` |

## Likely fixes (not yet applied)

1. Raise `centralQueue` QoS to `.userInitiated` in `BLETransport.swift:25` — single-line change that should
   eliminate all 13 inversions, since callers run at user-initiated.
2. Alternatively, keep `.utility` but dispatch all `CBPeripheral` / `CBCentralManager` calls onto
   `centralQueue` (async) instead of invoking them from Swift Concurrency tasks, so the calling thread
   never blocks on the barrier.

## Reproduce

```bash
log show --last 3h --style ndjson \
  --predicate 'processID == <PID> AND subsystem == "com.apple.runtime-issues"' > raw.ndjson
# decode trailing hex: 20-byte frames = 16-byte image UUID + 4-byte little-endian offset
atos -arch arm64 -o Meshtastic.debug.dylib -l 0x0 <offset>
atos -p <PID> <CoreBluetooth __TEXT base + offset>
```
