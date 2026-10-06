# Review V11: data, messages and services (feature/multi-radio)

Branch `feature/multi-radio` at `cf26aa79`. This pass re-checks the fixes for `review-data-v10.md`
(R10-1 to R10-8 → T330, T332, T336–T338, T340) and W-15 (a required radio choice for services in
use, replacing W-09 and the "radio connected first" fallback), and goes over what else changed in
my area since `d038d296`. I read the tasks.md, windows.md and HANDOFF.md changes first and
re-read every claim below in the files. The ingest and storage code only had names changed
(`firstRadio:` for `focusedRadio:`, T341).

Tests: the full suite passes in the iOS Simulator (iPhone 17 Pro) at `cf26aa79`: 3,490 Swift
Testing tests in 601 suites and 32 XCTests, started once no other `xcodebuild` was running. The
Mac Catalyst build succeeds (own derived data, signing off; built, not run). No tracked file
changed. None of the findings below is covered by a test.

## Status of review V10

| | Status |
|---|---|
| R10-1 channel saves from a link or QR on the first radio | Fixed: `saveChannelSet(…, viaRadio:)`, called with the window's radio (`sendingRadio(for:)`). |
| R10-2 discovery scan and beacon join on the first radio | Fixed: the scans take their radio; the join, add and slot helpers take `viaRadio`. |
| R10-3 sends while the window's radio is off | Fixed for channels, and for DMs whose thread has that radio; one case left, R11-3. |
| R10-4 node actions and waypoints on the first radio | Fixed for Trace Route, Local Stats, Exchange Positions (radio and slot), Exchange User Info and waypoints; Client History and Remove Node were missed, R11-1 and R11-2. |
| R10-5 Siri's voice send | Fixed: any radio connected, then the chosen one; off or not chosen, it fails asking to open the app. |
| R10-6 services without a connected choice | Replaced by W-15: with several radios known, each service in use has a chosen radio, waited for while it's off. |
| R10-7 intents | Fixed: a radio named or chosen that's off says "That radio isn't connected."; factory reset and shut down name the radio before confirming; Add Contact, Save Channel Settings and Send Waypoint take a radio. |
| R10-8 Mesh Beacon save, the Siri question | Fixed: the save passes its window; the question is gone (W-15). |

## Findings

Ranked most serious first. "Sure" is how confident I am that it happens as described.

### R11-1. Remove Node from another radio's window goes out on the first radio's link

- `AccessoryManager+ToRadio.swift:1453-1474` (`removeNode` addresses the admin message to
  `connectedNodeNum` and sends it with `send(toRadio)`, the first radio's connection); callers pass
  the window's radio (`NodeList.swift:205`, `DeleteNodeButton.swift:53`, `UnheardNodesBanner.swift:183`).
- In B's window the removal is addressed to B but handed to A, which sends it over the mesh to B
  as a remote admin message without B's session key, so B doesn't remove the node. The app then
  deletes the node, its user and every radio's observations from the shared store, and B's next
  node DB brings it back. The unheard-nodes clean-up after a LoRa change (`UnheardNodesBanner`)
  does this for many nodes at once. With the first radio gone, the send throws and nothing
  happens.
- Favorite and ignore already go through `sendLocalAdmin` (by radio); this one should too.
- Sure: high for the code path.

### R11-2. Client History from another radio's window goes out on the first radio's link

- `Views/Nodes/Helpers/Actions/ClientHistoryButton.swift:17-21` (`channelSlot(toReach:)` without
  `fromRadio`), `AccessoryManager+ToRadio.swift:1376-1404` (`requestStoreAndForwardClientHistory`
  sends with `send(toRadio)`).
- The request carries the window's radio as `from` but goes out through the first radio, on the
  first radio's slot for the node; the store and forward router answers the radio that sent it.
  Missed by T330, which moved the other node actions.
- Sure: high.

### R11-3. Minor

- `Views/Messages/UserMessageList.swift:434-445, 472-474`: a window whose radio is off and has no
  history with the node isn't in `conversationRadios` (connected radios plus radios with history),
  so `selectedRadio` falls to `conversationRadios.first`, another connected radio, and a reply goes
  from it. Adding the window's radio to `conversationRadios` always would close it.
- `AccessoryManager+ToRadio.swift:1490-1492`: `requestDeviceMetadata` requires `isConnected`, the
  first radio's flag, so Node Detail's metadata request fails in B's window with the first radio
  gone, though the message itself routes by radio.
- `AccessoryManager+ToRadio.swift:3178`: `exchangeUserInfo` falls back to the first radio's link
  when its `fromUser`'s radio isn't connected. The button only shows while the window's radio is
  connected, so it's a race at most, but it's the swap T330 set out to remove.
- Worth a look in the device test: the Choose Radios sheet is presented from the same view as
  onboarding, the lock-down and firmware gates, the per-radio passphrase sheet and the attention
  alert (`ContentView.swift:53, 61-90`). SwiftUI shows one of those at a time; check that each
  comes up once the other closes, for example a locked radio joining for the first time.

## Checked and found fine

- W-15 in `AccessoryManager+ServiceRadios.swift`: `knownRadios` are radios connected with this
  version, so merged backups don't count and a switcher stays a single-radio user; with one known,
  every service and intent uses the connected radio, as on `main`; with several, `radioNum(for:)`
  is the chosen radio also while it's off, and `session(for:)` is nil then, so TAK stops, Siri
  and Shortcuts say it isn't connected, CarPlay lists the radio's channels from the store and a
  send fails; `servicesNeedingRadio` drives the sheet, which can't be dismissed until each service
  in use has a radio (or TAK is turned off); removing a radio clears its choices; Clear App Data
  clears them all; a renumber moves them.
- The sends a window makes (T330): `sendingRadio(for:)` is the window's radio also while it's off
  (`knownNodeNums`), so a send fails rather than using another radio; `.firstRadio` (one window on
  one radio) passes nil, the first radio, as before. Beacon joins and adds route their channel and
  LoRa saves by the radio's own user. Every remaining `send(toRadio)` without a radio in `+ToRadio`
  is R11-1, R11-2, the heartbeat's no-session call, or `sendAdminMessageToRadio`'s fallback when
  `adminRoute` finds no radio.
- The channel composer: `sendingSlot` no longer falls to another radio's slot; with the window's
  radio off it sends through that radio and fails.
- Siri's voice send, the App Intents' radio handling and the destructive confirmations, as in the
  status table.
- Single radio against `main`: `hasSeveralRadios` is false with one known radio, so services,
  Siri, Shortcuts, CarPlay and the sharing snapshot use the connected radio; the sheet never shows;
  the window is `.firstRadio`, whose sends pass nil as before.
