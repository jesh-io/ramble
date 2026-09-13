# RambleAnalytics

Independent Swift package for opt-in, content-free product analytics. It has no
dependency on RambleCore or access to application transcripts/recordings.

```swift
import RambleAnalytics
Analytics.configure(enabled: consent, adapter: LoggingAnalyticsAdapter())
Analytics.dictationCompleted(source: .microphone, outcome: .success,
                            durationSeconds: 12, characterCount: 83)
```

For durable HTTPS delivery, compose `PersistentEventCollector` with
`HTTPAnalyticsTransport` and pass the collector as the adapter. A freshly created
collector never transmits until enabled. Each process needs a separate queue path.
Reset on opt-out clears queued events; any already transmitted data cannot be recalled.

See [the event design and delivery contract](../../docs/ANALYTICS.md).
Run `swift test --package-path Packages/RambleAnalytics` from the project root.
