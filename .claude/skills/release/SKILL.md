---
name: release
description: Cut a Ramble release — diff since the last tag, propose the semver bump, write real release notes + changelog, then (after confirmation) commit, tag, publish the GitHub release, and watch CI attach the binaries. Use when the user says "release", "cut a release", "ship a version", "tag a version".
---

# /release — cut a Ramble release

You are producing a **user-facing** release for the Ramble macOS app. The
GitHub Actions workflow (`.github/workflows/build.yml`) builds and attaches
binaries when a `v*` tag is pushed; **you own the version, the notes, and
the changelog**. Do the analysis first, present it, and only execute after
the user confirms.

## 1. Preflight

```bash
git status --porcelain          # must be clean
git fetch --tags -q && git rev-parse --abbrev-ref HEAD   # must be main
git describe --tags --abbrev=0  # last release tag, e.g. v0.1.0
```
Stop and tell the user if the tree is dirty or not on `main`.

## 2. Understand what changed (do a real diff, not a log skim)

```bash
LAST=$(git describe --tags --abbrev=0)
git log --reverse --format='%h %s%n%b' "$LAST"..HEAD
git diff --stat "$LAST"..HEAD
git diff "$LAST"..HEAD -- Sources RamblePhone scripts .github   # read the actual changes
```
Read the diff for user-visible behavior: new features, changed defaults,
new config keys (`Sources/RambleCore/Config.swift`), new CLI commands
(`Sources/RambleCLI/main.swift`), Settings UI changes, safety/guard changes,
permissions changes, anything that alters what a user must do. Ignore
refactors unless they change behavior.

## 3. Propose the version (semver)

- **patch** — fixes and tuning only
- **minor** — new user-facing features, new config keys, new CLI commands
- **major** — breaking config changes or removed features (pre-1.0: bump minor and say so)

Say which and why.

## 4. Draft the notes

Write for a person deciding whether to update. Concrete, specific, no
marketing. Structure (omit empty sections):

```
## Highlights
2–4 bullets: the things worth updating for, in plain language.

## New
## Improved
## Fixed
## Safety & guardrails      (hallucination guard / privacy changes go here)
## Changed defaults / config (new keys, new defaults — show the JSON key)
## Known issues
## Install / upgrade notes  (permissions to re-grant, models to pull, migration)
```
Under the install section always include: download `Ramble-macOS.zip`, move
to `/Applications`, first-launch Gatekeeper step (right-click → Open or
`xattr -dr com.apple.quarantine /Applications/Ramble.app`) unless builds are
notarized, and that updating re-prompts Accessibility until Developer ID
signing is configured. Mention `ramble-cli-macOS.zip` and `SHA256SUMS.txt`.

Also prepend the same content (dated, Keep-a-Changelog style) to
`CHANGELOG.md` under `## [X.Y.Z] - YYYY-MM-DD`.

## 5. Present, then wait

Show the user: proposed version, the notes, and the changelog diff. Ask for
confirmation or edits. **Do not tag until they confirm.**

## 6. Execute (after confirmation)

```bash
git add CHANGELOG.md && git commit -m "Release vX.Y.Z"
git tag -a vX.Y.Z -m "Ramble X.Y.Z"
git push origin main && git push origin vX.Y.Z
gh release create vX.Y.Z --title "Ramble X.Y.Z" --notes-file <notes.md>
RUN=$(gh run list --branch vX.Y.Z --limit 1 --json databaseId -q '.[0].databaseId')
gh run watch "$RUN" --exit-status --interval 15
gh release view vX.Y.Z --json url,assets -q '.url, (.assets[] | .name)'
```
Confirm all three assets are attached (`Ramble-macOS.zip`,
`ramble-cli-macOS.zip`, `SHA256SUMS.txt`). If CI fails, fix and re-run
before reporting; do not leave a release without binaries. Report the
release URL.
