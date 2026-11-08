import XCTest
#if SWIFT_PACKAGE
@testable import TomsTrainsCore
#endif

final class DepartureTests: XCTestCase {
    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    func testSummaryPrioritisesCancelledDestinationBeforeBoarding() {
        var train = BoardFixtures.services(around: date("2026-09-22T07:00:00Z"))[0]
        train.arrivalStatus = "Cancelled"
        train.routeStops = nil
        let summary = ServiceSummary(service: train)
        XCTAssertEqual(summary.status, .disrupted("Not calling at \(train.callingAt.first!.shortName)"))
        XCTAssertTrue(summary.showsStatusPanel)
        XCTAssertNil(summary.position)
        XCTAssertNil(summary.expectedDeparture)
        XCTAssertNil(summary.expectedArrival)
    }

    func testSummaryDoesNotInventOriginFromPartialRoute() {
        var train = BoardFixtures.services(around: date("2026-09-22T07:00:00Z"))[0]
        train.serviceOrigin = nil
        XCTAssertEqual(ServiceSummary(service: train).title, "To \(train.destination)")
        train.serviceOrigin = .init(name: "Horsham", scheduledDeparture: date("2026-09-22T11:30:00Z"))
        XCTAssertEqual(ServiceSummary(service: train).title, "12:30 Horsham to \(train.destination)")
        var refresh = train
        refresh.serviceOrigin = .init(name: "Horsham", scheduledDeparture: nil)
        XCTAssertEqual(refresh.mergingEarlierStops(from: train).serviceOrigin, train.serviceOrigin)
        refresh.serviceOrigin = nil
        XCTAssertEqual(refresh.mergingEarlierStops(from: train).serviceOrigin, train.serviceOrigin)
    }

    func testSummaryHidesMatchingArrivalMinuteButRetainsRealDelay() {
        var train = BoardFixtures.services(around: date("2026-09-22T07:00:00Z"))[0]
        train.scheduledArrival = date("2026-09-22T08:00:00Z")
        train.expectedArrival = date("2026-09-22T08:00:10Z")
        XCTAssertNil(ServiceSummary(service: train).expectedArrival)
        train.expectedArrival = date("2026-09-22T08:05:00Z")
        XCTAssertEqual(ServiceSummary(service: train).expectedArrival, train.expectedArrival)
        train.actualArrival = train.expectedArrival
        XCTAssertNil(ServiceSummary(service: train).expectedArrival)
    }

    func testTrackingWaitsForConfirmedArrivalDespiteElapsedETA() {
        var train = BoardFixtures.services(around: date("2026-09-22T07:00:00Z"))[0]
        train.observedAt = date("2026-09-22T12:00:00Z")
        train.expectedArrival = date("2026-09-22T08:00:00Z")
        XCTAssertFalse(TrackedJourney(departure: train).hasArrived)
        train.actualArrival = date("2026-09-22T08:04:00Z")
        XCTAssertTrue(TrackedJourney(departure: train).hasArrived)
    }

    func testTrackingRejectsFutureActualArrivalAndCancelledDestination() {
        var train = BoardFixtures.services(around: date("2026-09-22T07:00:00Z"))[0]
        train.observedAt = date("2026-09-22T08:00:00Z")
        train.actualArrival = date("2026-09-22T08:01:00Z")
        XCTAssertFalse(TrackedJourney(departure: train).hasArrived)
        train.actualArrival = date("2026-09-22T07:59:00Z")
        train.arrivalStatus = "Cancelled"
        XCTAssertFalse(TrackedJourney(departure: train).hasArrived)
    }

