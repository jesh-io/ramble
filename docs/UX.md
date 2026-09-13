# Ramble UX — user stories & interface decisions (macOS)

Principle: **the menu bar is the interface.** The pill is a status glyph,
not a reading surface. Nothing steals focus; nothing makes you wait.

## Stories

**1. Dictate into any app (the 95% case)**
Hotkey/BTT → tiny pill appears (dot + elapsed time) → speak → hotkey →
cleaned text pastes. The pill exists to answer exactly two questions:
"is it hearing me?" and "how long have I been talking?" Live text is OFF
by default (`output.captions: "minimal"`); set `"full"` to stream words,
`"off"` for menu-bar-icon-only.

**2. Never wait on the cleaner**
The instant recording stops, the raw transcript exists. While the LLM
runs, the pill shows "Cleaning…" with a **Skip** button — click it (or
menu → "Paste Raw Now") and the raw transcript pastes immediately; the
model call is cancelled. Cleanup is a bonus, never a gate.

**3. Glance at state**
Menu bar icon: mic = idle, red mic = recording, orange waveform =
cleaning. Always current, no pill required.

**4. Quick settings without a settings app**
Click the icon: toggles live at the top (Clean Up with AI, Live
Captions), Cleanup Model picker, then History / Transcribe File /
Recordings. One click to anything you change often; config file for
everything else.

**5. Recover anything (trust)**
History… shows recent sessions with raw + cleaned + audio. Every session
is on disk before anything can fail.

**6. Transcribe a file / let the CLI rip**
Everything the app does is scriptable: `ramble <file>`, `ramble clean`,
`ramble toggle`, `ramble history`. Claude/scripts drive it headlessly.

**7. Teach it your words (three doors)**
Menu → "Add to Vocabulary…" (`Term = misheard1, misheard2`); menu →
"Fix Last Dictation…" (edit the text — a local model diffs your edits,
learns the terms, copies the corrected text, and saves your version as an
eval golden label); or `ramble learn "…"` for scripts.

**8. Every correction makes it better**
Sessions keep audio + raw + cleaned + your revision. `ramble eval
[provider]` re-runs cleanup over all corrected sessions and reports WER
against your versions — A/B any prompt or model change against your own
history before adopting it.

**9. Know what it costs**
`usage.jsonl` logs STT seconds and cleanup tokens per model from day one.
`ramble usage` shows per-day/per-model usage with costs (set
`inputCostPerMTok`/`outputCostPerMTok` on remote providers) and a 30-day
projection.

## Later phases

- **Diarization** (FluidAudio, on-device): file/URL workflow — drop a
  meeting recording → segmented transcript → name speakers → copy/save to
  logbook. Streaming mode for live calls. Ships as a menu toggle +
  "Transcribe Meeting…" flow only when the backend is real.
- Diff-based cleanup: rejected for now — 4B models can't produce
  reliable edits-as-diffs; rewrite + validator + skip is the better
  trade.
- **Usage dashboard & guardrails**: viewer UI over usage.jsonl (per-day
  charts, projections), API key management for remote providers
  (AssemblyAI etc.), spend limits with auto-fallback to a local model on
  breach. Remote STT providers slot in via the `Transcriber` protocol
  (per-second billing already supported by the ledger).
