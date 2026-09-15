# Security

## Reporting a vulnerability

Email **security@laaabs.com** with what you found and how to reproduce it, or open a private advisory at
[github.com/bylaaabs/baaar/security/advisories/new](https://github.com/bylaaabs/baaar/security/advisories/new).

- We confirm receipt within **72 hours**
- We tell you what we plan to do, and when, within **7 days**
- We take no legal action against anyone researching in good faith who does not access other
  people's data

Include the baaar version and build, the macOS 27 build, and the steps. A
`~/Library/Logs/baaar/diagnostics.txt` from `baaar --diagnose` helps; read it first, since it lists
the names of your menu bar items.

**Do not open a public issue for a security problem.**

## Scope

In scope: baaar itself, its build script, and anything it writes to disk.

Out of scope: vulnerabilities in macOS, MenuBarAgent or other programs' menu bar items. Report those to
their vendors.

## Supported versions

baaar is alpha. Only the latest release gets fixes.

## The security model, briefly

baaar runs as a menu bar agent under the user's account. It is not sandboxed, because Accessibility
and the private framework below do not work from the sandbox. Hardened Runtime is on.

- **Accessibility (required).** It lets baaar read and press any process's menu bar items, which is a
  powerful grant. baaar reads only `AXExtrasMenuBar` trees, and presses an item only when the person
  clicks it in the bar, list or grid. It never reads window contents, text fields or keystrokes.
- **Screen Recording (optional).** It lets baaar capture the screen. baaar captures only the window
  macOS titles `Menubar`, as a still, cropped to each item's frame. It never records video and never
  captures another window.
- **Mouse clicks.** baaar watches the location of clicks system-wide to hide items again after a click
  elsewhere, to dismiss the bar, and to notice clicks on the clock. It does not watch the keyboard.
- **Private API.** Hiding goes through `MBAssessmentModeAssertion` in
  `/System/Library/PrivateFrameworks/MenuBarClientCore.framework`, loaded with `dlopen` from that
  system path only, never from a user path. Every selector is checked before it is called. The
  assertion only allows or withholds menu bar items, and it dies with baaar's connection to
  MenuBarAgent, so quitting or crashing baaar brings every item back. This is the one exception to
  the laaabs. rule against runtime code loading, and it is recorded in
  [docs/20-decision-log.md](docs/20-decision-log.md).
- **Local image cache.** Pictures of menu bar items are stored as PNG in
  `~/Library/Caches/com.laaabs.baaar`. They show whatever an item displayed when it was pictured
  (a timer, a battery level, a network name), and any process running as the same user can read them.
  Deleting that folder removes them; baaar pictures items again when needed.
- **Logs.** `~/Library/Logs/baaar` holds bundle identifiers, item labels, frames and errors.
- **Debug commands** (distributed notifications that drive baaar and synthesize clicks) exist only in
  DEBUG builds. Any local process can post a distributed notification, so they are compiled out of
  Release.
- **No network.** baaar opens no sockets, sends no telemetry and checks for no updates today. See
  [docs/PRIVACY.md](docs/PRIVACY.md).

## Hardening we follow

- No secrets or signing material in the repository. `.gitignore` covers `*.p12`, provisioning
  profiles, certificates and API keys.
- No third-party dependencies today. Any added later is license-checked and version-pinned.
- Logging never includes content typed by the person or read from other windows.
