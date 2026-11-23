import Foundation

/// Keeps persistence separate from tracking decisions.
struct TrackingStore {
    struct Journeys: Codable {
        var current: [TrackedJourney] = []
        var archived: [TrackedJourney] = []
    }

    let defaults: UserDefaults
    private let journeysKey = "trackedJourneys.v1"
    private let rulesKey = "autoTrackingRules.v2"

    func loadJourneys() -> Journeys {
        guard let data = defaults.data(forKey: journeysKey) else { return Journeys() }
        let decoder = JSONDecoder()
        if let saved = try? decoder.decode(Journeys.self, from: data) { return saved }
        return Journeys(current: (try? decoder.decode([TrackedJourney].self, from: data)) ?? [])
    }
    func saveJourneys(_ journeys: Journeys) {
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
