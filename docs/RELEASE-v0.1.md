## Ramble v0.1

Ramble is a Swift dictation app for macOS 26 with a menu bar interface, CLI,
local Apple speech recognition and optional local or remote AI cleanup.

- Full Ramble branding across app, CLI, SDK and iPhone source project.
- Launch at login through macOS Login Items.
- MIT license, privacy/security docs, Keychain credentials and private storage.
- Audio and transcript history are opt-in, with retention and deletion controls.
- Product analytics is opt-in and logs metadata locally only. It never receives
  dictated content. Includes a separate analytics package with an HTTP transport
  and durable batching/retry collector for future backend integration.
- Supported remote speech engines: OpenAI, Mistral and Groq (batch).
- Automated build, core/parser tests, analytics delivery tests and secret scanning.

### Downloads

Download **Ramble-macOS.zip**, unzip, and move **Ramble.app** to `/Applications`.
Requires Apple Silicon and macOS 26+. Grant Microphone and Accessibility when
prompted. For local cleanup, install Ollama and run `ollama pull qwen3:4b-instruct`.

**ramble-cli-macOS.zip** contains the standalone CLI and license notices.
Verify downloads with **SHA256SUMS.txt**.

### Known limitations

This release is ad-hoc signed, not notarized. If macOS blocks it, use Privacy &
Security → Open Anyway after attempting to launch. Updating may re-prompt for
Accessibility until Developer ID signing is configured. Launch at login should
be enabled after installing in `/Applications`.

ElevenLabs, AssemblyAI and Deepgram remain disabled scaffolds. Private trackpad
APIs are excluded from the default build. No analytics backend is connected.
The iPhone app is WIP, source-only, and outside this release's validation scope.

Previous installs retain their original data. Ramble uses new bundle identifiers,
configuration and storage locations; re-grant permissions and migrate settings
manually if needed. Git history is preserved.
