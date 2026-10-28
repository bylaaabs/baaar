# Changelog

All notable changes to baaar are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). The first release of this codebase will be
`0.1.0`.

## [Unreleased]

## [0.1.1] - 2026-10-28

### Added

- baaar speaks Spanish: menus, settings and the bar follow the language macOS uses.

### Changed

- baaar needs macOS 27 to open. It used to open on macOS 26, where it can hide nothing.
- While nothing is hidden and new items stay visible, baaar no longer reads the menu bar of every
  running bundle every 5 s.
- The icon is the baaar wordmark, white on black with its cyan dot, as the brand draws it, instead of
  the chevron and three dots.

### Fixed

- A hidden bundle that launched after baaar showed in the menu bar until the next click on the chevron.
  It is now hidden as soon as it launches, and nothing is held once no hidden bundle is running.
- Launch at login showed on when macOS refused to register baaar. It now shows what macOS did.
- The log grew for good, and lines written at the same time could mix. Past 1 MB it now moves to
  `baaar.log.1`, and lines are written one at a time.
- The layout pane could list items in a different order from one read to the next when some had no
  entry in macOS's layout table.
- Hidden items were pictured again only when baaar launched, so a bundle that relaunched with a new
  icon, or a new bundle that went straight to hidden, showed an old picture or its owner's icon until baaar
  restarted. They are now pictured a few seconds after the bundle launches.
- Items pictured while the menu bar was hidden, in a full-screen space, showed as black boxes in the
  bar, list, grid and layout pane. Those captures are now refused, and black pictures already kept are
  dropped and taken again.
- A hidden item whose bundle changed its icon kept showing the old picture for good. An item pictured
  before its bundle last launched is pictured again the next time hidden items are, once.

### Documentation

- The privacy policy and the permissions page now cover the menu bar layout file: what baaar reads and
  writes in it, and how to take the access back.

## [0.1.0] - 2026-09-16

The first release of baaar for macOS 27.

### Added

- baaar, rebuilt from scratch for macOS 27, where the whole menu bar is drawn into one window.
- Hiding through MenuBarAgent's visibility restriction: hidden items leave the menu bar and free their
  space, and every item comes back if baaar quits or crashes.
- Three sections, visible, hidden and always hidden, assigned per bundle. Apple's nine system items
  (battery, Bluetooth, clock, displays, keyboard brightness, sound, Wi-Fi, screen mirroring and
  Control Center) are placed one by one.
- The chevron: click it to show hidden items, ⌥ or ⌃ click it to show only always hidden ones, right-click it
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
- A settings window with general, layout, permissions and about panes. The layout pane shows every
  item in its real order; drag to reorder or to move between sections, and macOS re-sorts the menu
  bar through its layout table, without the cursor. Needs access to that file, granted once.
- Bar colors from the laaabs. palette: black, graphite, cyan, white, or macOS glass.
- Launch at login.
- `--diagnose`, which writes what baaar sees to `~/Library/Logs/baaar/diagnostics.txt`.

### Changed

- The bundle identifier is `com.laaabs.baaar`. Settings from earlier `com.aaangelmartin.baaar`
  development builds are copied over once; privacy grants and cached pictures are not.
- Licensed under the Apache License 2.0.

[Unreleased]: https://github.com/bylaaabs/baaar/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/bylaaabs/baaar/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/bylaaabs/baaar/releases/tag/v0.1.0
