# Review V34: the V33 fix (T396)

Branch `feature/multi-radio` at `8b32240b`, working tree clean. This review checks T396, the fix
for review V33, against the files.

## What changed since V33

- `RadioWindowTracker` in `RadioWindowViews.swift`: it now counts each window's views
  (`windowViews: [UUID: Int]`). `shownWindows` is computed from that count.
- One new test, `RadioWindowTrackerTests.viewSwapKeepsTheWindow`.
- `bluetooth.md`, `settings.md`, `HANDOFF.md` and `tasks.md` (T396). The V33 review file is
  committed with the fix.

## How it was checked

- **Tests:** one run of `MultiRadioConnectFlowTests`, `RadioRemovalTests` and
  `RadioWindowTrackerTests` in the iOS Simulator. 70 tests, all passed. The build changed no
  tracked files.
- **Probe:** a temporary test, deleted after the run, checked the other events the count now
  depends on. Results under "Checked and found fine".
- **SwiftLint:** clean on `RadioWindowViews.swift` and `RouterTests.swift`.
- **Removed lines:** the commit removes only the set-based tracker lines, the reworded
  `bluetooth.md` and `settings.md` lines, and the rewrapped HANDOFF lines. Every touched file
  ends in a newline, and no added HANDOFF line is over 100 characters.

## The V33 findings

| Finding | Status | Notes |
|---|---|---|
| V33-1 the tracker lost a window when a store reset swapped its view | Fixed | Details below. |
| Minor 1 `HANDOFF.md:567` too long | Fixed | Rewrapped. |
| Minor 2 T134's list had the old only-radio message | Fixed | T388's list names T390's message and the one it replaced. |
| Minor 3 the docs' name for Clear App Data, and the favorites wording | Fixed | `settings.md:42` says **Clear App Data**. `bluetooth.md:98` keeps favorites only while another radio's data is kept. |
| Minor 4 the editor's stale copies | Done | Checked on disk with `git diff` (T396). |

How V33-1 is fixed:

- In a swap, the new view's `onAppear` takes the count to 2 and the old view's `onDisappear`
  takes it back to 1, so the window stays counted (`RadioWindowViews.swift:63-79`).
- The closing mark is cleared only when the count goes from 0 to 1 (the window opened again) or
  reaches 0 (it went). A swap of a closing window's view keeps the mark.
- `windowDisappeared` without a matching `windowAppeared` drops the entry rather than storing a
  negative count.
- `viewSwapKeepsTheWindow` covers all three V33 cases:
  - A swap followed by another window's removal: no Connect window opens.
  - Clear App Data with two swapped windows: one Connect window, from the last window told.
  - A closing window whose view swaps: it stays closing.

The paths traced by hand against the count:

- **Removing the only radio.** Its window is told before the erase
  (`AccessoryManager+RadioRemoval.swift:119-122`), which marks it closing and opens the Connect
  window. The erase's swap then takes the count 1 → 2 → 1 with the mark kept. The window's close
  takes it to 0 and clears the mark.
- **Clear App Data with windows A and B.** The swaps settle at 1 each before
  `forgetRadiosNotInStore` sends. A is told and not last; B is told and last. One Connect window
  opens.
- **Removing B after Reset NodeDB with A alone.** A's swap leaves A at 1, so removing B doesn't
  open a Connect window. HANDOFF now has this as a device check.
- **Backup restore.** The full unmount takes each count to 0 and clears its mark, and the
  remount takes it back to 1, as before.

## Findings

None.

## Minors

None.

## Checked and found fine

- **Presentations over a radio window.** `ContentView` puts the lockdown and firmware gates up
  as `fullScreenCover`s (`ContentView.swift:168`, `:172`). A count would drift if a presentation
  sent `onDisappear` or `onAppear` on the view underneath. The probe showed it sends neither for
  a full-screen cover or a sheet, shown or dismissed.
- **Swap and close events.** A view swap while a cover is up sends one `onAppear` and one
  `onDisappear`. Removing the window's root sends `onDisappear`, which a radio window's close
  depends on.
- **One window per radio (W-03).** `openWindow(id:value:)` brings a radio's existing window
  forward rather than opening a second. So a count above 1 only happens during a swap.
- **No other users.** `shownWindows` is read only by `closesLastWindow` and the tests. Making it
  computed changes nothing else.

## Still open (unchanged)

- Strings: T134, now with T390's only-radio message.
- Docs HTML: T122 (`bluetooth.md` and `settings.md` changed again).
- The device checklist, including T393 and the new V33-1 check. On the Mac, also check a window
  tab group: macOS can merge radio windows into one tabbed window (`ToolbarLayoutNudge`'s
  comment). Removing the front tab's radio should not open a Connect window while another tab
  remains. The simulator can't check this.
- Committing this review.
