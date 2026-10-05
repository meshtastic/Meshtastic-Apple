# Spec: One Window per Radio (part of 021)

**Feature**: 021-multi-radio-connections, decision D-19 | **Status**: decided 2026-09-29, not started
**Main spec**: [spec.md](./spec.md) | **Tasks**: [tasks.md](./tasks.md)

## Summary

Each window works with one radio, as if it were its own copy of the app. All windows share one
database, so the node list and the history of a channel the radios share (channel 0 on the same
key, say) are the same in every window. Everything else in a window belongs to its radio: its
settings, its direct messages, its connection status, its prompts.

There is no app-wide focused radio. The radio a window works with is that window's, and nothing
moves it to another window or another radio behind the user's back.

- Mac: four radios, four windows, side by side.
- iPad with several windows: the same as the Mac.
- iPhone: one window, which works with one radio at a time; picking another radio in Connect
  changes that window's radio. The other radios stay connected.

This is what the feature was meant to be from the start. It replaces the focused radio of D-12,
D-13 and D-17, and ships in the same pull request as the rest of 021 (D-02).

## Why

In 021 as built so far, one radio is the focused one: Settings and Messages follow it, and the
others are connected alongside. A lot of 021's complexity is moving that focus between radios:
the focus handover when the focused radio drops, the radio a BLE restore passed over, the
connect-first override, "focused this run". Tying the radio to a window removes all of it. Each
window owns one value, its radio, and nothing hands it over.

## Decisions

| ID | Decision |
|---|---|
| W-01 | Closing a radio's window only hides it. The radio stays connected; it's disconnected the usual way (Disconnect in Connect or Settings). A hidden window is reopened from the Window menu. |
| W-02 | Disconnecting a radio keeps its window, showing the radio off with Connect and Remove Radio (revised 2026-10-04; it used to close the window). Remove Radio closes it. On iPhone and iPad with several radios the one window keeps showing the radio it disconnected until the user picks another. The Mac's Connect window and Radios menu list every one of the user's radios, connected or off, each opening its window. Remove Radio sits beside Disconnect everywhere, and is offered for a single radio too; its confirmation says the radio itself isn't changed. Another radio is added from a dedicated Connect window, opened from a menu. |
| W-03 | One radio per window. A radio already open in a window is never opened in a second one; its window comes to the front instead. |
| W-04 | iPhone has one window. The other radios stay connected in the background and the window switches between them. |
| W-05 | Tapping a notification: a direct message opens the window of the radio that received it; a channel message opens the channel in the first open window whose radio has that channel. |
| W-06 | Read state is shared: one row per message, so reading the shared channel in one window marks it read in every window. Direct messages belong to one radio anyway. |
| W-07 | Menu bar commands act on the radio of the key (active) window. With the Connect window in front, commands that need a radio are disabled. |
| W-08 | Siri and CarPlay use a default radio the user picks (W-10, W-11, W-15). |
| W-12 | Adding a radio always keeps the others connected: "Add a Radio" means add. The Keep Both / Switch question (D-05) and its App Settings choice go. The new radio opens in its own window on the Mac and iPad; on iPhone the window shows it, and the previous radio stays connected. At four radios, the radios to add are disabled with the reason shown; the app never disconnects one on its own. |
| W-13 | Switching the window's radio (iPhone, or an iPad window) is from Connect or from the connection indicator's radio menu (`RadioSwitcherMenu`). Switching never disconnects anything; disconnecting is always its own action. |
| W-14 | The composer's "Via" picker (sending on a shared channel through another connected radio that has it) stays on iPhone and iPad, defaulting to the window's radio, and goes on the Mac, where that radio has its own window. The choice lasts while the conversation is open, as today. |

## What's shared and what's per window