    func testTrackingAcceptsDestinationCallAndIgnoresOtherActualStops() {
        var train = BoardFixtures.services(around: date("2026-09-22T07:00:00Z"))[0]
        train.observedAt = date("2026-09-22T08:00:00Z")
        func stop(destination: Bool, cancelled: Bool) -> RouteStop {
            RouteStop(id: "stop", crs: "KGX", name: "King’s Cross", scheduled: nil,
                expected: nil, actual: date("2026-09-22T07:59:00Z"), isCancelled: cancelled,
                estimate: nil, isBoarding: false, isDestination: destination)
        }
        train.routeStops = [stop(destination: false, cancelled: false)]
        XCTAssertFalse(TrackedJourney(departure: train).hasArrived)
        train.routeStops = [stop(destination: true, cancelled: true)]
        XCTAssertFalse(TrackedJourney(departure: train).hasArrived)
        train.routeStops = [stop(destination: true, cancelled: false)]
        XCTAssertTrue(TrackedJourney(departure: train).hasArrived)
    }

    func testTrackingEndsAfterReportedStopBeyondDestinationWithMissingArrival() throws {
        var train = BoardFixtures.services(around: date("2026-09-22T07:00:00Z"))[0]
        train.observedAt = date("2026-09-22T09:00:00Z")
        train.actualArrival = nil
        func stop(_ id: String, destination: Bool = false, actual: Date? = nil, expected: Date? = nil, cancelled: Bool = false) -> RouteStop {
            RouteStop(id: id, crs: id, name: id, scheduled: nil, expected: expected, actual: actual,
                isCancelled: cancelled, estimate: nil, isBoarding: false, isDestination: destination)
        }
        let reported = date("2026-09-22T08:50:00Z")
        train.routeStops = [stop("before", actual: reported), stop("destination", destination: true), stop("after")]
        XCTAssertFalse(TrackedJourney(departure: train).hasArrived, "Earlier stations do not prove arrival")
        train.routeStops![2] = stop("after", expected: reported)
        XCTAssertFalse(TrackedJourney(departure: train).hasArrived, "Elapsed forecasts do not prove arrival")
        train.routeStops![2].actual = date("2026-09-22T09:01:00Z")
        XCTAssertFalse(TrackedJourney(departure: train).hasArrived, "Future reports do not prove arrival")
        train.routeStops![2].actual = reported
        XCTAssertTrue(TrackedJourney(departure: train).hasArrived)
        let saved = try JSONEncoder().encode(TrackedJourney(departure: train))
        XCTAssertTrue(try JSONDecoder().decode(TrackedJourney.self, from: saved).hasArrived,
            "An already saved journey is removed on the next launch too")
        train.routeStops![2] = stop("after", actual: reported, cancelled: true)
        XCTAssertFalse(TrackedJourney(departure: train).hasArrived)
        train.routeStops![2] = stop("after")
        train.routeStops![2].actual = nil
        train.routeStops![2].actualDeparture = reported
        XCTAssertTrue(TrackedJourney(departure: train).hasArrived)
        train.routeStops![1] = stop("destination", destination: true, cancelled: true)
        XCTAssertFalse(TrackedJourney(departure: train).hasArrived, "A skipped destination was not reached")
    }

    func testTrackingRejectsOlderResponsesAndOtherServices() {
        let trains = BoardFixtures.services(around: date("2026-09-22T07:00:00Z"))
        var train = trains[0]
        train.observedAt = date("2026-09-22T08:00:00Z")
        let journey = TrackedJourney(departure: train)
        var stale = train
        stale.observedAt = date("2026-09-22T07:59:00Z")
        stale.actualArrival = stale.observedAt
        XCTAssertEqual(journey.accepting(stale), journey)
        XCTAssertEqual(journey.accepting(trains[1]), journey)
        var fresh = train
        fresh.observedAt = date("2026-09-22T08:01:00Z")
        fresh.actualArrival = fresh.observedAt
        XCTAssertTrue(journey.accepting(fresh).hasArrived)
    }

    func testTrackedJourneySurvivesPersistenceWithoutBoardFiltering() throws {
        let journey = TrackedJourney(departure: BoardFixtures.services(around: date("2026-09-22T07:00:00Z"))[0])
        let data = try JSONEncoder().encode([journey])
        XCTAssertEqual(try JSONDecoder().decode([TrackedJourney].self, from: data), [journey])
        XCTAssertFalse(journey.hasArrived)
    }




