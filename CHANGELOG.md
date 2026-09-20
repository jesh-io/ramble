# Changelog

All notable changes to Ramble. Releases are cut with the `/release` skill;
binaries are built by GitHub Actions and attached to each release.

## [0.1.1] - 2026-09-19

### New
- Trackpad gesture in the released build: a **3-finger triple tap** starts and
  stops dictation, on out of the box. Settings → Trackpad Gesture changes the
  finger/tap count or turns it off. A fourth tap while cleanup finishes (or a
  single tap within 10 s of a paste) presses Return, as before.

### Changed defaults / config
- `gesture.enabled` now defaults to `true` and `gesture.taps` to `3`
  (`fingers` stays `3`).
- New key `gestureDefaultApplied`. Gesture support was compiled out of the 0.1
  app, so a `gesture` block saved by that build recorded no real choice: on
  first launch 0.1.1 adopts the new default once and sets this marker. A
  gesture setting you changed yourself is left as-is.

### Fixed
- The "↩ tap to send" hint no longer appears in builds without the gesture
  add-on, where no tap could act on it.
- `scripts/build-app.sh` now rebuilds over an existing `dist/`; the read-only
  third-party notice files made a second run fail.

### Install and upgrade
Download `Ramble-macOS.zip`, unzip and move `Ramble.app` to `/Applications`.
Builds are ad-hoc signed, not notarized: right-click → Open, or
`xattr -dr com.apple.quarantine /Applications/Ramble.app`. Updating can
re-prompt Accessibility until Developer ID signing is configured. CLI:
`ramble-cli-macOS.zip`; integrity: `SHA256SUMS.txt`.

### Known limitations
- The gesture add-on reaches the trackpad through Apple's private
  MultitouchSupport framework (OpenMultitouchSupport), so these binaries are
  not eligible for App Store distribution.
- If BetterTouchTool or a similar tool already fires Ramble's hotkey from a
  trackpad gesture, turn one of the two off — otherwise every gesture
  double-toggles dictation.
- macOS ships its own 3-finger tap gestures (Look Up). If yours are enabled,
  pick a different finger count in Settings.

## [0.1] - 2026-09-12

First public Ramble release (application version 0.1.0).

### New
- Full Ramble rename: app, CLI, SDK targets, iPhone project, identifiers and docs.
- Launch at login through macOS Login Items, with approval/error state handling.
- MIT license, contributor/security/privacy documentation and dependency notices.
- Keychain account credentials, private data-file permissions, separate opt-in
  audio/history settings, retention and confirmed deletion controls.
- Independent RambleAnalytics package: typed content-free events, local logging,
  HTTPS JSON transport and persistent batching/retry collector. Analytics is opt-in;
  this release uses local logging only and has no analytics server configured.
- Core/parser and analytics tests, PR build checks, secret scanning, dependency updates.

### Fixed
- Mark incomplete speech providers unavailable; OpenAI/Mistral are batch-only.
- Make remote-processing disclosures accurate and document fresh iPhone project generation.
- Exclude private gesture APIs from default app builds; opt in at build time.
- Include licenses in release archives and derive app version from release metadata.

### Install and upgrade
Download `Ramble-macOS.zip`, unzip and move `Ramble.app` to `/Applications`.
The first release is ad-hoc signed, not notarized. Use macOS Privacy & Security
→ Open Anyway if blocked; updating can re-prompt Accessibility until Developer ID
signing is configured. CLI: `ramble-cli-macOS.zip`; integrity: `SHA256SUMS.txt`.
The new bundle identifiers/data directories require fresh permissions. Previous
installations and data are left untouched; import configuration manually if desired.
Audio recording, transcript history and analytics are disabled for fresh installs.

### Known limitations
ElevenLabs, AssemblyAI and Deepgram are disabled scaffolds. The iPhone app is
WIP and outside the release gate. Model catalog prices are estimates. No analytics backend is connected.

## Development snapshot - 2026-09-07

First release. Fully local voice-to-text for macOS 26 (Apple Silicon).

### Highlights
- Push-to-talk dictation with Apple's on-device speech engine — audio never leaves the machine, text streams as you speak, and the mic starts the instant you trigger it.
- AI cleanup (filler removal, punctuation, paragraphs, bullets) through any local or remote model — Ollama/Qwen by default, Apple Intelligence, OpenAI, Anthropic, Groq and more via accounts.
- A hallucination guard that algorithmically diffs the model's output against what you said and refuses anything invented or restructured.
- Every dictation's audio and transcript are saved before anything can fail; a history panel and `ramble` CLI let you recover, audit, and score any session.

### New
- Menu bar app with quick toggles, a floating status pill (voice meter, elapsed time, optional live text), Skip button during cleanup, and a native Settings window (Usage analytics, General, Cleanup, Accounts, Vocabulary, Storage).
- Triggers: any number of keyboard shortcuts, mouse buttons (middle/side, with modifiers, optional click swallowing), or modifier-key taps — each in toggle or hold-to-talk mode. Optional trackpad gestures (3-finger double tap) via the `RambleGestures` add-on.
- Send flow: tap once within 10 s of a paste to press Return; triple-tap to finish and send; optional auto-Return; configurable Return vs ⌘Return.
- Personal vocabulary with recognizer biasing and deterministic mishearing replacement; learn terms from a corrected dictation ("Fix Last Dictation…", `ramble learn`).
- Incremental cleanup while you're still talking, so only the tail waits at stop.
- Usage ledger (audio seconds, tokens, cost per model) with a 14-day chart and `ramble usage`.
- `ramble` CLI: transcribe audio/video files, `clean`, `history`, `audit`, `guard`, `eval` (score prompts/models against your corrected dictations), `learn`, `vocab`, `models`, `use`.
- iPhone app (`RamblePhone/`) with Action-button intents and on-device cleanup (Apple Intelligence or MLX Qwen).

### Safety & guardrails
- Word-level alignment guard: strips inserted runs longer than 3 words, drops sentences unsupported by the input, and rejects cleanups below 75% similarity (raw transcript is pasted instead). Guard actions are recorded per session and shown in the pill.

### Known issues
- Builds are ad-hoc signed: first launch needs right-click → Open (or `xattr -dr com.apple.quarantine`), and each update re-prompts for Accessibility until Developer ID signing is configured.
- Small local models occasionally restructure short, question-style dictations; the guard falls back to the raw transcript in those cases.

### Install
Download `Ramble-macOS.zip`, unzip, move `Ramble.app` to `/Applications`, right-click → Open. Grant Microphone and Accessibility when prompted. For cleanup: install Ollama and `ollama pull qwen3:4b-instruct`. Optional CLI in `ramble-cli-macOS.zip`; checksums in `SHA256SUMS.txt`.
