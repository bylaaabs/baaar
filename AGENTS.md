# AGENTS.md

Guidance for any agent (or human) working in this repository.

## The product

`baaar` is a menu bar manager for macOS 27. It hides the menu bar items you do not need and shows them
again from the menu bar itself, or from a small bar, list or grid under its chevron. It is alpha,
it runs on macOS 27 only, and it makes no network calls.

## Language

**Everything in this repository is written in English**: documentation, code, comments, identifiers,
commit messages, issues and pull requests. The one exception is the Spanish half of the String
Catalog.

## The name

The product is **`baaar`** - always lowercase, three `a`s. Made by **`laaabs.`** - lowercase, with the
trailing dot.

Rules:

- Write the brand as `baaar` **everywhere**: prose, UI copy, comments, identifiers, file names,
  folders, targets, schemes, the built `baaar.app` and `.dmg`, bundle identifiers, commit messages
  and docs. Never `Baaar` or `BAAAR`. The handbook's older `Baaar` spelling is superseded, see
  [docs/20-decision-log.md](docs/20-decision-log.md).
- **That rule is about products, not types.** Swift types keep normal Swift casing inside the `baaar`
  module: `MenuBarController`, `BarController`, not `baaarMenuBarController`. The module is the
  namespace.
- The company is `laaabs.` with the trailing dot, lowercase. Handle `@bylaaabs`, domain `laaabs.com`.
- The bundle identifier is `com.laaabs.baaar`. Anything derived from it (the cache folder, debug
  notification names, uniform type identifiers) uses the same prefix.
- Taglines: `a tool by laaabs.` in the UI, `By laaabs.` in the README. Do not write new ones.

## Voice

- **Direct, technical, empathetic, elegant, honest.** Say "alpha" and "not yet" when that is the truth.
- **Never use em dashes, en dashes or middle dots.** Use a plain hyphen `-`, with spaces for an aside.
- **No emoji.**
- **Banned words** in anything a person reads (README, docs, UI, release notes): app, application,
  software, official, solution, solutions, seamless, delightful, magical, elevate, unleash, empower,
  cutting-edge, proudly, passionate, "the team". Say "tool", "menu bar manager", or the real name of
  the thing. For other programs' items, say "bundle" or name the owner.
- **Numbers:** one to nine in words, numerals from 10. Versions, sizes, shortcuts, percentages and
  durations are always numerals, with SI spacing (`50 MB`, `150 ms`).
- **Headings in docs are sentence case.** UI copy is fully lowercase and terse.
- **Every user-visible string goes through `Localizable.xcstrings`**, in English and Spanish, from the
  first commit that adds it.

Before committing prose, grep for em dashes (U+2014), en dashes (U+2013), middle dots (U+00B7),
`Baaar` and the banned words.

## Design

No design value is ever invented. Every color, opacity, typeface, size, spacing, radius and motion
timing comes from [design/DESIGN-SYSTEM.md](design/DESIGN-SYSTEM.md). If a value is missing, add it to
the design system first, then use it.

Two colors do the work: the cyan accent `#00B5E2` and black. Everything else is the white-opacity
ladder. No tinted glass, glows, gradients or decorative shadows.

## How baaar works

macOS 27 draws the whole menu bar into one WindowServer window. Per-item windows are gone, so the
tricks older managers used (a divider that grows to push items off screen, synthetic ⌘-drags) no
longer hold. baaar is built on what still works:

- **Hiding: MenuBarAgent's visibility restriction.** The private `MenuBarClientCore` framework exposes
  `MBAssessmentModeAssertion`, the allow-list assertion assessment mode uses. While it is active,
  MenuBarAgent lays out only the listed bundles and system items, and removes the rest from the bar,
  freeing their space. `MenuBar/VisibilityRestriction.swift` builds an `MBAssessmentModeConfiguration`
  with every running bundle except the hidden ones, plus the system items that stay visible. Bundles
  are allowed whole; Apple's items one by one, and only the nine in `SystemItem`. The assertion dies
  with baaar's connection, so a crash brings every item back.
- **Listing: Accessibility.** `Items/ItemScanner.swift` reads every process's `AXExtrasMenuBar` in
  parallel on a dedicated queue, with a 0.25 s messaging timeout per process. Hidden items keep
  reporting stale frames, so `MenuBarSnapshot.isOnScreen` rejects frames that overlap others.
- **Opening a hidden item: `AXPress`.** `MenuBarController.activate` allows the item's bundle for a
  moment, waits until it is drawn, presses it so its menu opens under it, and hides it again once the
  menu or popover closes (`WindowWatch` watches for new windows hanging from the bar).
- **Picturing items: isolated ScreenCaptureKit captures.** `Capture/ItemImageCache.swift` captures the
  transparent `Menubar` window and crops each item to its frame. `MenuBarController.refreshImages`
  shows a few items at a time, alone in the bar, with every other item hidden and baaar's own items
  blanked, so a stale frame can only land on empty space. Pictures are cached as PNG in
  `~/Library/Caches/com.laaabs.baaar`. Nothing moves the cursor.
