import XCTest
#if SWIFT_PACKAGE
@testable import TomsTrainsCore
#endif

final class AutoTrackingTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
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
        let tracker = TrainTracker(defaults: defaults)
        tracker.toggle(first)
        tracker.toggle(second)
        XCTAssertEqual(tracker.journeys.map(\.id), ["first", "second"])
        XCTAssertEqual(TrainTracker(defaults: defaults).journeys.map(\.id), ["first", "second"])
        defaults.set(try JSONEncoder().encode([TrackedJourney(departure: first), TrackedJourney(departure: second)]), forKey: "trackedJourneys.v1")
        XCTAssertEqual(TrainTracker(defaults: defaults).journeys.map(\.id), ["first", "second"], "Preserve all saved trains")
    }

    @MainActor func testAutomaticSelectionAndManualStopPersistUntilNextDay() async {
        let name = "auto-test-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let now = date("2026-09-23T07:00:00Z")
        let today = train("today", scheduled: date("2026-09-23T08:12:00Z"))
        let tracker = TrainTracker(defaults: defaults)
        tracker.configureAutomatic(AutoTrackingRule(departure: today))
        await tracker.autoTrack(at: now, lookup: { _, _ in today })
        XCTAssertEqual(tracker.journeys.map(\.id), ["today"])
        tracker.toggle(today)
        let restarted = TrainTracker(defaults: defaults)
        await restarted.autoTrack(at: now.addingTimeInterval(120), lookup: { _, _ in
            XCTFail("Manual stop must survive restart"); return today
        })
        XCTAssertTrue(restarted.journeys.isEmpty)
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
        let tracker = TrainTracker(defaults: defaults)
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
        let tracker = TrainTracker(defaults: defaults)
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

    @MainActor func testCompletedServiceUntracksAfterDestinationCancellation() {
        let name = "complete-test-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let tracker = TrainTracker(defaults: defaults)
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
        XCTAssertTrue(tracker.journeys.isEmpty)
        XCTAssertTrue(TrainTracker(defaults: defaults).journeys.isEmpty)
    }
    @MainActor func testMultipleRulesPersistAndContinueAfterLookupFailure() async throws {
        let name = "multi-test-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let now = date("2026-09-23T07:00:00Z")
        let first = train("first", scheduled: date("2026-09-23T08:12:00Z"))
        let second = train("second", scheduled: date("2026-09-23T09:12:00Z"))
        let firstRule = AutoTrackingRule(departure: first)
        let tracker = TrainTracker(defaults: defaults)
        XCTAssertTrue(tracker.autoRules.isEmpty)
        tracker.configureAutomatic(firstRule)
        let other = AutoTrackingRule(departure: second)
        tracker.configureAutomatic(other)
        XCTAssertEqual(TrainTracker(defaults: defaults).autoRules.count, 2)
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
        let restarted = TrainTracker(defaults: defaults)
        XCTAssertEqual(restarted.autoRules.map(\.id), [other.id])
        XCTAssertEqual(restarted.journeys.map(\.id), ["second"])
    }

    @MainActor func testCompletingOneTrainKeepsOthersAndRuleEditsAreIndependent() {
        let name = "multi-test-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var first = train("first", scheduled: date("2026-09-23T08:12:00Z"))
        let second = train("second", scheduled: date("2026-09-23T09:12:00Z"))
        let tracker = TrainTracker(defaults: defaults)
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
        XCTAssertEqual(tracker.journeys.map(\.id), ["second"])
        XCTAssertEqual(TrainTracker(defaults: defaults).journeys.map(\.id), ["second"])
    }

}