| Shared (one database) | Per window (its radio's) |
|---|---|
| Nodes, positions, telemetry, waypoints | The radio, and its connection status indicator |
| A channel's history, matched by channel key | Navigation: tab, selected node, selected channel |
| Whether a message is read | Settings pages (that radio's config and modules) |
| App settings, map, backups | Direct messages (that radio's) |
| The phone's position, sent to every connected radio | Lock-down passphrase, firmware-too-old prompt |
| | Heard By's default (this window's radio) |

## Siri, CarPlay and the other services

What's there today (checked 2026-09-29): App Settings has a "CarPlay & Siri" radio choice
(`RadioService.carPlay`, `ServiceRadioPickers`), and the Shortcuts send intents
(`MessageChannelIntent`, `MessageNodeIntent`) take an optional "Radio Node Number"; with none they
use the CarPlay & Siri radio, which today falls back to the focused one. TAK and the Apple Watch
have the same kind of choice.

- **W-09.** Replaced by W-15 (2026-09-29): the radio for Siri and CarPlay is a required choice, not
  a one-time question that can be put off.
- **W-10.** The Shortcuts commands take a radio by name, not by node number: "Send a message to
  Alice via Base Station". With no radio named, the default is used. A named radio that isn't
  connected is an error, never a send through another radio (as today).
- **W-11.** A new command sets the default radio: "Make Base Station my Meshtastic radio".
- With one radio known, every service uses it, as on `main`, and nothing is asked.
- The voice "send a message" that goes through SiriKit (`INSendMessageIntent`) has no place for a
  radio name, so it always uses the default.
- **W-15** (decided 2026-09-29, replaces W-09 and the "radio connected first" fallback): with two or
  more of the user's radios known (connected with this version), a service that's in use must have
  a radio chosen; the user is made to pick one. In use means:
  - TAK: the TAK server is on. Turning it on asks first; without a pick it stays off.
  - Apple Watch: a paired watch has the Meshtastic app.
  - CarPlay & Siri: always, as soon as a second radio is known (it also drives the Share sheet and
    notification replies).
  A sheet lists the radios, connected first, and closes only once each such service has a radio;
  it shows in the one window, and in the Connect window on the Mac. App Settings has no
  "Automatic"; a service not in use shows "Not set".
- Removing the chosen radio clears that choice; if the service is in use and two or more radios
  remain, the sheet asks again; with one left, that radio is used, as for a single-radio user.
- A chosen radio that isn't connected is waited for, never replaced by another: TAK stops bridging
  until it's back, Siri and Shortcuts say it isn't connected, CarPlay shows its conversations but
  a send says it isn't connected, and the Watch shows its nodes.

## BLE restore (iPhone and iPad)

iOS can close the app in the background and relaunch it when a Bluetooth radio it was connected to
sends something. It then hands the app the radios it still had open, and the app rebuilds their
connections. Today the app picks one of them as the focused radio, restores it first, and holds
the others until that one has finished connecting. Most of the connection review rounds (T155,
T178, T190, T201, T212, T240) were about that choice.

With no focus there is nothing to choose: every radio iOS hands back is restored the same way,
each through its own connect, one handshake at a time (the handshake gate already does that). The
only thing kept is which radio the iPhone's window showed, saved with the window, so the app opens
on the same radio. This part gets simpler.

## App-wide work in the connect steps

Some steps in a connect are for the app, not for the radio being connected. Today they run only in
the focused radio's connect (`if attempt.isFocused`, 30 places in `AccessoryManager+Connect.swift`).
They come in two kinds:

- **Work done once for the app**: refreshing the bundled device catalog and device images (Steps
  3a and 3b), stopping discovery, pruning stale nodes, the unread badges, starting the phone
  position loop, reconnecting the remembered radios. Without a focus these run once per launch,
  from whichever radio finishes connecting first, or on their own schedule.
- **One radio's state kept on the manager**: its connection status, last error, "firmware update
  required", whether Disconnect is allowed, its lock-down state. Each moves onto that radio's
  `RadioSession`, where the window reads it.

Neither is hard; it's a list of places to change, each small.

## What changes in the code

1. **A window's radio.** A `WindowGroup(for:)` value naming the radio (its peripheral id, known
   before its node number, and the node number once known), passed to the views as an environment
   value. Views read it instead of `activeDeviceNum`, `activeConnection` and `PreferredRadio`: 56
   view files, about 370 references across the app today.
2. **A router per window.** `AppState.router` is shared (23 files use it), so opening a node in one
   window would navigate every window. Each window gets its own.
3. **Per-radio state onto the session**, as above.
4. **No app-wide focus.** `activeConnection` and `additionalRadios` become one set of sessions.
   `focusConnectedRadio`, the focus handover, `restoreDisplacedPreferred`, the connect-first
   override and `radiosFocusedThisRun` go. `PreferredRadio` becomes the list of radios to reconnect
   (`MyInfoEntity.autoConnect` already holds that).
5. **Windows.** The Connect window (W-02), each radio's window opened when it connects, hidden on
   close (W-01), kept showing the radio off when it's disconnected and closed when it's removed
   (W-02), brought back at launch by macOS window restoration and for every radio that reconnects,
   and the Radios menu listing the user's radios, connected or off.
6. **Siri and CarPlay** as W-09 to W-11.
7. **Adding and switching** as W-12 and W-13; the composer's picker as W-14.

## Risks

- Navigation: every screen that assumes one connected node has to take the window's radio.
- Settings screens that fetch "the connected node" when they appear.
- Catalyst window restoration: each window has to come back with its radio.
- The pull request grows. 021 is already large; this adds most of the UI side.

## Non-goals

- A separate database per window.
- More than four radios.
- Any change to the radio firmware.
