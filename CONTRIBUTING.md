# How we work

baaar is an open source menu bar manager by [laaabs.](https://laaabs.com). Code, docs, translations and
bug reports are welcome. The rules below apply to everyone, agents included; [AGENTS.md](AGENTS.md)
has the naming, voice and architecture detail.

## Language

English, everywhere. Code, comments, docs, commits, issues, pull requests. Spanish only inside the
String Catalog.

## Before you start

- **Open or find an issue first.** Anything beyond a typo starts as a conversation, not as a pull
  request.
- Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and the "Rules the code depends on" section of
  [AGENTS.md](AGENTS.md).
- Read and agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

### Claiming an issue

1. **Assign the issue to yourself**
2. **Add `status: in-progress`**
3. **Comment one line**: the branch name and what you are doing

When you stop without finishing, **remove `status: in-progress` and say where you left it**. A stalled
issue that still looks active is worse than one that looks untouched, because nobody else will pick it
up.

## Getting it running

Requirements: macOS 27, Xcode 26 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
git clone https://github.com/bylaaabs/baaar.git
cd baaar
scripts/build.sh                                   # Debug build
CONFIGURATION=Release scripts/build.sh --install   # copy to /Applications and relaunch
```

Build signed products outside `~/Desktop`: extended attributes there make `codesign` reject the bundle.
`scripts/build.sh` already keeps DerivedData in `~/Library/Developer/Xcode/DerivedData/baaar-cli`.

There is no test target yet. Verify on a real macOS 27 Mac; the DEBUG-only notification commands in
[AGENTS.md](AGENTS.md#testing) drive baaar from a script.

## Branches

**One trunk: `main`.** Branch off it, open a pull request, merge, delete the branch. There is no
`develop`.

Working branches are `type/short-slug`. Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`,
`spike`.

**Never commit or push directly to `main`.** Never force push to it. See
[.github/BRANCH-PROTECTION.md](.github/BRANCH-PROTECTION.md) for what GitHub enforces.

Keep branches short: merged within a day or two. A branch that lives a week is a merge conflict growing
quietly.

### Release branches, later

When people run released versions, cut `release/0.4` from `main` at the moment it ships, and maintain
it only while that version is supported. Fixes land on `main` first and get cherry-picked back. Not
before then.

## Commits

Conventional Commits, English, imperative, lowercase `baaar`:

```
feat(bar): open the grid from the last scan
fix(capture): skip items drawn behind the notch
docs(permissions): explain why Accessibility is asked at launch
```

Small, logical commits. Never bundle unrelated changes. Never `git stash`, never `--no-verify`.

## Pull requests

A pull request explains **why**, not only what. Use the template. The build passes before review is
requested, and the pull request says which macOS 27 build it was verified on.

- Update [CHANGELOG.md](CHANGELOG.md) under `[Unreleased]` for anything a person can notice.
- A change a person can see comes with before and after screenshots.
- New network calls, permissions or files on disk update [docs/PRIVACY.md](docs/PRIVACY.md) and
  [docs/PERMISSIONS.md](docs/PERMISSIONS.md) in the same pull request.

**Nothing merges without the maintainer's explicit approval.** A green CI is not approval.

### Squash or merge commit

**Squash by default.** One pull request becomes one commit on `main`, the commit message is the pull
request title, and `git log` reads like a changelog.

**Merge commit when the branch tells a story that flattening would destroy**, such as a feature built
in steps you want to revert as a unit. If you are unsure, squash. Rebase merge is not used.

## Issues

Every issue carries an issue type (`Feature`, `Task`, `Bug`) and three labels:

- **type**: `type: feature`, `type: fix`, `type: docs`, `type: refactor`, `type: spike`, `type: test`,
  `type: design`, `type: security`, `type: chore`
- **area**: `area: menu-bar`, `area: bar`, `area: capture`, `area: layout`, `area: settings`,
  `area: permissions`, `area: design`, `area: distribution`, `area: ci`, `area: l10n`
- **size**: `size: XS` through `size: XL`

`prio: P0` to `prio: P2` when priority matters. The roadmap phase is the **milestone**. Anything that
needs a call before work can continue gets `status: needs-decision`.

## Sizes

| Label | An issue means | A pull request means |
|---|---|---|
| `size: XS` | under an hour | 0-9 effective lines |
| `size: S` | half a morning | 10-49 |
| `size: M` | one or two days | 50-199 |
| `size: L` | about a week | 200-599 |
| `size: XL` | too big, split it | 600 or more |

On **issues** the size is an estimate you set by hand. On **pull requests** it is applied automatically
by `.github/workflows/pr-size.yml`, counting added plus deleted lines.

**Tests, generated projects, asset catalogs and design files do not count.** A pull request is not
large because it came with the tests it should have had.

## What we care about

- **Privacy.** No telemetry, no analytics, no network calls. The Sparkle appcast is the only one ever
  planned.
- **Native.** Swift 6, AppKit and SwiftUI. No web views, no Electron.
- **Honest about private API.** baaar depends on MenuBarAgent's private visibility restriction. Every
  private selector is checked before it is called, and baaar keeps running without hiding when one is
  missing.
- **The design system.** No invented colors, sizes or radii: everything comes from
  [design/DESIGN-SYSTEM.md](design/DESIGN-SYSTEM.md).
- **Both languages.** Every user-visible string ships in English and Spanish.
- **License compatibility.** Dependencies must be Apache 2.0 compatible (MIT, BSD, Apache, MPL 2.0).
  GPL and AGPL are not.

## Recording decisions

Decisions that are hard to reverse go in [docs/20-decision-log.md](docs/20-decision-log.md), with the
template there.

## Releasing

Only the maintainer cuts releases, tagged `vX.Y.Z-alpha.N`. The first one is `0.4.0-alpha.1`. If your
change needs to ship in the next version, say so in the pull request.

## License

By contributing, you agree that your contributions are licensed under the
[Apache License 2.0](LICENSE), like the rest of baaar. There is no CLA.
