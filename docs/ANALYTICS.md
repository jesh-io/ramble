# Product questions and measurement

Analytics is opt-in and off by default. Its API never accepts dictated content:
no transcript, audio, prompt, vocabulary, raw error message, endpoint, account ID,
file name, clipboard content, or persistent user/device ID. Counts are calculated
by the caller; the analytics package only receives numbers. Custom provider and
model names become `custom` through allowlists. All lengths and timings are buckets.

## Questions first

| Product question | Evidence | Event(s) |
|---|---|---|
| Are people opening the app and successfully completing dictation? | Opens, starts, terminal outcome counts | `app_opened`, `dictation_started`, `dictation_completed` |
| Which speech providers and models are used, and which complete reliably? | Approved model/provider categories at start and completion | `dictation_started`, `dictation_completed` |
| Are sessions short commands or longer composition? | Character count and duration buckets | `dictation_completed` |
| When is dictation useful, and is use bursty? | Six-hour local daypart; start-to-start interval bucket within this process | `dictation_started` |
| Which stages fail? | Permission, capture, transcription, cleanup failure counts; no error payloads | `operation_failed` |
| Does cleanup help, or interrupt the flow? | Cleanup latency, outcome, guard rejection and skips | `cleanup_completed`, `cleanup_skipped` |
| Which optional features are adopted? | Feature toggle and enabled state | `feature_changed` |

Duration, frequency and model choice describe behavior; they do not prove usefulness.
Prioritize completion rate, failure rate, cleanup latency, rejection rate and skip
rate. A long dictation could be useful writing or a slow workflow. Model mix should
guide testing and reliability work, not be treated as a quality ranking.

These events cannot measure retained *users*, per-person funnels, paid conversion,
actual transcription accuracy, or editing quality. There is deliberately no user ID.
Do not infer population adoption from event volume or extrapolate opt-in participants
to every user. Use voluntary interviews and synthetic benchmarks for missing context.
Start/completion counts are aggregate: a crash can leave an unmatched start.
Microphone duration currently measures the full attempt including finalization
and cleanup; file duration measures transcription processing time, not media length.
Cleanup events are emitted per chunk when incremental cleanup is on, so do not
interpret them as one event per dictation. Standalone text-cleaning/evaluation
commands are not instrumented; stored history is never replayed into analytics.

## Package and call sites

`Packages/RambleAnalytics` is an independent Swift package without app/core imports.

```swift
import RambleAnalytics
Analytics.configure(enabled: userConsent, adapter: LoggingAnalyticsAdapter())
Analytics.dictationCompleted(source: .microphone, outcome: .success,
                            durationSeconds: 22, characterCount: 127)
```

Default release behavior: only the logging adapter, visible in macOS Console under
`io.ramble.analytics`. No server endpoint is configured. OS log retention is managed
by the OS; opt-out cannot erase logs already written or events already accepted by
a server. Consent is checked on every call. No pre-consent data is collected.

Adapters implement `AnalyticsAdapter`; networking implements `AnalyticsTransport`.
To configure HTTP after an explicit backend/privacy rollout:

```swift
let transport = try HTTPAnalyticsTransport(endpoint: URL(string: "https://analytics.example.com/v1/events")!)
let collector = try PersistentEventCollector(fileURL: queueURL, transport: transport)
Analytics.configure(enabled: userConsent, adapter: collector)
```

Construct one collector per process, using a distinct Application Support queue file
for app and CLI. Construction never delivers; consent enables its worker. Reuse the
same adapter while consent stays on. Replacing an adapter resets its previous queue.
The app integration point is `Sources/RambleCore/ProductAnalytics.swift`.

## Delivery contract

`POST` HTTPS with `Content-Type: application/json`. A batch has `schemaVersion: 1`,
`batchID` (UUID) and `events`. Each event contains `id` (UUID), `occurredAt` (UTC ISO
8601), and `event` containing `schemaVersion`, `name`, and string-valued `properties`.
`Idempotency-Key` is the batch UUID. Deduplicate by **event ID**, because batch
boundaries/IDs can change on retry or after a crash. No client secret is shipped.
An optional runtime bearer token is supported for controlled deployments only.

Any 2xx acknowledges the entire batch. The server must durably store all events
before acknowledging. Network errors, 408, 425, 429 and 5xx retry with exponential
backoff plus jitter; `Retry-After` supports seconds and HTTP dates. Other responses
are permanent rejections and discard the batch. Redirects are refused. Server
implementations should bound request sizes, validate schema and event/property
allowlists, rate-limit abuse, and avoid retaining IP addresses or request headers.

Events are atomically persisted before enqueue returns. The queue defaults to 1,000
events, a seven-day TTL, batches of 50 and a 30-second flush cadence while the
process runs. Overflow evicts oldest events. Retry count and next attempt persist.
Files use owner-only permissions and are excluded from backups. Corrupt queues
are discarded; write failures drop the new event and log a content-free diagnostic.
Delivery is at least once, not exactly once. Acknowledgment/disk-write crashes may
duplicate delivery. OS background suspension pauses delivery until execution resumes.

Opt-out cancels the worker and clears persisted pending events. In-flight data may
already have reached the server; it cannot be recalled. No analytics system may
read application history or recordings to backfill measurements.
