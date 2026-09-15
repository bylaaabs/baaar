# baaar

A menu bar manager for macOS 27.

By `laaabs.`

**Why**: macOS 27 draws the whole menu bar into a single window, which broke every manager built on
per-item windows, and a crowded bar still hides items behind the notch. baaar hides the items you do
not need through MenuBarAgent's own visibility restriction, so their space comes back, and shows them
again from the menu bar or from a small bar under it. It runs entirely on the Mac: no network, no
telemetry.

## Status

Alpha. macOS 27 only. No signed release yet: build from source.

baaar depends on a private macOS framework. A macOS update can change it; when it does, baaar keeps
running, stops hiding, and says so in its settings.

## Use

baaar adds two items to the menu bar: the **chevron**, which hides and shows, and the **baaar icon**,
which opens its menu and settings. The menu bar is split in three sections: **visible**, **hidden**
and **always hidden**.

- **Drag bundles between sections** in the layout pane of settings. Everything one bundle puts in the menu bar
  moves together.
- **Click the chevron** to show hidden items. **⌥-click** it to include always hidden ones.
  **Right-click** it for its menu.
- **Pick how hidden items appear**: in the menu bar itself, a horizontal bar, a vertical list or a grid.
- **Click an item** in the bar, list or grid: baaar shows it in the menu bar for a moment, opens its
  menu under it, and hides it again when the menu closes.

## How it works

| Need | Mechanism |
| --- | --- |
| Hide | MenuBarAgent's visibility restriction: `MBAssessmentModeAssertion` in the private `MenuBarClientCore` framework, the allow-list assessment mode uses. baaar allows every running bundle except the hidden ones, plus the system items that stay visible. MenuBarAgent lays out only those, and the rest leave the bar and free their space. The assertion dies with baaar, so quitting or crashing brings every item back. |
| List items | Each process's `AXExtrasMenuBar`, read through Accessibility in parallel. Hidden items are remembered from the last scan that saw them. |
| Picture items | A few items at a time are shown alone in the menu bar, with baaar's own items blanked. A ScreenCaptureKit still of the transparent `Menubar` window is cropped to each item and cached in `~/Library/Caches/com.laaabs.baaar`. The cursor never moves. |
| Open an item | The item's bundle is allowed for a moment, then `AXPress` opens it where it is drawn. baaar watches for its menu or popover to close, then hides it again. If there is no room next to the visible items, everything else hides while the menu is open. |
| Notification Center | MenuBarAgent will not open it while a restriction is active, so a click on the clock lifts the restriction until Notification Center closes. |

## Permissions

- **Accessibility, required.** baaar lists, opens and pictures items through it.
- **Screen Recording, optional.** Used only to picture items: stills of the menu bar, cropped to each
  item. Without it the bar shows each owner's icon. Never video, never another window.

Details in [docs/PERMISSIONS.md](docs/PERMISSIONS.md).

## Known limitations

- **Bundles hide whole.** Every item one bundle puts in the menu bar shares a section.
- **Apple's other modules disappear while anything is hidden.** Only the nine system items (battery,
  Bluetooth, clock, displays, keyboard brightness, sound, Wi-Fi, screen mirroring, Control Center) can
  stay visible under the restriction. Focus, Fast User Switching and the rest come back when nothing is
  hidden.
- **Notification Center needs the restriction lifted while it is open**, so hidden items show in the
  menu bar until it closes.
- **A menu bar that is not on screen cannot be pictured.** In full screen or with the menu bar set to
  hide, baaar waits for it.
- **Privacy grants follow the signing identity.** Rebuilding with a different certificate asks for
  them again.

## Docs

| Doc | What it covers |
|---|---|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Code structure, data flow, concurrency, files on disk |
| [PERMISSIONS.md](docs/PERMISSIONS.md) | Every permission baaar asks for, when and why |
| [PRIVACY.md](docs/PRIVACY.md) | What stays on the Mac, and the empty list of what leaves it |
| [20-decision-log.md](docs/20-decision-log.md) | The calls that are hard to reverse, and why |

## Install

No release yet. The first one will be `0.4.0-alpha.1`, as a notarized DMG and a Homebrew cask in
[bylaaabs/homebrew-tap](https://github.com/bylaaabs/homebrew-tap). Until then, build from source.

## Build from source

Requirements: macOS 27, Xcode 26 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
git clone https://github.com/bylaaabs/baaar.git
cd baaar
scripts/build.sh                                   # Debug build
CONFIGURATION=Release scripts/build.sh --install   # copy to /Applications and launch
```

Set `CODE_SIGN_IDENTITY` if you have more than one "Apple Development" certificate. System Settings
lists privacy grants only for tools installed in a regular location such as `/Applications`, which is
why `--install` copies baaar there.

## Community

- [Contributing guide](CONTRIBUTING.md) - how to propose changes
- [AGENTS.md](AGENTS.md) - naming, voice and architecture rules, for people and agents
- [Code of Conduct](CODE_OF_CONDUCT.md) - Contributor Covenant v2.1
- [Security policy](SECURITY.md) - how to report vulnerabilities responsibly
- [Changelog](CHANGELOG.md) - release notes

Bugs and feature requests on [Issues](https://github.com/bylaaabs/baaar/issues).

## License

[Apache License 2.0](LICENSE) © 2026 [laaabs.](https://laaabs.com)
