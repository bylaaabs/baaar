# 20 - Decision log

## Why we write them down

Six months from now someone will ask "why does baaar use a private framework?" and the honest answer
has to be better than "it worked". A decision that is not written down gets relitigated, usually at the
worst moment.

## What deserves an entry

Write one when a choice is **hard to reverse** or **someone will reasonably question it later**:

- Depending on private API, or dropping that dependency
- Adding or dropping a dependency that is hard to replace
- A change to what baaar can see, capture or send
- A change to identity: names, bundle identifiers, license, repository
- Choosing between two approaches where the loser was defensible

**Not** every technical choice. If reversing it is an afternoon's work, just do it.

## How

Append to the table below and, if it needs more than a row, add a section under it, in the same pull
request as the change it explains. The entries dated 2026-09-15 record decisions made while the
codebase was first built.

## Template

```
### YYYY-MM-DD - Short title

**Context.** What was going on that forced a choice.

**Options.** What was actually on the table, including the one we rejected.

**Decision.** What we chose.

**What decided it.** The single argument that tipped it. Not a list.

**What it costs.** What we knowingly gave up.

**What would reverse it.** The signal that should make us revisit.
```

## Log

| Date | Decision | Where |
|---|---|---|
| 2026-09-15 | Hide through MenuBarAgent's visibility restriction, not dividers or synthetic drags | this file |
| 2026-09-15 | Sections are assigned per bundle, and per system item for Apple's nine | this file |
| 2026-09-15 | Picture items in isolation, a few at a time, without moving the cursor | this file |
| 2026-09-15 | The bundle identifier is `com.laaabs.baaar` | this file |
| 2026-09-15 | The product name is lowercase `baaar` | this file |
| 2026-09-15 | Apache License 2.0 | this file |
| 2026-09-15 | A new `bylaaabs/baaar`, with the old repository archived as `baaar-legacy` | this file |
| 2026-09-16 | The first release is `0.1.0` | this file |

### 2026-09-15 - Hide through MenuBarAgent's visibility restriction

**Context.** macOS 27 draws the whole menu bar into a single WindowServer window, owned by MenuBarAgent.
Every manager built on per-item windows broke. The first baaar builds for macOS 27 used a divider status
item that grew until macOS overflowed everything to its left, and moved items with synthetic ⌘-drags.
The divider width had to be searched per screen, drifted with every change to the bar, and a single
point too wide overflowed the divider itself. Drags moved the cursor and failed silently.

**Options.** Keep tuning the divider and the drags. Hide nothing and only offer a bar of shortcuts. Or
use the allow-list assertion MenuBarAgent already has for assessment mode, `MBAssessmentModeAssertion`,
exposed by the private `MenuBarClientCore` framework.

**Decision.** The visibility restriction. baaar allows every running bundle except the hidden ones, and
the system items that stay visible, and MenuBarAgent removes the rest from the bar.

**What decided it.** It is MenuBarAgent doing the layout, so hidden items free their space exactly, on
every screen, with no geometry to guess and nothing touching the cursor. And the assertion dies with
baaar's connection: a crash cannot leave items lost.

**What it costs.** A private API that Apple can change or remove in any update, which rules out
distribution through Apple's store. Bundles hide whole. Apple's modules beyond the nine system items disappear while any
restriction is active, and Notification Center will not open from the clock under one. `dlopen` of a
system framework is an exception to the laaabs. rule against runtime code loading.

**What would reverse it.** Apple removing the assertion or its selectors, which
`VisibilityRestriction.isAvailable` detects, or Apple shipping a public API for hiding menu bar items.

### 2026-09-15 - Sections per bundle

**Context.** The divider builds stored a section per item. The restriction allows bundle identifiers,
plus Apple's system items one by one, and nothing finer.

**Options.** Keep per-item sections and pretend some of them work. Or make the section model match what
MenuBarAgent can do.

**Decision.** A section per bundle, and per `SystemItem` for battery, Bluetooth, clock, displays,
keyboard brightness, sound, Wi-Fi, screen mirroring and Control Center. Sections stored per item migrate
to their bundle once.

**What decided it.** A setting that silently does nothing is worse than a coarser one that always
works.

**What it costs.** A bundle with several items cannot keep one visible and hide another.

**What would reverse it.** MenuBarAgent accepting per-item identifiers.

