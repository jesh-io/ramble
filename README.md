# Ramble

Voice-to-text for macOS 26 and iOS 26, built in Swift. Dictate into the app
you are using, clean up filler words and punctuation, or transcribe a file.
Includes a menu bar app, the `ramble` CLI, and modular Swift packages.

Apple's speech engine runs on-device by default. Cleanup uses a local Ollama
model by default on Mac and Apple Intelligence on iPhone. Optional remote
providers send audio and/or text to that provider. See [Privacy](PRIVACY.md).

## Install

Download `Ramble-macOS.zip` from [Releases](https://github.com/jesh-io/ramble/releases),
unzip it, and move `Ramble.app` to `/Applications`. The macOS release targets
Apple Silicon and macOS 26+. CLI downloads are in `ramble-cli-macOS.zip`.
Check downloads against `SHA256SUMS.txt`.

The first release is ad-hoc signed, not notarized. macOS may block it:
use System Settings → Privacy & Security → Open Anyway after attempting to
launch the downloaded app. Only bypass Gatekeeper for a download you trust.
Updates may require granting Accessibility again until Developer ID signing
is configured.

Grant Microphone access. Accessibility allows pasting into the frontmost app;
without it, results go to the clipboard. Settings → General → Startup has
**Launch Ramble at login**. Install in `/Applications` before enabling it.

For local cleanup, install [Ollama](https://ollama.com) and run:

```bash
ollama pull qwen3:4b-instruct
```

Cleanup is optional. Disable it for raw dictation, or select Apple Intelligence
on compatible hardware with Apple Intelligence enabled.

## Use

Press **⌃⌥⌘D**, speak, and press the shortcut again to paste the result.
Settings supports keyboard, mouse, and modifier-key triggers, including hold-to-talk.
Audio recordings, transcript history, and product analytics are all **off by default**.

```bash
ramble meeting.mp4
ramble interview.m4a --raw
ramble lecture.mp3 --json
ramble toggle
ramble clean "um so basically"
ramble models
ramble use qwen3-4b
ramble config
```

BetterTouchTool can trigger `ramble toggle` or send the keyboard shortcut.
To inspect all commands, run `ramble --help`.

## Providers and credentials

Settings → Accounts supports local and remote cleanup accounts. Save API keys
in Keychain or name an environment variable; do not put secrets in configuration.
GUI apps launched by Finder do not inherit terminal shell variables. Custom
OpenAI-compatible endpoints work for cleanup. Personal vocabulary is included
in cleanup prompts, so select a local provider to keep it on-device.

| Speech engine | Live streaming | Batch | Status |
|---|---|---|---|
| Apple SpeechAnalyzer | Yes | Yes | Default, on-device |
| OpenAI Transcribe | No | Yes | Remote; live mode currently uses batch fallback |
| Mistral Voxtral | No | Yes | Remote; live mode currently uses batch fallback |
| Groq Whisper | No | Yes | Remote |
| ElevenLabs, AssemblyAI, Deepgram | No | No | Scaffolds; disabled pending implementation |

Select a supported remote speech engine under Settings → General. Batch mode
records locally and uploads at stop. Do not treat catalog/model prices as current
quotes: provider availability and rates change, and editable defaults are estimates.

## Build from source

Requires macOS 26+ and Xcode 26.2 or newer with Swift 6.2.

```bash
git clone https://github.com/jesh-io/ramble.git
cd ramble
swift test
swift test --package-path Packages/RambleAnalytics
./scripts/build-app.sh
cp -R dist/Ramble.app /Applications/
open /Applications/Ramble.app
```

For a command on your PATH, copy `dist/ramble` to a directory on your PATH.
The build script reads `VERSION` or `RAMBLE_VERSION`; release CI supplies the tag.

Private trackpad APIs are excluded from source builds by default. To opt in:

```bash
RAMBLE_ENABLE_GESTURES=1 ./scripts/build-app.sh
```

That build uses Apple's private MultitouchSupport framework through
OpenMultitouchSupport and is unsuitable for App Store submission. The
released `Ramble-macOS.zip` is built with the flag on, so the trackpad
gesture — a 3-finger triple tap to start and stop dictation — works out of
the box; turn it off or rebind it in Settings → Trackpad Gesture.

### iPhone (WIP)

The mobile client is unfinished and is not part of the v0.1 release gate.
The instructions below are for development; a successful mobile build is not
guaranteed for this snapshot.

Install XcodeGen and generate the ignored project before opening it:

```bash
brew install xcodegen
cd RamblePhone
xcodegen generate
open RamblePhone.xcodeproj
```

Select your signing team in Xcode, then run on an iPhone with iOS 26. Apple
Intelligence is the default cleanup engine; optional MLX Qwen downloads model
weights from Hugging Face. The Action button can run Toggle Ramble Dictation.
The iPhone app is source-only in this release; no IPA is distributed.
The MLX dependency requires the Metal toolchain (`xcodebuild -downloadComponent
MetalToolchain`) and approval of its package macros in Xcode.

## Configuration and upgrading

Mac configuration: `~/.config/ramble/config.json`. Missing keys use defaults.
On iPhone, configuration is `ramble-config.json` in the app's Documents directory.
The rename introduces new bundle identifiers and data locations. Existing installs
keep their previous settings and recordings untouched; there is no automatic
import. Copy a reviewed configuration into the new location if desired, or start
fresh. Re-grant permissions and replace old shortcuts/login items after installing.

Recordings can be enabled in Settings → Storage and are normally pruned after
72 hours. Transcript history has separate consent and retention. Pruning runs at
launch and after dictation; `0` keeps data indefinitely. Delete stored audio and
history through Storage after stopping active dictation.

## Development

`RambleCore` holds configuration and transcript types; `RambleKit` orchestrates
capture, transcription and cleanup. `RambleApp`, `RambleCLI` and `RamblePhone`
are clients. Speech engines are separate targets. `Packages/RambleAnalytics`
is an independent package with typed events, logging, HTTP delivery and a
persistent retry queue. The release uses logging only, after explicit opt-in;
analytics never receives dictated content.

- [Contributing](CONTRIBUTING.md)
- [Privacy](PRIVACY.md)
- [Analytics questions, events and delivery contract](docs/ANALYTICS.md)
- [Speech plugin architecture](docs/STT-PLUGINS.md)
- [Security reporting](SECURITY.md)
- [Changelog](CHANGELOG.md)

MIT licensed. Dependency license texts are included in `ThirdPartyNotices`.
