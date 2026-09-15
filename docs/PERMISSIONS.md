# Permissions - baaar

Every macOS permission baaar asks for, when it asks, and why.

## When baaar asks

The laaabs. rule is to ask only when a person takes an action that needs the permission. baaar follows
it for Screen Recording. **Accessibility is the exception**: baaar cannot list, hide or open a single
item without it, so it asks at first launch.

Grants belong to the code signature. System Settings lists them only for bundles in a regular location
such as `/Applications`, and a build signed with a different certificate is asked again.

## Accessibility

- **Required.**
- **Asked:** at launch, while it is not granted, and from settings, permissions.
- **Why:** macOS 27 draws every menu bar item into one window, and each process's `AXExtrasMenuBar` is
  the only list of them.
- **Used to:**
  - read every process's menu bar items: their identifier, label and frame
  - press an item when you click it in the bar, list or grid, so its menu opens under it
  - read Apple's system items from MenuBarAgent
- **Never used to** read window contents, text fields or keystrokes, or to click anything you did not
  click.
- **Without it:** baaar cannot list or open items. Its settings explain what is missing and link to the
  pane.
- **macOS pane:** System Settings, Privacy & Security, Accessibility.

## Screen Recording

- **Optional.**
- **Asked:** only when you press grant in settings, permissions.
- **Why:** a hidden item is not drawn, so the bar needs a picture taken while it was visible.
- **Used to:** take stills of the transparent window macOS titles `Menubar`, while a few items at a time
  are shown alone in it, then crop each item and cache it in `~/Library/Caches/com.laaabs.baaar`.
- **Never used to** record video, capture another window, or capture the desktop.
- **Without it:** everything works, and the bar, list, grid and layout pane show each owner's icon, or a
  symbol for Apple's system items, instead of the real item.
- **macOS pane:** System Settings, Privacy & Security, Screen & System Audio Recording.

## Things that need no prompt

- **Mouse click locations.** baaar watches where clicks land, system-wide, to hide items again after a
  click elsewhere, to dismiss the bar, and to notice clicks on the clock. macOS does not ask for this;
  it does not include the keyboard.
- **The on-screen window list** (owner, layer and bounds, no titles or contents), to tell when an item's
  menu or popover is open.
- **MenuBarAgent's visibility restriction.** A private assertion that allows or withholds menu bar
  items. It needs no permission and ends when baaar quits.
- **Launch at login**, registered through `SMAppService` when you turn it on. It shows in System
  Settings, General, Login Items.

## Network access

baaar makes no network calls. See [PRIVACY.md](PRIVACY.md).

## Revoking permissions

System Settings, Privacy & Security, then the pane, and turn baaar off. baaar notices within a second
while its permissions pane is open. Without Accessibility it stops listing and opening items; without
Screen Recording it keeps the pictures it already has and takes no new ones.
