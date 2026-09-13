# Release checklist

- [x] MIT license and contributor/security/privacy documentation.
- [x] Rename current source, targets, executables, identifiers and docs to Ramble.
- [x] Preserve history; publish only main and the requested release tag.
- [x] Keep credentials in Keychain; protect private files.
- [x] Make recording/history and product analytics opt-in.
- [x] Document actual provider support; disable incomplete integrations.
- [x] Exclude private gesture APIs from the default app build.
- [x] Add native launch-at-login setting.
- [x] Add core/parsing and independent analytics delivery tests.
- [x] Add PR checks, secret scanning, dependency updates and pinned actions.
- [x] Include logging and HTTPS analytics adapters, durable batching/retry and consent tests.
- [x] Run all tests and assemble/inspect a clean release build (19 tests pass).
- [ ] Push main and v0.1 to jesh-io/ramble; attach app, CLI and checksums.
- [ ] Verify GitHub Actions and release assets.
- [ ] Configure optional Developer ID signing/notarization repository secrets.
- [ ] Enable repository branch protection/security alerts where supported.

No HTTP analytics endpoint is configured in v0.1. Before a backend rollout,
implement server-side event validation/deduplication/retention and update consent.
