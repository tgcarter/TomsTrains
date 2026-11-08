import Foundation

/// Keeps persistence separate from tracking decisions.
struct TrackingStore {
    let defaults: UserDefaults
    private let journeysKey = "trackedJourneys.v1"
    private let rulesKey = "autoTrackingRules.v2"

    func loadJourneys() -> [TrackedJourney] {
        defaults.data(forKey: journeysKey)
            .flatMap { try? JSONDecoder().decode([TrackedJourney].self, from: $0) } ?? []
    }
    func saveJourneys(_ journeys: [TrackedJourney]) {
        if let data = try? JSONEncoder().encode(journeys) { defaults.set(data, forKey: journeysKey) }
    }
    func loadRules() -> [AutoTrackingRule] {
        defaults.data(forKey: rulesKey)
            .flatMap { try? JSONDecoder().decode([AutoTrackingRule].self, from: $0) } ?? []
    }
    func saveRules(_ rules: [AutoTrackingRule]) {
        if let data = try? JSONEncoder().encode(rules) { defaults.set(data, forKey: rulesKey) }
    }
}
