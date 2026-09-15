# baaar

A lightweight menu bar manager for macOS 27. Hide the status icons you don't need and reach them from a small bar under the menu bar, like Ice and its Ice Bar.

## Use

- **⌘-drag** icons to the left of the `‹` divider.
- **Click** the baaar icon to hide them. Click it again to open the bar with the hidden icons; click one to open its menu.
- **⌥-click** shows the hidden icons in the menu bar instead.
- **Right-click** for Refresh Icons, Bar Layout (horizontal bar or vertical list with names), Launch at Login and Diagnostics.

baaar needs **Accessibility** to list and press icons. **Screen Recording** is optional and only used to picture the icons: baaar takes a still of the menu bar while an icon is visible, crops that icon and caches it, so the bar can show it once it is hidden. Without it the bar shows each owning app's icon. Nothing else is captured or leaves the Mac.

## How it works on macOS 27

macOS 27 draws the whole menu bar into a single WindowServer window, which broke every manager built on per-icon windows (Ice, Bartender, Hidden Bar). baaar uses only what still works:

| Need | Mechanism |
| --- | --- |
| Hide | The divider grows to 45% of the screen width. macOS can't fit it, so it overflows the divider and everything to its left. Past ~48% macOS drops just the divider, so the width matters. |
| List icons | Each app's `AXExtrasMenuBar`. Hidden icons keep reporting their last on-screen frame, so they are sorted against the divider's last known position. |
| Picture icons | A ScreenCaptureKit shot of the transparent "Menubar" window, cropped to each icon's frame while it is visible and trimmed to its pixels, cached in `~/Library/Caches/com.aaangelmartin.baaar`. Icons macOS itself overflowed behind its `«` chevron are pictured by expanding the chevron for a moment. |
| Open an icon | `AXPress` on the hidden icon opens its menu without revealing the section. The call blocks until the menu closes, so it runs off the main thread and its timeout is expected. |

Apple's own icons (Wi-Fi, battery…) are not pressable through Accessibility and vanish from it while hidden, so keep them to the right of the divider.

## Build

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
scripts/build.sh            # Debug build
CONFIGURATION=Release scripts/build.sh --install   # copy to /Applications and launch
```

Set `CODE_SIGN_IDENTITY` if you have more than one "Apple Development" certificate. Privacy grants only survive rebuilds when the signing identity stays the same, and System Settings only lists apps installed in a regular location such as `/Applications`.