    func testEarlierPaginationRevealsOlderServicesAndStopsAtEnd() {
        let template = BoardFixtures.services(around: date("2026-09-22T07:00:00Z"))[0]
        let trains = (0..<19).map { index in
            Departure(id: "train-\(index)", origin: template.origin, destination: template.destination,
                callingAt: template.callingAt, scheduled: template.scheduled.addingTimeInterval(Double(index * 60)),
                status: .onTime, platform: nil, operatorName: template.operatorName, journeyMinutes: nil, disruptionReason: nil)
        }
        var pagination = EarlierDeparturePagination()
        XCTAssertTrue(pagination.visible(in: trains).isEmpty)
        pagination.revealMore()
        XCTAssertEqual(pagination.visible(in: trains).map(\.id), Array(trains.suffix(8)).map(\.id))
        XCTAssertTrue(pagination.hasMore(in: trains))
        pagination.revealMore()
        XCTAssertEqual(pagination.visible(in: trains).map(\.id), Array(trains.suffix(16)).map(\.id))
        XCTAssertTrue(pagination.hasMore(in: trains))
        pagination.revealMore()
        XCTAssertEqual(pagination.visible(in: trains), trains)
        XCTAssertFalse(pagination.hasMore(in: trains))
        XCTAssertFalse(pagination.hasMore(in: []))
        pagination = EarlierDeparturePagination()
        XCTAssertTrue(pagination.visible(in: trains).isEmpty)
    }


    func testEarlierServicesExcludeDelayedUpcomingAndOtherRoutes() {
        let now = date("2026-09-22T07:00:00Z")
        func train(_ id: String, minutesAgo: Double, status: ServiceStatus, origin: Station = .stNeots) -> Departure {
            Departure(id: id, origin: origin, destination: "London", callingAt: [.kingsCross],
                scheduled: now.addingTimeInterval(-minutesAgo * 60), status: status, platform: nil,
                operatorName: "Great Northern", journeyMinutes: 45, disruptionReason: nil)
        }
        let services = [train("past", minutesAgo: 10, status: .onTime),
            train("delayed", minutesAgo: 5, status: .delayed(minutes: 20)),
            train("old", minutesAgo: 121, status: .onTime),
            train("wrong", minutesAgo: 10, status: .onTime, origin: .stPancras),
            train("recent", minutesAgo: 2, status: .onTime)]
        let result = Departure.earlier(from: services + services, at: now, selection: RouteSettings().selection(at: now))
        XCTAssertEqual(result.map(\.id), ["past", "recent"])
    }


    func testTrackedStatusUsesDestinationInsteadOfHistoricalDepartureDelay() {
        let now = date("2026-09-22T07:00:00Z")
        var departure = Departure(id: "tracked", origin: .stNeots, destination: "London",
            callingAt: [.kingsCross], scheduled: now, status: .delayed(minutes: 12),
            platform: nil, operatorName: "Great Northern", journeyMinutes: 50, disruptionReason: nil,
            scheduledArrival: now.addingTimeInterval(3000), expectedArrival: now.addingTimeInterval(3000))
        XCTAssertEqual(departure.journeyStatus, .onTime)
        XCTAssertEqual(departure.status, .delayed(minutes: 12))
        departure.expectedArrival = now.addingTimeInterval(3420)
        XCTAssertEqual(departure.journeyStatus, .delayed(minutes: 7))
        departure.expectedArrival = now.addingTimeInterval(2880)
        XCTAssertEqual(departure.journeyStatus, .early(minutes: 2))
        departure.actualArrival = now.addingTimeInterval(3180)
        XCTAssertEqual(departure.journeyStatus, .delayed(minutes: 3))
        departure.arrivalStatus = "Cancelled"
        XCTAssertEqual(departure.journeyStatus, .disrupted("Not calling at \(Station.kingsCross.shortName)"))
    }

