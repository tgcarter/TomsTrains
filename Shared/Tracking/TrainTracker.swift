import Foundation
import Observation

@MainActor @Observable
final class TrainTracker {
    private let store: TrackingStore
    private let provider: any DepartureProviding
    private var refreshing = false
    private(set) var journeys: [TrackedJourney]
    var errors: [String: String] = [:]
    private(set) var autoRules: [AutoTrackingRule]
    private var automaticErrors: [UUID: String] = [:]
    var autoTrackingError: String? {
        automaticErrors.isEmpty ? nil : "Auto-tracking couldn’t check some scheduled trains. It will retry while the app is open."
    }
    private var checkingAutomatic = false
    private var lastAutomaticChecks: [UUID: Date] = [:]


    init(defaults: UserDefaults = .standard, provider: any DepartureProviding = NationalRailProvider()) {
        store = TrackingStore(defaults: defaults)
        self.provider = provider
        journeys = store.loadJourneys().filter { !$0.hasFinished }
        autoRules = store.loadRules()
        save()
    }

    private func matches(_ existing: Departure, _ update: Departure) -> Bool {
        existing.id == update.id || (existing.serviceRID != nil && existing.serviceRID == update.serviceRID
            && existing.origin == update.origin && existing.scheduled == update.scheduled && existing.callingAt == update.callingAt)
    }

    func contains(_ departure: Departure) -> Bool { journeys.contains { matches($0.departure, departure) } }

    func toggle(_ departure: Departure) {
        for index in autoRules.indices where autoRules[index].matches(departure) {
            autoRules[index].lastHandledDay = JourneyDirection.londonCalendar.startOfDay(for: departure.scheduled)
        }
        store.saveRules(autoRules)
        if contains(departure) {
            let removed = journeys.filter { matches($0.departure, departure) }.map(\.id)
            journeys.removeAll { removed.contains($0.id) }
            for id in removed { errors[id] = nil }
            errors[departure.id] = nil
        } else {
            let journey = TrackedJourney(departure: departure)
            guard !journey.hasFinished else { return }
            journeys.append(journey)
            journeys.sort { $0.departure.scheduled < $1.departure.scheduled }
        }
        save()
    }

    func receive(_ departure: Departure) {
        guard let index = journeys.firstIndex(where: { matches($0.departure, departure) }) else { return }
        var incoming = departure
        incoming.id = journeys[index].id
        let updated = journeys[index].accepting(incoming)
        if updated.hasFinished {
            journeys.remove(at: index)
        } else {
            journeys[index] = updated
        }
        errors[incoming.id] = nil
        save()
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        for journey in journeys {
            guard !Task.isCancelled else { return }
            do {
                let updated = try await provider.serviceDetails(for: journey.departure)
                guard !Task.isCancelled else { return }
                receive(updated)
            } catch {
                guard !Task.isCancelled else { return }
                if journeys.contains(where: { $0.id == journey.id }) {
                    errors[journey.id] = "Live update unavailable · showing last report"
                }
            }
        }
    }

    func configureAutomatic(_ rule: AutoTrackingRule) {
        guard rule.isValid else { return }
        let index = autoRules.firstIndex { $0.id == rule.id }
            ?? autoRules.firstIndex { $0.origin == rule.origin && $0.destination == rule.destination && $0.departureMinutes == rule.departureMinutes }
        var updated = rule
        if let index {
            let previous = autoRules[index]
            updated.id = previous.id
            updated.lastHandledDay = previous.origin == rule.origin && previous.destination == rule.destination
                && previous.departureMinutes == rule.departureMinutes ? previous.lastHandledDay : nil
        }
        if let current = journeys.first(where: { updated.matches($0.departure) })?.departure {
            updated.lastHandledDay = JourneyDirection.londonCalendar.startOfDay(for: current.scheduled)
        }
        if let index { autoRules[index] = updated } else { autoRules.append(updated) }
        lastAutomaticChecks[updated.id] = nil
        automaticErrors[updated.id] = nil
        store.saveRules(autoRules)
    }

    func removeAutomatic(id: UUID) {
        autoRules.removeAll { $0.id == id }
        lastAutomaticChecks[id] = nil
        automaticErrors[id] = nil
        store.saveRules(autoRules)
    }

    func autoTrack(at now: Date, lookup: (@Sendable (AutoTrackingRule, Date) async throws -> Departure?)? = nil) async {
        guard !checkingAutomatic else { return }
        checkingAutomatic = true
        defer { checkingAutomatic = false }
        for rule in autoRules {
            guard !Task.isCancelled else { return }
            guard autoRules.contains(rule), rule.isDue(on: now),
                  lastAutomaticChecks[rule.id].map({ now.timeIntervalSince($0) >= 60 }) ?? true else { continue }
            lastAutomaticChecks[rule.id] = now
            do {
                let departure: Departure?
                if let lookup { departure = try await lookup(rule, now) }
                else { departure = try await provider.automaticDeparture(for: rule, at: now) }
                guard !Task.isCancelled else { return }
                // An edit, removal or manual stop during the request invalidates only this rule.
                guard let index = autoRules.firstIndex(where: { $0 == rule }) else { continue }
                automaticErrors[rule.id] = nil
                guard let departure, rule.matches(departure),
                      JourneyDirection.londonCalendar.isDate(departure.scheduled, inSameDayAs: now) else { continue }
                autoRules[index].lastHandledDay = JourneyDirection.londonCalendar.startOfDay(for: now)
                store.saveRules(autoRules)
                let journey = TrackedJourney(departure: departure)
                guard !journey.hasFinished, !contains(departure) else { continue }
                journeys.append(journey)
                journeys.sort { $0.departure.scheduled < $1.departure.scheduled }
                save()
            } catch {
                guard !Task.isCancelled else { return }
                if autoRules.contains(rule) { automaticErrors[rule.id] = "Live lookup failed" }
            }
        }
    }

    private func save() { store.saveJourneys(journeys) }
}
