## Why

<!-- The problem or the decision behind this change. Do not repeat the title. -->

## What changes

<!-- Short list. -->

-

## How to test it

<!-- Concrete steps on macOS 27, or the debug command that drives it. Say which macOS build you verified on. -->

-

## Screenshots

<!-- Required for any change a person can see. Before and after. Delete this section otherwise. -->

## Checklist

- [ ] `scripts/build.sh` passes with no new warnings
- [ ] Verified on macOS 27, with Screen Recording granted and denied if pictures are involved
- [ ] Conventional Commits, in English, lowercase `baaar`
- [ ] No invented design values: everything comes from `design/DESIGN-SYSTEM.md`
- [ ] New UI strings are in `Localizable.xcstrings`, in English and Spanish
- [ ] No em dashes, en dashes, middle dots, emoji or banned words in copy
- [ ] No secrets, no signing material, no generated project, no `git stash`
- [ ] `CHANGELOG.md` updated under `[Unreleased]` if a person can notice the change
- [ ] Docs and `docs/20-decision-log.md` updated if behaviour or a decision changed

### If this touches private API

- [ ] Every new private selector is checked in `VisibilityRestriction.isAvailable`
- [ ] baaar still runs, without hiding, when the selector is missing

### If this touches privacy

- [ ] No new network call, or `docs/PRIVACY.md` lists it
- [ ] `docs/PERMISSIONS.md` updated if a permission, or its use, changed
- [ ] Logs still hold no content typed by the person or read from other windows

## Closes

<!-- Closes #123, or Part of #123 -->