    func testTrackedStatusDoesNotUseOldDelayWhenArrivalIsUnknown() {
        let departure = Departure(id: "tracked", origin: .stNeots, destination: "London",
            callingAt: [.kingsCross], scheduled: date("2026-09-22T07:00:00Z"), status: .delayed(minutes: 12),
            platform: nil, operatorName: "Great Northern", journeyMinutes: 50, disruptionReason: nil)
        XCTAssertEqual(departure.journeyStatus, .unknown)
    }

    func testNoonSwitchUsesLondonTimeInSummerAndWinter() {
        XCTAssertEqual(JourneyDirection.at(date("2026-09-22T10:59:59Z")), .toLondon)
        XCTAssertEqual(JourneyDirection.at(date("2026-09-22T11:00:00Z")), .toStNeots)
        XCTAssertEqual(JourneyDirection.at(date("2026-12-22T11:59:59Z")), .toLondon)
        XCTAssertEqual(JourneyDirection.at(date("2026-12-22T12:00:00Z")), .toStNeots)
    }

    func testWeekendHasSameDirectionRules() {
        XCTAssertEqual(JourneyDirection.at(date("2026-09-26T08:00:00Z")), .toLondon)
        XCTAssertEqual(JourneyDirection.at(date("2026-09-26T14:00:00Z")), .toStNeots)
    }

    func testMorningIncludesThroughServices() {
        let now = date("2026-09-22T07:00:00Z")
        let board = Departure.board(from: BoardFixtures.services(around: now), at: now)
        XCTAssertFalse(board.isEmpty)
        XCTAssertTrue(board.allSatisfy { $0.origin == .stNeots })
        XCTAssertTrue(board.contains { $0.destination == "Horsham" && $0.callingAt.contains(.stPancras) })
    }

    func testReturnBoardMergesStationsAndKeepsCancellationsInTimetableOrder() {
        let now = date("2026-09-22T16:00:00Z")
        let board = Departure.board(from: BoardFixtures.services(around: now).reversed(), at: now, limit: 1000)
        XCTAssertEqual(Set(board.map(\.origin)), [.kingsCross, .stPancras])
        XCTAssertTrue(board.allSatisfy { $0.callingAt.contains(.stNeots) })
        let active = board.filter { $0.status != .cancelled }
        XCTAssertEqual(active.map(\.scheduled), active.map(\.scheduled).sorted())
        XCTAssertEqual(board.map(\.scheduled), board.map(\.scheduled).sorted())
    }

    func testDelayedServiceRemainsUntilExpectedDepartureAndCancelledHasNoExpectedTime() {
        let now = date("2026-09-22T16:22:00Z")
        let services = BoardFixtures.services(around: now)
        let board = Departure.board(from: services, at: now, limit: 1000)
        XCTAssertTrue(board.contains { $0.scheduled < now && ($0.expected ?? .distantPast) > now })
        let cancelled = board.first { $0.status == .cancelled }
        XCTAssertNotNil(cancelled)
        XCTAssertNil(cancelled?.expected)
        XCTAssertTrue(board.allSatisfy { ($0.expected ?? $0.scheduled) >= now })
    }

    func testThreeDepartureLimitAndRefreshKeepsStableServices() {
        let now = date("2026-09-22T16:00:00Z")
        let first = Departure.board(from: BoardFixtures.services(around: now), at: now, limit: 3)
        let later = now.addingTimeInterval(30)
        let refreshed = Departure.board(from: BoardFixtures.services(around: later), at: later, limit: 3)
        XCTAssertEqual(first.count, 3)
        XCTAssertEqual(first, refreshed)
    }

    func testAfterTwoAMRollsIntoMorningServices() {
        let now = date("2026-09-23T01:30:00Z")
        let board = Departure.board(from: BoardFixtures.services(around: now), at: now, limit: 3)
        XCTAssertEqual(board.count, 3)
        XCTAssertTrue(board.allSatisfy { $0.origin == .stNeots && $0.scheduled > now })
    }

