# Releasing baaar

How a maintainer ships a version of baaar: a Developer ID signed, notarized and stapled `baaar.app`,
packaged as `baaar-v<version>.dmg` and `baaar-v<version>.zip`, published as a GitHub release and
then as a Homebrew cask in [bylaaabs/homebrew-tap](https://github.com/bylaaabs/homebrew-tap).

Two ways produce identical output because they run the same scripts:

- **From your Mac** with `scripts/release/release.sh`. The default while baaar is alpha.
- **From GitHub Actions** by pushing a tag, once the signing secrets are stored in the repository.

Versions follow SemVer with pre-release tags: `0.4.0-alpha.1`, `0.4.0-beta.1`, `0.4.0-rc.1`, `0.4.0`.
Tags carry a `v` (`v0.4.0-alpha.1`); file names carry `v` too (`baaar-v0.4.0-alpha.1.dmg`);
`MARKETING_VERSION` does not (`0.4.0-alpha.1`).

## What you need

| Thing | Where | Why |
|---|---|---|
| macOS 27, Xcode 26 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen) | `brew install xcodegen` | builds baaar |
| A "Developer ID Application" certificate for team `3862GT8D5W` | Keychain Access | signs the bundle and the DMG |
| An App Store Connect API key with the Developer role (`AuthKey_<id>.p8`, key id, issuer id) | [App Store Connect > Users and Access > Integrations](https://appstoreconnect.apple.com/access/integrations/api) | notarizes |
| [GitHub CLI](https://cli.github.com) logged in with push rights | `brew install gh && gh auth login` | creates the release |
| A git signing key | `git config user.signingkey` | tags are signed |

Check the certificate is there and valid:

```sh
security find-identity -v -p codesigning | grep "Developer ID Application"
```

If more than one Developer ID identity is listed, export `DEVELOPER_ID_APPLICATION` with the exact
name in quotes before running the scripts.

### Store the notary credentials once

`notarytool` keeps the API key in the keychain under a profile name. The scripts use the profile
`baaar` unless `NOTARY_PROFILE` says otherwise:

```sh
xcrun notarytool store-credentials baaar \
  --key ~/Downloads/AuthKey_XXXXXXXXXX.p8 \
  --key-id XXXXXXXXXX \
  --issuer 00000000-0000-0000-0000-000000000000
```

Then delete the `.p8` from Downloads or move it to a password manager: Apple lets you download it
once. Never put it in the repository (`.gitignore` already refuses `*.p8`).

## The scripts

All under `scripts/release/`, all `set -euo pipefail`, each usable on its own:

| Script | Does | Writes |
|---|---|---|
| `build-release.sh` | `xcodegen generate`, `xcodebuild archive` in Release with `CODE_SIGN_STYLE=Manual`, hardened runtime and a timestamp, then `codesign --verify --deep --strict` and `spctl` | `dist/baaar.app`, `build/xcodebuild-release.log` |
| `notarize.sh <file>...` | `notarytool submit --wait`, then `stapler staple`. A `.app` is zipped for the upload and stapled in place; a `.dmg` is stapled; a `.zip` is submitted only | tickets on the files |
| `make-dmg.sh [app]` | a 620 x 420 DMG with the background from `Resources/dmg-background.png`, `baaar.app` on the left, an `Applications` alias on the right, signed; and a zip with `ditto -c -k --keepParent` | `dist/baaar-v<version>.dmg`, `dist/baaar-v<version>.zip` |
| `checksum.sh [version]` | SHA-256 of both files and the cask to paste into homebrew-tap | stdout |
| `release.sh <version> [--dry-run]` | all of the above in order, then tag, push the tag and `gh release create` | `dist/release-notes-v<version>.md`, `dist/checksums-v<version>.txt` |

Shared settings live in `lib.sh`:

- `DERIVED_DATA` defaults to `~/Library/Developer/Xcode/DerivedData/baaar-release`. It must stay
  outside `~/Desktop` and outside the repository: files there carry extended attributes that make
  `codesign` reject the bundle. `build-release.sh` refuses such a path.
- `DEVELOPER_ID_APPLICATION` defaults to `Developer ID Application`, which `codesign` resolves when
  the keychain holds exactly one. `-` signs ad-hoc, for a dry run on a Mac without the certificate.
- `DIST` defaults to `dist/`, which belongs in `.gitignore` next to `build/`. Nothing in it is ever
  committed.
- The build number (`CURRENT_PROJECT_VERSION`) is `git rev-list --count HEAD`, so every release has
  a higher one without editing `project.yml`.

The DMG background is generated: `swift scripts/render-dmg-background.swift` rewrites
`Resources/dmg-background.png` (620 x 420 pt at 2x). Re-run it only when the layout or the brand
changes, and commit the result. Its icon coordinates and `make-dmg.sh`'s must agree.

## Releasing from your Mac

1. **Green `main`.** `git switch main && git pull --ff-only`, then `scripts/build.sh` and use the build
   for a while. Do not release a `main` you have not run.
2. **Release commit** on a branch named `chore/release-v0.4.0-alpha.1`:
   - `CHANGELOG.md`: rename `## [Unreleased]` to `## [v0.4.0-alpha.1] - 2026-09-16` and add an empty
     `## [Unreleased]` above it. This section becomes the release notes, word for word.
   - `project.yml`: `MARKETING_VERSION: "0.4.0-alpha.1"`.
   - Pull request, review, squash-merge. `release.sh` refuses to run when `project.yml` and the
     version disagree or when the CHANGELOG section is missing.
3. **Dry run** (optional, no credentials touched):
   ```sh
   git switch main && git pull --ff-only
   scripts/release/release.sh 0.4.0-alpha.1 --dry-run
   ```
   Builds, signs, packages and prints the checksums and the cask. Skips notarization, the tag and the
   GitHub release. Open `dist/baaar-v0.4.0-alpha.1.dmg` and check the window.
4. **Release:**
   ```sh
   scripts/release/release.sh 0.4.0-alpha.1
   ```
   Around 10 minutes, most of it Apple's notary service (twice: the bundle, then the DMG). At the
   end it creates the signed tag `v0.4.0-alpha.1`, pushes it, and publishes the GitHub release with
   the DMG, the zip and the CHANGELOG section, marked pre-release when the version contains `alpha`,
   `beta` or `rc`. Pushing the tag also starts the `Release` workflow; it sees the release already
   exists and leaves it alone.
5. **Homebrew cask**, see below.
6. **Check the download**: on a Mac that never built baaar, download the DMG from the release page,
   open it, drag, launch. Gatekeeper must say nothing.

If a step fails, fix the cause and run `release.sh` again: it rebuilds from scratch. If it failed
after the tag was pushed, do not delete the tag; cut the next pre-release number instead
(`0.4.0-alpha.2`). Tags are immutable.

## Releasing from GitHub Actions

`.github/workflows/release.yml` runs on every pushed `v*` tag, on a `macos-26` runner (GitHub has no
macOS 27 image yet; `macos-26` ships Xcode 26, which builds baaar; the repository variable
`XCODE_APP` pins another Xcode when needed, for example `/Applications/Xcode_27.0.app` on the
`xcode-27` preview image).

Store these once in Settings > Secrets and variables > Actions:

| Secret | Value |
|---|---|
| `DEVELOPER_ID_CERT_P12_BASE64` | the Developer ID Application certificate with its private key, exported from Keychain Access as `.p12`, then `base64 -i cert.p12 \| pbcopy` |
| `DEVELOPER_ID_CERT_PASSWORD` | the password chosen at export |
| `DEVELOPER_ID_APPLICATION` | optional, the exact identity name |
| `APPSTORE_CONNECT_API_KEY_BASE64` | `base64 -i AuthKey_XXXXXXXXXX.p8 \| pbcopy` |
| `APPSTORE_CONNECT_API_KEY_ID` | the 10 character key id |
| `APPSTORE_CONNECT_API_ISSUER_ID` | the issuer UUID |

Then steps 1 and 2 above, and instead of `release.sh`:

```sh
git switch main && git pull --ff-only
git tag -s v0.4.0-alpha.1 -m "baaar 0.4.0-alpha.1"
git push origin v0.4.0-alpha.1
```

The workflow imports the certificate into a temporary keychain, writes the `.p8` to the runner's
temp folder, runs the same four scripts, publishes the release and deletes the keychain and the
key. The checksums and the cask appear in the job summary. Without the certificate the job fails
on purpose; without the API key it publishes a signed but not notarized build and says so in the
notes.

## The Homebrew cask

After the GitHub release is live, in a fresh branch of
[bylaaabs/homebrew-tap](https://github.com/bylaaabs/homebrew-tap):

1. Replace `Casks/baaar.rb` with the block `checksum.sh` printed (also in
   `dist/checksums-v<version>.txt`, and in the CI job summary). It sets `version`, the zip's
   `sha256`, `depends_on macos: :golden_gate` (Homebrew's name for macOS 27) and `auto_updates false`
   until Sparkle exists.
2. `brew style Casks/baaar.rb` and `brew audit --cask --online Casks/baaar.rb`.
3. `brew install --cask ./Casks/baaar.rb` on your Mac, launch baaar, `brew uninstall --cask baaar`.
4. Pull request titled `baaar 0.4.0-alpha.1`, wait for CI, squash-merge.

Users then get it with:

```sh
brew tap bylaaabs/tap
brew install --cask baaar
```

## Not yet

- **Sparkle.** baaar does not update itself and there is no appcast, so the cask says
  `auto_updates false` and the zip is there for Homebrew only. When Sparkle lands, `make-dmg.sh` already produces the zip Sparkle wants;
  what is missing is the EdDSA signature step and the appcast, plus a change to `docs/PRIVACY.md`.
- **Mac App Store.** baaar uses a private framework to hide items; it cannot be sandboxed.
- **A macOS 27 runner.** Move `release.yml` to `macos-27` when GitHub publishes it.
