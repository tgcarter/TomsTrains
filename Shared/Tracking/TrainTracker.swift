import Foundation
import Observation

@MainActor @Observable
final class TrainTracker {
    private let store: TrackingStore
    private let provider: any DepartureProviding
    private let clock: @Sendable () -> Date
    private var routeSettings: RouteSettings
    private var refreshing = false
    private(set) var journeys: [TrackedJourney]
    private var archivedJourneys: [TrackedJourney]
    var previouslyTracked: [TrackedJourney] {
        (journeys + archivedJourneys).sorted { $0.departure.scheduled > $1.departure.scheduled }
    }
    var errors: [String: String] = [:]
    private(set) var autoRules: [AutoTrackingRule]
    private var automaticErrors: [UUID: String] = [:]
    var autoTrackingError: String? {
        automaticErrors.isEmpty ? nil : "Auto-tracking couldn’t check some scheduled trains. It will retry while the app is open."
    }
    private var checkingAutomatic = false
    private var lastAutomaticChecks: [UUID: Date] = [:]


    init(defaults: UserDefaults = .standard, provider: any DepartureProviding = NationalRailProvider(),
         routeSettings: RouteSettings = .load(), clock: @escaping @Sendable () -> Date = { Date() }) {
        store = TrackingStore(defaults: defaults)
        self.provider = provider
        self.routeSettings = routeSettings
        self.clock = clock
        let saved = store.loadJourneys()
        journeys = saved.current
        archivedJourneys = saved.archived
        autoRules = store.loadRules()
        pruneExpired()
    }

    private func matches(_ existing: Departure, _ update: Departure) -> Bool {
        existing.id == update.id || (existing.serviceRID != nil && existing.serviceRID == update.serviceRID
            && existing.origin == update.origin && existing.scheduled == update.scheduled && existing.callingAt == update.callingAt)
    }

    func contains(_ departure: Departure) -> Bool { journeys.contains { matches($0.departure, departure) } }

    func pruneExpired(settings: RouteSettings? = nil) {
        if let settings { routeSettings = settings }
        let dayStart = routeSettings.travelDayStart(at: clock())
        let expired = journeys.filter { !$0.isCurrent(since: dayStart) }
        guard !expired.isEmpty else { return }
        let expiredIDs = Set(expired.map(\.id))
        journeys.removeAll { expiredIDs.contains($0.id) }
        archivedJourneys.append(contentsOf: expired)
        for id in expiredIDs { errors[id] = nil }
        save()
    }

    func canStartTracking(_ departure: Departure) -> Bool {
        let journey = TrackedJourney(departure: departure)
        return !journey.hasFinished && journey.isCurrent(since: routeSettings.travelDayStart(at: clock()))
    }

    func toggle(_ departure: Departure) {
        pruneExpired()
        if contains(departure) {
            removeFromHistory(departure)
            return
        }
        guard canStartTracking(departure) else { return }
        markAutomaticRulesHandled(for: departure)
        startTracking(departure)
    }

    private func startTracking(_ departure: Departure) {
        archivedJourneys.removeAll { matches($0.departure, departure) }
        journeys.append(TrackedJourney(departure: departure))
        journeys.sort { $0.departure.scheduled < $1.departure.scheduled }
        save()
    }

    func removeFromHistory(_ departure: Departure) {
        let removed = journeys.filter { matches($0.departure, departure) }
        if !removed.isEmpty { markAutomaticRulesHandled(for: departure) }
        journeys.removeAll { matches($0.departure, departure) }
        archivedJourneys.removeAll { matches($0.departure, departure) }
        for journey in removed { errors[journey.id] = nil }
        save()
    }

    private func markAutomaticRulesHandled(for departure: Departure) {
        for index in autoRules.indices where autoRules[index].matches(departure) {
            autoRules[index].lastHandledDay = JourneyDirection.londonCalendar.startOfDay(for: departure.scheduled)
        }
        store.saveRules(autoRules)
    }

    func receive(_ departure: Departure, fromLiveDetails: Bool = false) {
        guard let index = journeys.firstIndex(where: { matches($0.departure, departure) }) else { return }
        var incoming = departure
        incoming.id = journeys[index].id
        let updated = journeys[index].accepting(incoming)
        guard updated.departure.observedAt == incoming.observedAt else { return }
        journeys[index] = updated
        if fromLiveDetails || updated.hasFinished || updated.departure.isCancelledAtDestination { errors[incoming.id] = nil }
        save()
    }

    func refresh() async {
        pruneExpired()
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        for id in journeys.map(\.id) {
            guard !Task.isCancelled else { return }
            guard let journey = journeys.first(where: { $0.id == id }), journey.needsLiveDetails else { continue }
            do {
                let updated = try await provider.serviceDetails(for: journey.departure)
                guard !Task.isCancelled else { return }
                pruneExpired()
                receive(updated, fromLiveDetails: true)
            } catch {
                guard !Task.isCancelled else { return }
                pruneExpired()
                if let current = journeys.first(where: { $0.id == id }), !current.hasFinished,
                   !current.departure.isCancelledAtDestination {
                    errors[id] = "Live update unavailable · showing last report"
                }
            }
        }
    }

    func refreshArchivedJourney(id: String) async {
        guard let journey = archivedJourneys.first(where: { $0.id == id }),
              journey.needsLiveDetails, journey.departure.serviceRID != nil,
              let update = try? await provider.serviceDetails(for: journey.departure), !Task.isCancelled,
              let index = archivedJourneys.firstIndex(where: { $0.id == id }) else { return }
        let refreshed = archivedJourneys[index].accepting(update)
        guard refreshed != archivedJourneys[index] else { return }
        archivedJourneys[index] = refreshed
        save()
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
                guard canStartTracking(departure), !contains(departure) else { continue }
                startTracking(departure)
            } catch {
                guard !Task.isCancelled else { return }
                if autoRules.contains(rule) { automaticErrors[rule.id] = "Live lookup failed" }
            }
        }
    }

    private func save() { store.saveJourneys(.init(current: journeys, archived: archivedJourneys)) }
}