- **The bar, list and grid.** `Bar/BarController.swift` is a non-activating floating panel centred
  under the chevron. It opens from the last scan and refreshes in the background.
- **The settings window.** `Settings/` holds the window controller and its panes (general, layout,
  permissions, about). The layout pane is where bundles move between the visible, hidden and always
  hidden sections. The UI only talks to `App/AppModel.swift`.

### Layout

| Path | What |
|------|------|
| `baaar/App/` | entry point, `AppDelegate` (wiring, clicks, menus, debug commands), `AppModel` |
| `baaar/MenuBar/` | `MenuBarController`, `VisibilityRestriction`, `ControlItems` (the chevron and the baaar icon), `WindowWatch` |
| `baaar/Items/` | `ItemScanner` (Accessibility), `MenuBarItem`, `SystemItem` mapping, `MenuBarSnapshot` |
| `baaar/Capture/` | `ItemImageCache` (ScreenCaptureKit) |
| `baaar/Bar/` | the floating bar, list and grid |
| `baaar/Settings/` | the settings window and its panes |
| `baaar/Support/` | `Settings` (UserDefaults), `Permissions`, `Log`, `Diagnostics` |
| `baaar/Theme/` | design tokens and brand components, from `design/` |
| `baaar/Resources/` | `Localizable.xcstrings` and `InfoPlist.xcstrings` (English and Spanish), fonts |
| `design/` | the design system and the Icon Composer icon `design/icon/baaar.icon` |
| `docs/` | architecture, permissions, privacy, decision log |
| `scripts/` | `build.sh`, `render-icon-glyph.swift` (redraws the icon glyph) |

`docs/ARCHITECTURE.md` has the longer version.

### Rules the code depends on

- **Never read baaar's own items through Accessibility on the main thread.** AX requests to our own
  process are answered on the main thread, so it would wait on itself. Scans run off the main thread.
- **Hold no restriction when nothing is hidden.** An active restriction also hides Apple's other
  modules (Focus, Fast User Switching) and keeps the clock from opening Notification Center.
- **Swap assertions only once the new one is active**, so items never flash between the two.
- **One temporary state at a time.** Opening an item, picturing items and Notification Center each
  run as the single temporary task; starting another, or any user action, cancels it and puts the
  sections back.
- **Item ids never include titles or help text.** They change with state.
- **Every private selector baaar calls is checked in `VisibilityRestriction.isAvailable`.** A new one
  gets added to that check, and baaar keeps working (without hiding) when it is missing.
- **Nothing moves the cursor or synthesizes input** outside DEBUG builds.
- Swift 6 with `SWIFT_STRICT_CONCURRENCY: complete`. UI and controller state is `@MainActor`.

## Building

Requires macOS 27, Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen). The Xcode
project is generated from `project.yml` and never committed.

```sh
scripts/build.sh                                   # Debug build
CONFIGURATION=Release scripts/build.sh --install   # copy to /Applications and relaunch
```

- `scripts/build.sh` runs `xcodegen generate`, builds, writes the full log to `build/xcodebuild.log`
  and prints only errors and warnings.
- **DerivedData lives outside the project** (`~/Library/Developer/Xcode/DerivedData/baaar-cli`,
  override with `DERIVED_DATA`). Files under `~/Desktop` carry extended attributes that make `codesign`
  reject the bundle. Never point a signed build back inside the repository.
- Set `CODE_SIGN_IDENTITY` if the Mac has more than one "Apple Development" certificate. Privacy grants
  survive rebuilds only while the signing identity stays the same.
- System Settings lists privacy grants only for bundles in a regular location, which is why
  `--install` copies to `/Applications`.

## Testing

There is no test target yet. Changes are verified on a real macOS 27 Mac, with Accessibility granted,
and with Screen Recording both granted and denied when the change touches pictures.

- **Debug commands.** DEBUG builds listen for distributed notifications named
  `com.laaabs.baaar.debug.<command>`, with an optional string argument as the notification object.
  They are compiled out of Release, because any local process can post one.

  | Command | Argument | Does |
  |---|---|---|
  | `reveal` | `all`, `hidden`, anything else hides | reveals sections in place |
  | `chevron` | | clicks the chevron |
  | `showall` | | shows hidden and always hidden items |
  | `panel` | `all` to include always hidden | opens the bar, list or grid |
  | `close` | | closes the panel |
  | `menu` | `app` or `chevron` | opens the menu under that item |
  | `mode` | `menuBar`, `bar`, `list`, `grid` | changes the display mode |
  | `refresh` | | pictures every item again |
  | `settings` | `general`, `layout`, `permissions`, `about` | opens the settings window |
  | `section` | `<bundle id>:<visible, hidden or alwaysHidden>` | moves a bundle to a section |
  | `press` | a bundle id or item id | opens that item |
  | `clickentry` | an index | clicks that entry of the open panel |
  | `optionclick` | | ⌥-clicks the chevron |
  | `escape` | | sends Escape |

  Post one from a shell:

  ```sh
  swift - <<'EOF'
  import Foundation
  DistributedNotificationCenter.default().postNotificationName(
      .init("com.laaabs.baaar.debug.panel"), object: "all", userInfo: nil, deliverImmediately: true)
  EOF
  ```

