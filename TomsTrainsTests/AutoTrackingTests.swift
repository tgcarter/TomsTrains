import XCTest
#if SWIFT_PACKAGE
@testable import TomsTrainsCore
#endif

final class AutoTrackingTests: XCTestCase {
    private let morning = ISO8601DateFormatter().date(from: "2026-09-23T07:00:00Z")!
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    @MainActor private func makeTracker(defaults: UserDefaults) -> TrainTracker {
        let morning = morning
        return TrainTracker(defaults: defaults, routeSettings: RouteSettings(), clock: { morning })
    }
    private func train(_ id: String, scheduled: Date) -> Departure {
        Departure(id: id, origin: .kingsCross, destination: "Peterborough", callingAt: [.stNeots],
            scheduled: scheduled, status: .onTime, platform: "8", operatorName: "Great Northern",
            journeyMinutes: 50, disruptionReason: nil)
    }

    func testRuleMatchesLocalTimeAndChosenWeekdaysAcrossDates() throws {
        let original = train("old-rid", scheduled: date("2026-09-22T08:12:00Z"))
        let rule = AutoTrackingRule(departure: original)
        XCTAssertEqual(rule.weekdays, [2, 3, 4, 5, 6])
        XCTAssertTrue(rule.isDue(on: date("2026-09-23T07:00:00Z")))
        XCTAssertFalse(rule.isDue(on: date("2026-09-26T07:00:00Z")))
        XCTAssertTrue(rule.matches(train("new-rid", scheduled: date("2026-09-23T08:12:00Z"))))
        XCTAssertTrue(rule.matches(train("winter-rid", scheduled: date("2026-12-23T09:12:00Z"))))
        XCTAssertFalse(rule.matches(train("changed-time", scheduled: date("2026-09-23T08:13:00Z"))))
        XCTAssertEqual(try JSONDecoder().decode(AutoTrackingRule.self, from: JSONEncoder().encode(rule)), rule)
    }

    @MainActor func testMultipleTrainsSurviveRestartAndStopIndependently() throws {
        let name = "auto-test-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let first = train("first", scheduled: date("2026-09-23T08:12:00Z"))
        let second = train("second", scheduled: date("2026-09-23T09:12:00Z"))
        let tracker = makeTracker(defaults: defaults)
        tracker.toggle(first)
        tracker.toggle(second)
        XCTAssertEqual(tracker.journeys.map(\.id), ["first", "second"])
        XCTAssertEqual(makeTracker(defaults: defaults).journeys.map(\.id), ["first", "second"])
        defaults.set(try JSONEncoder().encode([TrackedJourney(departure: first), TrackedJourney(departure: second)]), forKey: "trackedJourneys.v1")
        XCTAssertEqual(makeTracker(defaults: defaults).journeys.map(\.id), ["first", "second"], "Preserve all saved trains")
    }

    @MainActor func testAutomaticSelectionAndManualStopPersistUntilNextDay() async {
        let name = "auto-test-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let now = date("2026-09-23T07:00:00Z")
        let today = train("today", scheduled: date("2026-09-23T08:12:00Z"))
        let tracker = makeTracker(defaults: defaults)
        tracker.configureAutomatic(AutoTrackingRule(departure: today))
        await tracker.autoTrack(at: now, lookup: { _, _ in today })
        XCTAssertEqual(tracker.journeys.map(\.id), ["today"])
        XCTAssertEqual(tracker.previouslyTracked.map(\.id), ["today"])
        tracker.toggle(today)
        let restarted = makeTracker(defaults: defaults)
        await restarted.autoTrack(at: now.addingTimeInterval(120), lookup: { _, _ in
            XCTFail("Manual stop must survive restart"); return today
        })
        XCTAssertTrue(restarted.journeys.isEmpty)
        XCTAssertTrue(restarted.previouslyTracked.isEmpty)
        let tomorrow = train("tomorrow", scheduled: date("2026-09-24T08:12:00Z"))
        await restarted.autoTrack(at: date("2026-09-24T07:00:00Z"), lookup: { _, _ in tomorrow })
        XCTAssertEqual(restarted.journeys.map(\.id), ["tomorrow"])
    }

