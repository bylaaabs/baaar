# Changelog

All notable changes to baaar are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). The first release of this codebase will be
`0.4.0-alpha.1`, after the legacy baaar's last cask, `0.3.0-alpha.5`.

## [Unreleased]

### Added

- baaar, rebuilt from scratch for macOS 27, where the whole menu bar is drawn into one window.
- Hiding through MenuBarAgent's visibility restriction: hidden items leave the menu bar and free their
  space, and every item comes back if baaar quits or crashes.
- Three sections, visible, hidden and always hidden, assigned per bundle. Apple's nine system items
  (battery, Bluetooth, clock, displays, keyboard brightness, sound, Wi-Fi, screen mirroring and
  Control Center) are placed one by one.
- The chevron: click it to show hidden items, ⌥-click it to include always hidden ones, right-click it
  for its menu. Five styles: chevron, arrow, triangle, circle and dots.
- Four ways to show hidden items: in the menu bar itself, a horizontal bar, a vertical list or a grid
  under the chevron.
- Opening a hidden item from the bar, list or grid: baaar shows it for a moment, opens its menu under
  it, and hides it again once the menu closes.
- Pictures of hidden items, taken a few at a time with each batch alone in the menu bar, without moving
  the cursor. Needs Screen Recording; without it the bar shows each owner's icon.
- Hiding again automatically in the menu bar mode, after a click elsewhere or 15 seconds away from the
  menu bar.
- A section for bundles baaar has not seen before.
- Notification Center opens from the clock while items are hidden.
- A settings window with general, layout, permissions and about panes. The layout pane moves bundles
  between sections by dragging.
- Launch at login.
- `--diagnose`, which writes what baaar sees to `~/Library/Logs/baaar/diagnostics.txt`.

### Changed

- The bundle identifier is `com.laaabs.baaar`. Settings from earlier `com.aaangelmartin.baaar`
  development builds are copied over once; privacy grants and cached pictures are not.
- Licensed under the Apache License 2.0.