    func testTimeDisplayAlwaysUsesLondonClock() {
        XCTAssertEqual(RailTime.string(date("2026-09-22T16:04:00Z")), "17:04")
        XCTAssertEqual(RailTime.string(date("2026-12-22T16:04:00Z")), "16:04")
    }

    func testRouteFilterRejectsTrainsNotCallingAtDestination() {
        let departure = Departure(id: "unrelated", origin: .kingsCross, destination: "Edinburgh",
            callingAt: [], scheduled: date("2026-09-22T16:04:00Z"), status: .onTime,
            platform: nil, operatorName: "Example", journeyMinutes: 45, disruptionReason: nil)
        XCTAssertFalse(JourneyDirection.toStNeots.includes(departure))
        XCTAssertFalse(JourneyDirection.toLondon.includes(departure))
    }
    func testCancelledTrainsFollowEarlierTimetableServicesWithoutReorderingLiveETAs() {
        let now = date("2026-09-22T16:00:00Z")
        func train(_ id: String, origin: Station, status: ServiceStatus, arrival: Int, eta: Int?) -> Departure {
            Departure(id: id, origin: origin, destination: "Peterborough", callingAt: [.stNeots],
                scheduled: now.addingTimeInterval(300), status: status, platform: nil,
                operatorName: "Example", journeyMinutes: nil, disruptionReason: nil,
                scheduledArrival: now.addingTimeInterval(Double(arrival * 60)),
                expectedArrival: eta.map { now.addingTimeInterval(Double($0 * 60)) })
        }
        let first = train("first", origin: .kingsCross, status: .onTime, arrival: 40, eta: 40)
        let cancelled = train("cancelled", origin: .stPancras, status: .cancelled, arrival: 45, eta: 90)
        let later = train("later", origin: .kingsCross, status: .delayed(minutes: 15), arrival: 35, eta: 50)
        var missedStop = train("missed-stop", origin: .stPancras, status: .onTime, arrival: 47, eta: nil)
        missedStop.arrivalStatus = "Cancelled"
        let board = Departure.board(from: [later, missedStop, cancelled, first], at: now)
        XCTAssertEqual(board.map(\.id), ["first", "later", "cancelled", "missed-stop"])
        XCTAssertEqual(Departure.board(from: [later, cancelled, first], at: now, limit: 2).map(\.id), ["first", "later"])
    }

    func testCancelled1146FollowsDelayed1116() {
        let now = date("2026-09-23T10:30:00Z")
        func train(_ id: String, departure: String, arrival: String, expected: String?, status: ServiceStatus) -> Departure {
            Departure(id: id, origin: .stPancras, destination: "Peterborough", callingAt: [.stNeots],
                scheduled: date("2026-09-23T" + departure + ":00Z"), status: status, platform: "B",
                operatorName: "Thameslink", journeyMinutes: nil, disruptionReason: nil,
                scheduledArrival: date("2026-09-23T" + arrival + ":00Z"),
                expectedArrival: expected.map { date("2026-09-23T" + $0 + ":00Z") })
        }
        let trains = [
            train("11:46", departure: "10:46", arrival: "11:44", expected: nil, status: .cancelled),
            train("11:16", departure: "10:16", arrival: "11:12", expected: "11:56", status: .delayed(minutes: 47)),
            train("12:16", departure: "11:16", arrival: "12:12", expected: nil, status: .cancelled),
            train("12:46", departure: "11:46", arrival: "12:43", expected: "12:52", status: .delayed(minutes: 14))
        ]
        let selection = RouteSelection(starts: [.kingsCross, .stPancras], ends: [.stNeots])
        XCTAssertEqual(Departure.board(from: trains, at: now, selection: selection).map(\.id), ["11:16", "11:46", "12:16", "12:46"])
        XCTAssertEqual(Departure.board(from: trains.reversed(), at: now, selection: selection).map(\.id), ["11:16", "11:46", "12:16", "12:46"])
    }

}