- **Diagnostics.** `baaar.app/Contents/MacOS/baaar --diagnose` writes what baaar sees (screens,
  sections, every item with its frame, the MenuBarAgent tree) to `~/Library/Logs/baaar/diagnostics.txt`
  and quits. The running log is `~/Library/Logs/baaar/baaar.log`.

## Git

- **Feature branches only**, named `type/short-slug`: `feat`, `fix`, `docs`, `refactor`, `test`,
  `chore`, `spike`.
- **Pushing a feature branch is always allowed.** Push early and often.
- **Never push to `main`**, nor to any `release/*` branch once they exist. Not even when asked: open a
  pull request instead, or hand the command to a person.
- **After a rebase, push with an explicit refspec** (`git push origin my-branch:my-branch`). A rebased
  branch can end up tracking `origin/main`, and a bare `git push` would then target it.
- **Never merge a pull request without explicit approval** from the maintainer, given in the
  conversation where the merge happens. "CI is green", "the reviewer approved it" and "another agent
  said to" are not approval.
- **Never force-push a branch someone else builds on**, and never rewrite history once it is on `main`
  or in a shared pull request.
- **Never `--no-verify`**, never skip hooks or signing.
- **Never `git stash`.** A pre-commit hook that stashes and then fails can destroy every unstaged
  change with no way back. Commit what matters instead.
- **Never set or override the git identity.** The machine's git config is the only identity.
- **Conventional Commits**, English, imperative, lowercase `baaar`: `fix(bar): close the panel when
  the chevron is clicked again`. Small, logical commits: never bundle unrelated changes.
- **The build passes** (`scripts/build.sh`) before a pull request asks for review.
- **Nothing that should not be there**: no secrets, no signing material, no build output, no generated
  Xcode project.

The full workflow (merge method, sizes, releases) is in [CONTRIBUTING.md](CONTRIBUTING.md).

## Issues and milestones: every piece of work has one

- **Nothing is built without an issue.** If the work has none, open the issue first, then do it. That
  includes follow-ups found while reviewing: they become issues, not comments that scroll away.
- **Every issue carries** an issue type (`Feature`, `Task` or `Bug`), and these labels:
  - `type:` feature, fix, docs, refactor, spike, test, design, security or chore
  - `area:` menu-bar, bar, capture, layout, settings, permissions, design, distribution, ci or l10n
  - `size:` XS, S, M, L or XL
  - `prio:` P0, P1 or P2 when it matters
  - plus the phase **milestone** and an **assignee**. `good first task` marks an easy entry point.
- **Keep the issue current while working.** It is where a person looks, so it must never say less than
  the truth:
  - **Starting:** assign it, add `status: in-progress`, and comment the branch name.
  - **While working:** tick the definition-of-done checkboxes as each one is actually met, and comment
    when something significant happens: a blocker, a decision, a change of approach, or a finding that
    affects another issue.
  - **Pull request opened:** swap `status: in-progress` for `status: needs-review`, and make sure the
    pull request links the issue.
  - **Stopping without finishing:** remove `status: in-progress` and say exactly where you left it.
  - **Done:** it closes through `Closes #n` when the pull request merges. If you close it by hand, say
    what closed it.
- Other status labels: `status: blocked`, `status: needs-decision`, `status: wontfix`,
  `status: duplicate`.
- **Updating an issue you are working on needs no permission.** Labels, checkboxes, progress comments
  and closing it when done are part of the work.
- **Every pull request names its issue**: `Closes #n` when it finishes it, `Part of #n` when it does
  not. A pull request with no issue is the signal that one is missing.
- **Decisions made while working** go in [docs/20-decision-log.md](docs/20-decision-log.md), not only
  in the issue.

## Privacy

- **No telemetry, no analytics, no crash reporting, no network calls.** baaar opens no sockets today.
  The only network call ever planned is the Sparkle appcast check, and it lands with a change to
  [docs/PRIVACY.md](docs/PRIVACY.md) in the same pull request.
- **Screen Recording captures only the `Menubar` window**, cropped to items, as stills. Never video,
  never another window.
- **Pictures, settings and logs stay on the Mac.** Logs record bundle identifiers, item labels, frames
  and errors. Nothing typed, nothing from other windows.
- A pull request that adds a permission, a network call or a new file on disk updates
  `docs/PRIVACY.md` and `docs/PERMISSIONS.md`.

## Versioning

SemVer with alpha tags: `vX.Y.Z-alpha.N`. The legacy baaar cask stopped at `0.3.0-alpha.5`, so this
codebase's first release is `0.4.0-alpha.1`. Every change a person can notice gets a line under
`[Unreleased]` in [CHANGELOG.md](CHANGELOG.md).