    @MainActor func testAutomaticAddsAlongsideManualAndRejectsRemovedRule() async {
        let name = "auto-test-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let now = date("2026-09-23T07:00:00Z")
        let automatic = train("automatic", scheduled: date("2026-09-23T08:12:00Z"))
        let manual = train("manual", scheduled: date("2026-09-23T09:12:00Z"))
        let tracker = makeTracker(defaults: defaults)
        let rule = AutoTrackingRule(departure: automatic)
        tracker.configureAutomatic(rule)
        tracker.toggle(manual)
        await tracker.autoTrack(at: now, lookup: { _, _ in automatic })
        XCTAssertEqual(tracker.journeys.map(\.id), ["automatic", "manual"])
        tracker.toggle(automatic)
        tracker.removeAutomatic(id: rule.id)
        let replacement = AutoTrackingRule(departure: automatic)
        tracker.configureAutomatic(replacement)
        await tracker.autoTrack(at: now.addingTimeInterval(120), lookup: { rule, _ in
            await tracker.removeAutomatic(id: rule.id)
            return automatic
        })
        XCTAssertEqual(tracker.journeys.map(\.id), ["manual"])
        XCTAssertTrue(tracker.autoRules.isEmpty)
    }

    @MainActor func testCompletedAndWrongDayServicesAreNotAutomaticallyTracked() async {
        let name = "auto-test-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let now = date("2026-09-23T12:00:00Z")
        var completed = train("completed", scheduled: date("2026-09-23T08:12:00Z"))
        completed.observedAt = now
        completed.actualArrival = date("2026-09-23T09:02:00Z")
        let reported = completed
        let tracker = makeTracker(defaults: defaults)
        tracker.configureAutomatic(AutoTrackingRule(departure: completed))
        await tracker.autoTrack(at: now, lookup: { _, _ in reported })
        XCTAssertTrue(tracker.journeys.isEmpty)
        XCTAssertFalse(tracker.autoRules[0].isDue(on: now))
        tracker.removeAutomatic(id: tracker.autoRules[0].id)
        tracker.configureAutomatic(AutoTrackingRule(departure: completed))
        let wrongDay = train("wrong-day", scheduled: date("2026-09-24T08:12:00Z"))
        await tracker.autoTrack(at: now, lookup: { _, _ in wrongDay })
        XCTAssertTrue(tracker.journeys.isEmpty)
    }

    @MainActor func testCompletedServiceStaysTrackedAfterDestinationCancellation() {
        let name = "complete-test-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let tracker = makeTracker(defaults: defaults)
        var service = train("cancelled-stop", scheduled: date("2026-09-23T08:12:00Z"))
        tracker.toggle(service)
        service.observedAt = date("2026-09-23T10:00:00Z")
        service.arrivalStatus = "Cancelled"
        service.routeStops = [
            RouteStop(id: "sno", crs: "SNO", name: "St Neots", scheduled: nil, expected: nil,
                actual: nil, isCancelled: true, estimate: nil, isBoarding: false, isDestination: true),
            RouteStop(id: "pbo", crs: "PBO", name: "Peterborough", scheduled: nil, expected: nil,
                actual: date("2026-09-23T09:30:00Z"), isCancelled: false, estimate: nil, isBoarding: false, isDestination: false)
        ]
        XCTAssertFalse(TrackedJourney(departure: service).hasArrived)
        service.terminalActual = date("2026-09-23T09:30:00Z")
        XCTAssertTrue(TrackedJourney(departure: service).hasFinished)
        tracker.receive(service)
        XCTAssertEqual(tracker.journeys.first?.departure.journeyStatus, .disrupted("Not calling at St Neots"))
        XCTAssertEqual(makeTracker(defaults: defaults).journeys.first?.id, service.id)
    }
    @MainActor func testMultipleRulesPersistAndContinueAfterLookupFailure() async throws {
        let name = "multi-test-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let now = date("2026-09-23T07:00:00Z")
        let first = train("first", scheduled: date("2026-09-23T08:12:00Z"))
        let second = train("second", scheduled: date("2026-09-23T09:12:00Z"))
        let firstRule = AutoTrackingRule(departure: first)
        let tracker = makeTracker(defaults: defaults)
        XCTAssertTrue(tracker.autoRules.isEmpty)
        tracker.configureAutomatic(firstRule)
        let other = AutoTrackingRule(departure: second)
        tracker.configureAutomatic(other)
        XCTAssertEqual(makeTracker(defaults: defaults).autoRules.count, 2)
        await tracker.autoTrack(at: now, lookup: { rule, _ in
            if rule.id == firstRule.id { throw RailAPIError.unavailable }
            return second
        })
        XCTAssertEqual(tracker.journeys.map(\.id), ["second"])
        XCTAssertNotNil(tracker.autoTrackingError)
        await tracker.autoTrack(at: now.addingTimeInterval(120), lookup: { _, _ in first })
        XCTAssertEqual(tracker.journeys.map(\.id), ["first", "second"])
        XCTAssertNil(tracker.autoTrackingError)
        tracker.toggle(first)
        XCTAssertEqual(tracker.journeys.map(\.id), ["second"])
        XCTAssertFalse(tracker.autoRules.first { $0.id == firstRule.id }!.isDue(on: now))
        tracker.removeAutomatic(id: firstRule.id)
        let restarted = makeTracker(defaults: defaults)
        XCTAssertEqual(restarted.autoRules.map(\.id), [other.id])
        XCTAssertEqual(restarted.journeys.map(\.id), ["second"])
    }

