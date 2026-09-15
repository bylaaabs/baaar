# Privacy policy - baaar

Last updated: 2026-09-15.

## What we collect

**Nothing.** baaar sends no analytics, no telemetry, no crash reports, no tracking and no advertising
identifiers. It does not contact laaabs. servers: there are none.

## What stays on your Mac

| Where | What | How to remove it |
|---|---|---|
| `~/Library/Preferences/com.laaabs.baaar.plist` | The section of every bundle and system item baaar has placed, the bundles it has seen, the display mode, the chevron style and the other settings | `defaults delete com.laaabs.baaar` |
| `~/Library/Caches/com.laaabs.baaar/` | PNG pictures of menu bar items, showing whatever each item displayed when it was pictured | delete the folder; baaar pictures items again when needed |
| `~/Library/Logs/baaar/baaar.log` | Errors and events, with bundle identifiers and item labels | delete the file |
| `~/Library/Logs/baaar/diagnostics.txt` | Written only when you run `baaar --diagnose`: screens, sections, every item's label and frame, and the MenuBarAgent tree | delete the file |

Launch at login, when you turn it on, is registered with macOS through `SMAppService` and shows in
System Settings, General, Login Items.

baaar never reads the contents of other windows, never captures video and never watches the keyboard.
Screen Recording, when granted, is used only for stills of the menu bar window, cropped to each item.

## What goes over the network

| Call | When | Why | Encryption |
|---|---|---|---|
| none | | | |

That is the **complete list**: baaar makes no network calls. Any network call would be a bug.

When automatic updates arrive, a Sparkle appcast check over HTTPS will be the only call, and this file
will list it in the same release.

## Permissions baaar may request

- **Accessibility**, required, to list, open and picture menu bar items.
- **Screen Recording**, optional, to picture menu bar items.

When each is asked for, and what happens without it: [PERMISSIONS.md](PERMISSIONS.md).

## Data subject rights (GDPR and CCPA)

We collect no personal data. Rights of access, deletion and portability are satisfied by definition:
everything baaar keeps is in the table above, on your Mac.

## Changes

If this policy ever changes materially, we will:

- Update this file in the public repository.
- Bump the "Last updated" date.
- Mention the change in the next release's [CHANGELOG](../CHANGELOG.md).

## Contact

`hello@laaabs.com`. Security: see [SECURITY.md](../SECURITY.md).
