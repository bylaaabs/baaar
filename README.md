# baaar

A lightweight menu bar manager for macOS 27. Hide the status icons you don't need and reach them from a small bar under the menu bar, like Ice and its Ice Bar.

## Use

- **⌘-drag** icons to the left of the `‹` divider.
- **Click** the baaar icon to hide them. Click it again to open the bar with the hidden icons; click one to open its menu.
- **⌥-click** shows the hidden icons in the menu bar instead.
- **Right-click** for Refresh Icons, Launch at Login and Diagnostics.

baaar needs **Accessibility** to list and press icons. **Screen Recording** is optional: with it the bar shows the real icons, without it the owning app's icon.

## How it works on macOS 27

macOS 27 draws the whole menu bar into a single WindowServer window, which broke every manager built on per-icon windows (Ice, Bartender, Hidden Bar). baaar uses only what still works:

| Need | Mechanism |
| --- | --- |
| Hide | The divider grows to 45% of the screen width. macOS can't fit it, so it overflows the divider and everything to its left. Past ~48% macOS drops just the divider, so the width matters. |
| List icons | Each app's `AXExtrasMenuBar`. Hidden icons keep reporting their last on-screen frame, so they are sorted against the divider's last known position. |
| Picture icons | A ScreenCaptureKit shot of the transparent "Menubar" window, cropped to each icon's frame while it is visible, cached in `~/Library/Caches/com.aaangelmartin.baaar`. |
| Open an icon | `AXPress` on the hidden icon opens its menu without revealing the section. |

Apple's own icons (Wi-Fi, battery…) are not pressable through Accessibility and vanish from it while hidden, so keep them to the right of the divider.

## Build

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
scripts/build.sh            # Debug build
CONFIGURATION=Release scripts/build.sh --install   # copy to /Applications and launch
```

Set `CODE_SIGN_IDENTITY` if you have more than one "Apple Development" certificate. Privacy grants only survive rebuilds when the signing identity stays the same, and System Settings only lists apps installed in a regular location such as `/Applications`.
