# Architecture - baaar

One target, `baaar`, a menu bar agent (`LSUIElement`) in Swift 6 with strict concurrency, AppKit for the
menu bar and the floating panel, SwiftUI for settings. No third-party dependencies.

## Modules

```
baaar/App/        entry point, AppDelegate (wiring, clicks, menus, DEBUG commands), AppModel
baaar/MenuBar/    MenuBarController, VisibilityRestriction, ControlItems, WindowWatch
baaar/Items/      ItemScanner, MenuBarItem, SystemItem, MenuBarSnapshot
baaar/Capture/    ItemImageCache
baaar/Bar/        BarController: the bar, list and grid
baaar/Settings/   the settings window and its panes
baaar/Support/    Settings (UserDefaults), Permissions, Log, Diagnostics
baaar/Theme/      design tokens and brand components
baaar/Resources/  string catalogs (English and Spanish), fonts
```

## The pieces

- **`VisibilityRestriction`** is the only code that touches private API. It loads
  `MenuBarClientCore`, checks every selector it calls (`isAvailable`), and turns a set of concealed keys
  (bundle identifiers and `system.<item>` keys) into an `MBAssessmentModeAssertion` that allows
  everything else running. A new assertion replaces the old one only once it is active. With nothing to
  conceal, it holds none. It re-issues the assertion when a bundle it does not know about launches.
- **`MenuBarController`** owns the state: the reveal level (none, hidden, all), the sections, the last
  scan, and at most one temporary task (opening an item, picturing items, Notification Center) that
  adds allowed or concealed keys on top of the sections. Any new task or user action cancels the current
  one and puts the sections back.
- **`ItemScanner`** reads every process's `AXExtrasMenuBar` on a dedicated concurrent queue, one AX
  messaging timeout per process, and returns a `MenuBarSnapshot` sorted left to right. A background loop
  scans every 5 seconds so the bar opens from a recent scan.
- **`ItemImageCache`** captures the `Menubar` window with ScreenCaptureKit, crops each item to its AX
  frame, trims transparent padding and rejects empty captures.
- **`ControlItems`** are baaar's two status items: the chevron and the baaar icon.
- **`BarController`** shows hidden items in a non-activating floating panel under the chevron, and
  closes on a click outside, Escape or losing key status.
- **`WindowWatch`** reads the on-screen window list to tell when a pressed item's menu or popover is
  open, and which window is under a click.
- **`AppModel`** is the observable model the settings window reads and edits. Views never call the
  controller directly.

## Flows

**Hide and show.** A click on the chevron changes the reveal level, or opens the panel from the last
scan. `MenuBarController.apply()` computes the concealed keys and hands them to `VisibilityRestriction`.

**Open a hidden item.** The item's key is allowed for the temporary task, baaar waits until the item is
drawn and its frame holds still, presses it with `AXPress` off the main thread, and waits while a menu
or popover hangs from the bar. When no room is left, every other item is concealed while the menu is
open.

**Picture items.** Items are grouped into batches that fit next to the notch. Each batch is allowed
alone, baaar's own items are blanked, frames settle, and the batch is captured.

## Concurrency

- UI, controllers and model are `@MainActor`.
- AX scans run on `com.laaabs.baaar.scanner`, a concurrent dispatch queue, never on Swift's shared pool,
  so a slow process only costs its own timeout. AX requests to baaar's own process are answered on the
  main thread, so the main thread never scans.
- `AXPress` runs on a global queue with a 120 s timeout, because it blocks until the item's menu closes.
- Temporary tasks carry a generation number; a superseded task stops at its next check.

## Files on disk

| Path | What |
|---|---|
| `~/Library/Preferences/com.laaabs.baaar.plist` | sections, known bundles, display mode, chevron style, settings |
| `~/Library/Caches/com.laaabs.baaar/` | PNG pictures of items |
| `~/Library/Logs/baaar/` | `baaar.log`, and `diagnostics.txt` from `--diagnose` |

See [PRIVACY.md](PRIVACY.md).

## System frameworks

AppKit, SwiftUI, ApplicationServices (Accessibility), ScreenCaptureKit, ServiceManagement (launch at
login), and the private `MenuBarClientCore`. Why the private one:
[20-decision-log.md](20-decision-log.md).

## Bundled resources

The Outfit variable font (`baaar/Resources/Fonts/Outfit-Variable.ttf`), licensed under the SIL Open
Font License 1.1.
