# Changelog

All notable changes to Talky. Releases are cut with the `/release` skill;
binaries are built by GitHub Actions and attached to each release.

## [0.1.0] - 2026-09-07

First release. Fully local voice-to-text for macOS 26 (Apple Silicon).

### Highlights
- Push-to-talk dictation with Apple's on-device speech engine — audio never leaves the machine, text streams as you speak, and the mic starts the instant you trigger it.
- AI cleanup (filler removal, punctuation, paragraphs, bullets) through any local or remote model — Ollama/Qwen by default, Apple Intelligence, OpenAI, Anthropic, Groq and more via accounts.
- A hallucination guard that algorithmically diffs the model's output against what you said and refuses anything invented or restructured.
- Every dictation's audio and transcript are saved before anything can fail; a history panel and `talky` CLI let you recover, audit, and score any session.

### New
- Menu bar app with quick toggles, a floating status pill (voice meter, elapsed time, optional live text), Skip button during cleanup, and a native Settings window (Usage analytics, General, Cleanup, Accounts, Vocabulary, Storage).
- Triggers: any number of keyboard shortcuts, mouse buttons (middle/side, with modifiers, optional click swallowing), or modifier-key taps — each in toggle or hold-to-talk mode. Optional trackpad gestures (3-finger double tap) via the `TalkyGestures` add-on.
- Send flow: tap once within 10 s of a paste to press Return; triple-tap to finish and send; optional auto-Return; configurable Return vs ⌘Return.
- Personal vocabulary with recognizer biasing and deterministic mishearing replacement; learn terms from a corrected dictation ("Fix Last Dictation…", `talky learn`).
- Incremental cleanup while you're still talking, so only the tail waits at stop.
- Usage ledger (audio seconds, tokens, cost per model) with a 14-day chart and `talky usage`.
- `talky` CLI: transcribe audio/video files, `clean`, `history`, `audit`, `guard`, `eval` (score prompts/models against your corrected dictations), `learn`, `vocab`, `models`, `use`.
- iPhone app (`TalkyPhone/`) with Action-button intents and on-device cleanup (Apple Intelligence or MLX Qwen).

### Safety & guardrails
- Word-level alignment guard: strips inserted runs longer than 3 words, drops sentences unsupported by the input, and rejects cleanups below 75% similarity (raw transcript is pasted instead). Guard actions are recorded per session and shown in the pill.

### Known issues
- Builds are ad-hoc signed: first launch needs right-click → Open (or `xattr -dr com.apple.quarantine`), and each update re-prompts for Accessibility until Developer ID signing is configured.
- Small local models occasionally restructure short, question-style dictations; the guard falls back to the raw transcript in those cases.

### Install
Download `Talky-macOS.zip`, unzip, move `Talky.app` to `/Applications`, right-click → Open. Grant Microphone and Accessibility when prompted. For cleanup: install Ollama and `ollama pull qwen3:4b-instruct`. Optional CLI in `talky-cli-macOS.zip`; checksums in `SHA256SUMS.txt`.