### 2026-09-15 - Picture items in isolation

**Context.** Hidden items are not drawn, so the bar needs pictures taken while they were visible. On
macOS 27 AX frames go stale after the bar reflows, including baaar's own items, so a capture cropped to
a stale frame shows the wrong item. The divider builds pictured items where they stood and expanded
macOS's own overflow chevron for the ones behind it.

**Options.** Capture in place and trust the frames. Or show a few items at a time, alone in the bar,
and capture them there.

**Decision.** Batches narrow enough to fit next to the notch, each shown alone: every other item hidden
through the restriction, baaar's own items blanked, frames settled across two scans before the capture,
and captures that come out empty or overlapping rejected.

**What decided it.** Alone in the bar, a stale frame can only land on empty space or on another item of
the same batch, and both are detectable. In place, a wrong picture looks right.

**What it costs.** Picturing takes a few seconds and visibly empties the menu bar while it runs. It
cannot run while the menu bar is off screen.

**What would reverse it.** macOS keeping AX frames current after a reflow.

### 2026-09-15 - The bundle identifier is `com.laaabs.baaar`

**Context.** Development builds used `com.aaangelmartin.baaar`, and the legacy baaar used
`com.aaangelmartin.Baaar`. Newer laaabs. products (`haaarness`) use the `com.laaabs` prefix.

**Options.** Keep the personal prefix, or move to `com.laaabs` before the first release.

**Decision.** `com.laaabs.baaar`, with `bundleIdPrefix: com.laaabs`, signed by team `3862GT8D5W`.

**What decided it.** The bundle identifier cannot change after release without losing every person's
settings and privacy grants, and nobody has installed this codebase yet.

**What it costs.** Development builds lose their Accessibility and Screen Recording grants and their
cached pictures. Settings are copied from the `com.aaangelmartin.baaar` defaults domain once, at launch.

**What would reverse it.** Nothing after the first release.

### 2026-09-15 - The product name is lowercase `baaar`

**Context.** The laaabs. handbook's naming page still writes products with a capital first letter
(`Baaar`). The newest products, `haaarness` and `terminaaal`, are lowercase everywhere.

**Options.** Follow the handbook as written, or follow the newest products.

**Decision.** Lowercase `baaar` everywhere: prose, UI, identifiers, targets, bundle identifiers, the
built `baaar.app`. Swift types keep Swift casing.

**What decided it.** The newest conventions win, and one spelling across the studio's current products
reads as a system.

**What it costs.** The handbook disagrees until it is updated.

**What would reverse it.** A studio-wide decision recorded in the handbook.

### 2026-09-15 - Apache License 2.0

**Context.** baaar is public, and the legacy baaar and `speaaak` are Apache 2.0.

**Decision.** Apache License 2.0, copyright laaabs., no CLA.

**What decided it.** Its explicit patent grant, and consistency with the other open laaabs. tools.

**What it costs.** Anyone can ship a closed fork.

**What would reverse it.** Nothing expected.

### 2026-09-15 - A new repository, the old one archived

**Context.** The legacy `bylaaabs/baaar` targeted macOS 15 and 26 with a different architecture (spacer
panels, profiles, conditional rules) that macOS 27 broke. Its history, issues and releases describe a
product that no longer exists.

**Options.** Rewrite inside the old repository, or start clean.

**Decision.** The old repository is renamed `baaar-legacy` and archived. `bylaaabs/baaar` is recreated
from scratch for this codebase.

**What decided it.** Issues and releases for features that cannot return would mislead everyone who
lands on the repository.

**What it costs.** Stars, watchers and links to old issues stay with the legacy repository. The
Homebrew cask points at release assets of the old name and has to move with the first release.

**What would reverse it.** Nothing.

### 2026-09-16 - The first release is `0.1.0`

**Context.** The legacy baaar cask stopped at `0.3.0-alpha.5`, and the cask keeps the same token.

**Decision.** Start a new version line at `0.1.0`: this is a new codebase for macOS 27, not a continuation.

**What decided it.** The legacy alpha had no known users outside the studio, and a clean version line
reads honestly for a rewrite.

**What it costs.** Homebrew compares versions, so anyone with the legacy cask installed has to reinstall
the cask instead of upgrading.

**What would reverse it.** Nothing.