    @MainActor func testCompletingOneTrainKeepsOthersAndRuleEditsAreIndependent() {
        let name = "multi-test-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var first = train("first", scheduled: date("2026-09-23T08:12:00Z"))
        let second = train("second", scheduled: date("2026-09-23T09:12:00Z"))
        let tracker = makeTracker(defaults: defaults)
        var rule = AutoTrackingRule(departure: first)
        let other = AutoTrackingRule(departure: second)
        tracker.configureAutomatic(rule)
        tracker.configureAutomatic(other)
        rule.isEnabled = false
        rule.weekdays = [1, 7]
        tracker.configureAutomatic(rule)
        XCTAssertEqual(tracker.autoRules.count, 2)
        XCTAssertEqual(tracker.autoRules.first { $0.id == other.id }, other)
        XCTAssertEqual(tracker.autoRules.first { $0.id == rule.id }?.weekdays, [1, 7])
        tracker.toggle(first)
        tracker.toggle(second)
        first.observedAt = date("2026-09-23T09:10:00Z")
        first.actualArrival = date("2026-09-23T09:02:00Z")
        tracker.receive(first)
        XCTAssertEqual(tracker.journeys.map(\.id), ["first", "second"])
        XCTAssertTrue(tracker.journeys[0].hasArrived)
        tracker.toggle(first)
        XCTAssertEqual(makeTracker(defaults: defaults).journeys.map(\.id), ["second"])
        XCTAssertEqual(makeTracker(defaults: defaults).previouslyTracked.map(\.id), ["second"])
    }

    @MainActor func testCompletedJourneyStaysUntilConfiguredResetAndIsNotPolled() async {
        let name = "reset-test-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var settings = RouteSettings()
        settings.resetMinutes = 3 * 60
        let reset = date("2026-09-24T02:00:00Z") // 03:00 in London
        let clock = ContinuousTestClock(reset.addingTimeInterval(-60))
        let provider = CompletedJourneyTestProvider()
        let tracker = TrainTracker(defaults: defaults, provider: provider, routeSettings: settings, clock: { clock.now })
        var service = train("arrived", scheduled: date("2026-09-23T22:30:00Z"))
        tracker.toggle(service)
        service.actualArrival = date("2026-09-23T23:20:00Z")
        service.terminalActual = date("2026-09-23T23:40:00Z")
        service.observedAt = date("2026-09-23T23:41:00Z")
        tracker.receive(service)

        var incomplete = service
        incomplete.actualArrival = nil
        incomplete.observedAt = clock.now
        tracker.receive(incomplete)
        await tracker.refresh()
        XCTAssertTrue(tracker.journeys.first?.hasArrived == true)
        XCTAssertTrue(TrainTracker(defaults: defaults, routeSettings: settings, clock: { clock.now }).journeys.first?.hasArrived == true)
        XCTAssertTrue(tracker.errors.isEmpty)

        clock.now = reset
        await tracker.refresh()
        XCTAssertTrue(tracker.journeys.isEmpty)
        let restarted = TrainTracker(defaults: defaults, routeSettings: settings, clock: { clock.now })
        XCTAssertTrue(restarted.journeys.isEmpty)
        XCTAssertEqual(restarted.previouslyTracked.map(\.id), ["arrived"])
        XCTAssertEqual(restarted.previouslyTracked.first?.departure.actualArrival, service.actualArrival)
        XCTAssertEqual(DelayRepay.links(for: service).first?.url.host, "www.greatnorthernrail.com")
        tracker.toggle(incomplete)
        XCTAssertTrue(tracker.journeys.isEmpty)
        tracker.removeFromHistory(service)
        XCTAssertTrue(TrainTracker(defaults: defaults, routeSettings: settings, clock: { clock.now }).previouslyTracked.isEmpty)
    }

