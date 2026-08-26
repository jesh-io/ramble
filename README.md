# Talky

Fully local voice-to-text for macOS, Wispr Flow-style. Push-to-talk dictation
with live on-screen captions, LLM cleanup (filler-word removal, punctuation,
formatting), and audio/video file transcription. Built as a modular Swift
package: a core SDK plus a lightweight menu bar app and CLI on top.

- **Speech-to-text**: Apple's on-device `SpeechAnalyzer` (macOS 26+). No audio
  ever leaves the machine. True streaming — you see text as you speak.
- **Cleanup**: any OpenAI-compatible endpoint, local or remote — Ollama,
  LM Studio, vLLM, OpenAI, Groq, OpenRouter, … Switch models from the menu bar
  or `talky use <id>` to trial what works best.
- **Diarization-ready**: the transcript model carries optional speaker labels
  and the `Transcriber` protocol declares a `.diarization` capability, so a
  speaker-aware engine (e.g. [FluidAudio](https://github.com/FluidInference/FluidAudio))
  can slot in without API changes.

## Requirements

- macOS 26+ (uses the new on-device SpeechAnalyzer API)
- Xcode 26 toolchain to build
- [Ollama](https://ollama.com) (or any OpenAI-compatible server) for cleanup —
  optional; dictation works without it (raw transcript)

## Build & install

```bash
./scripts/build-app.sh
cp -R dist/Talky.app /Applications/
sudo ln -sf "$PWD/dist/talky" /usr/local/bin/talky
open /Applications/Talky.app
```

First run: grant **Microphone** when prompted, and **Accessibility**
(System Settings → Privacy & Security → Accessibility → Talky) so Talky can
paste results into the frontmost app. Without Accessibility it still works —
results land on the clipboard.

Cleanup model (default `gemma3:1b` via Ollama):

```bash
ollama pull gemma3:1b     # and/or gemma3:4b — better quality, still fast
```

## Use

1. Press the hotkey (default **⌃⌥⌘D**) — the menu bar mic turns red and a
   floating caption panel appears at the bottom of the screen.
2. Speak. Text streams into the panel as you talk (dimmed = still revising).
3. Press the hotkey again — the transcript is cleaned by the active LLM and
   pasted into whatever app has focus.

### BetterTouchTools (3-finger double-tap)

Either have your BTT gesture send the keyboard shortcut `⌃⌥⌘D`, or — more
robust — give the gesture an **Execute Shell Script** action:

```bash
/usr/local/bin/talky toggle
```

### CLI

```bash
talky meeting.mp4              # transcribe any audio/video file (cleaned)
talky interview.m4a --raw      # raw transcript, no LLM
talky lecture.mp3 --json       # segments with timestamps as JSON
talky toggle                   # start/stop dictation in the menu bar app
talky clean "um so basically"  # test the active cleanup model on text
talky models                   # list cleanup providers
talky use gemma3-4b            # switch cleanup model
talky download                 # pre-fetch the on-device speech model
```

## Configuration

`~/.config/talky/config.json` (created on first run; `talky config` prints the
path). Missing keys fall back to defaults, so you can keep a minimal file.

```jsonc
{
  "hotkey": "ctrl+alt+cmd+d",      // e.g. "cmd+shift+space", "f13"
  "locale": "en-US",
  "cleanup": {
    "enabled": true,
    "provider": "gemma3-1b",        // active provider id
    "providers": [
      { "id": "gemma3-1b", "baseURL": "http://localhost:11434/v1", "model": "gemma3:1b" },
      { "id": "openai",    "baseURL": "https://api.openai.com/v1", "model": "gpt-5-mini", "apiKeyEnv": "OPENAI_API_KEY" }
    ],
    "systemPrompt": "…",            // edit to taste
    "timeoutSeconds": 30
  },
  "output": { "paste": true, "restoreClipboard": true, "sounds": true }
}
```

Providers are plain OpenAI-compatible chat-completions endpoints. Local and
remote are configured identically; API keys come from the environment via
`apiKeyEnv` (don't put secrets in the file). Add as many as you like and
switch from the menu bar (Cleanup Model) or `talky use`.

## iPhone (TalkyPhone)

`TalkyPhone/` is an iOS 26 app built on the same TalkyKit SDK: tap the mic
(or press the **Action button**) → speak → cleaned text lands on the
clipboard, ready to paste anywhere. iOS forbids system-wide keystroke
injection, so paste is one tap — no custom keyboard required.

Two fully on-device cleanup engines:

- **`apple-fm`** (default) — Apple's built-in foundation model
  (Apple Intelligence). Zero download, also selectable on the Mac.
- **`mlx-qwen`** — Qwen3 4B via MLX; one-time ~2.3 GB download from
  Hugging Face, then fully local. Higher quality.

Build: open `TalkyPhone/TalkyPhone.xcodeproj` in Xcode, set your signing
team, run on your iPhone. (Regenerate the project after editing
`project.yml` with `xcodegen generate`.) Then Settings → Action Button →
Shortcut → **Toggle Talky Dictation**.

## Package layout

| Target | What it is |
|---|---|
| `TalkyCore` | Transcript/segment model (speaker-ready), `Transcriber` & `TextCleaner` protocols, config |
| `TalkyAudio` | Mic capture; audio extraction from audio/video files |
| `TalkyTranscribe` | `AppleTranscriber` — on-device SpeechAnalyzer engine |
| `TalkyClean` | `OpenAICompatCleaner` — model-agnostic LLM cleanup |
| `TalkyKit` | Umbrella SDK: `DictationSession` (mic → live text → clean → result), `FileTranscription` |
| `talky` | CLI |
| `TalkyApp` | Menu bar app: hotkey, live caption panel, auto-paste |

Consume the SDK from another package with
`.package(path: "…/talky")` and `import TalkyKit` (or just the pieces you need).

## Extending

- **New STT engine** (Whisper via WhisperKit, Parakeet via FluidAudio, a remote
  API): implement `Transcriber` + `TranscriptionStream` in a new module. If it
  labels speakers, set `.diarization` in `capabilities` and populate
  `TranscriptSegment.speaker` — formatting (`S1: …`) already works.
- **New cleanup backend** with a different wire format (e.g. native Anthropic
  API): implement `TextCleaner`.
