# baaar

A lightweight menu bar manager for macOS 27. Hide the status icons you don't need and reach them from a small bar under the menu bar, like Ice and its Ice Bar.

## Use

baaar adds two icons: the **‹ chevron**, which hides and shows, and the **baaar icon**, which holds every setting. The menu bar is split in three sections, left to right: **Always Hidden** `|` **Hidden** `‹` **Visible**.

- **⌘-drag** icons across the chevron or the thin `|` divider, or drag them between sections in **Edit Layout…**, which moves them in the menu bar for you.
- **Click the chevron** to see hidden icons; **⌥-click** it to include the always-hidden ones. Click again to hide.
- **Pick how they appear** from the baaar icon → Show Hidden Items: in the menu bar itself, a horizontal bar, a vertical list or a grid.
- **Click an icon** in the bar, list or grid: baaar shows it in the menu bar, opens it so its menu appears under it, and hides it again when the menu closes.

baaar needs **Accessibility** to list, press and move icons. **Screen Recording** is optional and only used to picture the icons: baaar takes a still of the menu bar while an icon is visible, crops that icon and caches it, so the bar can show it once it is hidden. Without it the bar shows each owning app's icon. Nothing else is captured or leaves the Mac.

## How it works on macOS 27

macOS 27 draws the whole menu bar into a single WindowServer window, which broke every manager built on per-icon windows (Ice, Bartender, Hidden Bar). baaar uses only what still works:

| Need | Mechanism |
| --- | --- |
| Hide | A divider grows until it spans exactly to the left edge of the status area. macOS then overflows everything to its left while the divider, and its chevron, stay on screen. One point wider and macOS overflows the divider too, so baaar searches for the width, checks it against the position of macOS's own `«` overflow chevron, and remembers it per screen. |
| List icons | Each app's `AXExtrasMenuBar`. Hidden icons keep reporting their last on-screen frame, so they are sorted against the dividers' last known positions. |
| Picture icons | A ScreenCaptureKit shot of the transparent "Menubar" window, cropped to each icon's frame while it is visible and trimmed to its pixels, cached in `~/Library/Caches/com.aaangelmartin.baaar`. Icons macOS itself overflowed behind its `«` chevron are pictured by expanding the chevron for a moment. |
| Open an icon | The section is revealed, then `AXPress` opens the icon where it is drawn. The call blocks until the menu closes, which tells baaar when to hide again. |
| Move an icon | A synthetic ⌘-drag, the same gesture a person uses. |

Apple's own icons (Wi-Fi, battery…) are not pressable through Accessibility and vanish from it while hidden, so keep them in the visible section.

## Build

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
scripts/build.sh            # Debug build
CONFIGURATION=Release scripts/build.sh --install   # copy to /Applications and launch
```

Set `CODE_SIGN_IDENTITY` if you have more than one "Apple Development" certificate. Privacy grants only survive rebuilds when the signing identity stays the same, and System Settings only lists apps installed in a regular location such as `/Applications`.
