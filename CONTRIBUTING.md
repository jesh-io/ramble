# Contributing to Ramble

Use Xcode 26.2+ on macOS 26. Build with `swift build`, and run both
`swift test` and `swift test --package-path Packages/RambleAnalytics`.
The app bundle is assembled by `./scripts/build-app.sh`; an executable launched
directly with `swift run` does not behave like an installed app for permissions
or login items. See README for the iPhone/XcodeGen workflow.

Keep changes focused and explain the behavior plus verification in pull requests.
Add synthetic fixtures for parsing and cleanup regressions. Never submit recordings,
real transcripts, personal vocabulary, credentials, or private endpoint URLs in
tests, screenshots, issues, logs, or PRs. Report vulnerabilities privately.

`RambleCore` must remain usable on macOS and iOS. Provider protocol/registration
details are in `docs/STT-PLUGINS.md`. Unsupported integrations must remain disabled
and must not advertise runtime capabilities they do not implement.

Analytics changes must start with a product question in `docs/ANALYTICS.md`.
No text-content parameter is permitted. Add consent/redaction and delivery tests
when changing the analytics contract. Adapter code must not import application
modules or read transcript/recording files.

CI checks builds, tests, and secrets on pull requests and pushes. Release tags
produce archives with checksums. `VERSION` supplies local builds; release CI uses
the requested tag. Keep `RamblePhone/project.yml` version metadata in sync.