    @MainActor func testIntermediateStopKeepsPollingThroughTheTerminusAndSavesBothReports() async throws {
        let name = "arrival-test-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let clock = ContinuousTestClock(date("2026-09-23T08:00:00Z"))
        var service = train("to-st-neots", scheduled: date("2026-09-23T08:12:00Z"))
        let scheduledArrival = date("2026-09-23T09:02:00Z")
        let arrival = date("2026-09-23T09:05:00Z")
        let departure = date("2026-09-23T09:06:00Z")
        service.scheduledArrival = scheduledArrival
        var departedStNeots = service
        departedStNeots.observedAt = date("2026-09-23T09:07:00Z")
        departedStNeots.routeStops = [
            RouteStop(id: "sno", crs: "SNO", name: "St Neots", scheduled: scheduledArrival, expected: nil,
                actual: departure, isCancelled: false, estimate: nil, isBoarding: false, isDestination: true,
                actualDeparture: departure)
        ]
        var arrivalReport = departedStNeots
        arrivalReport.observedAt = date("2026-09-23T09:08:00Z")
        arrivalReport.actualArrival = arrival

        // The terminus report may omit earlier times, including the selected stop's.
        var later = departedStNeots
        later.observedAt = date("2026-09-23T09:36:00Z")
        later.terminalActual = date("2026-09-23T09:34:00Z")
        later.scheduledArrival = nil
        later.routeStops?[0].actual = nil
        later.routeStops?[0].actualDeparture = nil
        later.routeStops?.append(RouteStop(id: "hun", crs: "HUN", name: "Huntingdon", scheduled: nil, expected: nil,
            actual: date("2026-09-23T09:17:00Z"), isCancelled: false, estimate: nil, isBoarding: false, isDestination: false))
        later.routeStops?.append(RouteStop(id: "pbo", crs: "PBO", name: "Peterborough", scheduled: nil, expected: nil,
            actual: later.terminalActual, isCancelled: false, estimate: nil, isBoarding: false, isDestination: false))
        let provider = TrackingDetailsTestProvider(reports: [departedStNeots, arrivalReport, later])
        let tracker = TrainTracker(defaults: defaults, provider: provider, routeSettings: RouteSettings(), clock: { clock.now })
        tracker.toggle(service)

        clock.now = date("2026-09-23T09:07:00Z")
        await tracker.refresh()
        let first = try XCTUnwrap(tracker.previouslyTracked.first)
        XCTAssertTrue(first.hasArrived)
        XCTAssertNil(first.reportedArrival)
        XCTAssertEqual(first.reportedDepartureFromDestination, departure)

        clock.now = date("2026-09-23T09:08:00Z")
        await tracker.refresh()
        XCTAssertEqual(tracker.previouslyTracked.first?.reportedArrival, arrival)
        XCTAssertTrue(tracker.previouslyTracked.first?.needsLiveDetails == true)

        clock.now = date("2026-09-23T09:36:00Z")
        await tracker.refresh()
        XCTAssertFalse(try XCTUnwrap(tracker.previouslyTracked.first).needsLiveDetails)
        await tracker.refresh()

        var shortened = later
        shortened.observedAt = date("2026-09-23T09:37:00Z")
        shortened.terminalActual = nil
        shortened.routeStops?.removeLast()
        tracker.receive(shortened)
        shortened.terminalActual = shortened.routeStops?.last?.actual
        tracker.receive(shortened)

        clock.now = date("2026-09-24T02:00:00Z")
        let restarted = TrainTracker(defaults: defaults, routeSettings: RouteSettings(), clock: { clock.now })
        XCTAssertTrue(restarted.journeys.isEmpty)
        let saved = try XCTUnwrap(restarted.previouslyTracked.first)
        XCTAssertEqual(saved.departure.observedAt, later.observedAt)
        XCTAssertEqual(saved.departure.scheduledArrival, scheduledArrival)
        XCTAssertEqual(saved.reportedArrival, arrival)
        XCTAssertEqual(saved.reportedDepartureFromDestination, departure)
        XCTAssertEqual(saved.departure.routeStops?.map(\.crs), ["SNO", "HUN", "PBO"])
        XCTAssertEqual(saved.departure.routePosition?.last.crs, "PBO")
    }

