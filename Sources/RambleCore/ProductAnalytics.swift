import Foundation
import RambleAnalytics

/// Backend rollout is explicit. Current releases use local logging only.
/// Configure an HTTP collector here once the endpoint and privacy notice ship.
public enum ProductAnalytics {
    public static func configure(_ config: RambleConfig) {
        Analytics.configure(enabled: config.analyticsEnabled)
    }
}