    @MainActor func testOpeningArchivedJourneyBackfillsTheFinalStopWhenDetailsAreAvailable() async throws {
        let name = "archive-test-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var saved = train("archived", scheduled: date("2026-09-22T08:12:00Z"))
        saved.serviceRID = "202609220001"
        saved.actualArrival = date("2026-09-22T09:02:00Z")
        saved.observedAt = date("2026-09-22T09:03:00Z")
        TrackingStore(defaults: defaults).saveJourneys(.init(archived: [TrackedJourney(departure: saved)]))

        var full = saved
        full.terminalActual = date("2026-09-22T09:30:00Z")
        full.observedAt = date("2026-09-22T09:31:00Z")
        full.routeStops = [RouteStop(id: "pbo", crs: "PBO", name: "Peterborough", scheduled: nil, expected: nil,
            actual: full.terminalActual, isCancelled: false, estimate: nil, isBoarding: false, isDestination: false)]
        let tracker = TrainTracker(defaults: defaults, provider: TrackingDetailsTestProvider(reports: [full]))
        await tracker.refreshArchivedJourney(id: saved.id)
        await tracker.refreshArchivedJourney(id: saved.id)

        let restored = try XCTUnwrap(TrainTracker(defaults: defaults).previouslyTracked.first)
        XCTAssertEqual(restored.reportedArrival, saved.actualArrival)
        XCTAssertEqual(restored.departure.routePosition?.last.crs, "PBO")
    }

    @MainActor func testOvernightTrainCanFinishAfterReset() {
        let name = "overnight-test-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let clock = ContinuousTestClock(date("2026-09-24T00:30:00Z"))
        let tracker = TrainTracker(defaults: defaults, routeSettings: RouteSettings(), clock: { clock.now })
        var service = train("overnight", scheduled: date("2026-09-24T00:40:00Z"))
        service.scheduledArrival = date("2026-09-24T01:30:00Z")
        tracker.toggle(service)
        clock.now = date("2026-09-24T01:00:00Z")
        tracker.pruneExpired()
        XCTAssertEqual(tracker.journeys.first?.id, service.id)
        clock.now = date("2026-09-24T01:35:00Z")
        service.observedAt = clock.now
        service.actualArrival = date("2026-09-24T01:33:00Z")
        tracker.receive(service)
        tracker.pruneExpired()
        XCTAssertTrue(tracker.journeys.first?.hasArrived == true)
    }
}

private final class ContinuousTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    var now: Date {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

private struct CompletedJourneyTestProvider: DepartureProviding {
    func snapshot(at date: Date) async throws -> DepartureSnapshot { throw RailAPIError.unavailable }
    func serviceDetails(for departure: Departure) async throws -> Departure {
        XCTFail("Completed journeys should not request live details")
        throw RailAPIError.unavailable
    }
}

private actor TrackingDetailsTestProvider: DepartureProviding {
    private var reports: [Departure]

    init(reports: [Departure]) { self.reports = reports }

    func snapshot(at date: Date) async throws -> DepartureSnapshot { throw RailAPIError.unavailable }

    func serviceDetails(for departure: Departure) async throws -> Departure {
        guard !reports.isEmpty else {
            XCTFail("The tracker should stop requesting details once the service is complete")
            throw RailAPIError.unavailable
        }
        return reports.removeFirst()
    }
}
