import XCTest
#if SWIFT_PACKAGE
@testable import TomsTrainsCore
#endif

private actor BoardFixtureProvider: DepartureProviding {
    let services: [Departure]
    var requestedLimits: [Int] = []
    init(services: [Departure]) { self.services = services }

    func snapshot(at date: Date) async throws -> DepartureSnapshot {
        try await snapshot(at: date, tomorrow: false, limit: 8)
    }
    func snapshot(at date: Date, tomorrow: Bool, limit: Int) async throws -> DepartureSnapshot {
        requestedLimits.append(limit)
        let settings = RouteSettings()
        let boundary = settings.travelDayEnd(after: date)
        let start = tomorrow ? boundary : date
        let end = tomorrow ? settings.travelDayEnd(after: boundary) : boundary
        let matching = services.filter { $0.scheduled >= start && $0.scheduled < end }
        return DepartureSnapshot(fetchedAt: date, departures: Array(matching.prefix(limit)),
            routeKey: settings.selection(at: date).key, hasLaterDepartures: matching.count > limit)
    }
    func earlierDepartures(at date: Date, before: Date?) async throws -> [Departure] {
        let end = before ?? date
        let start = NationalRailProvider.historyStart(before: end, now: date)
        return services.filter { $0.scheduled >= start && $0.scheduled < end }
    }
}

private actor SuspendedBoardProvider: DepartureProviding {
    private var response: CheckedContinuation<DepartureSnapshot, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func snapshot(at date: Date) async throws -> DepartureSnapshot {
        await withCheckedContinuation { continuation in
            response = continuation
            started?.resume()
            started = nil
        }
    }
    func waitForRequest() async {
        if response != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish(at date: Date) {
        response?.resume(returning: DepartureSnapshot(fetchedAt: date, departures: []))
        response = nil
    }
}

final class DepartureBoardTests: XCTestCase {
    private func date(_ value: String) -> Date { DarwinDecoder.time(value)! }
    private func services(start: Date, count: Int) -> [Departure] {
        (0..<count).map { index in
            Departure(id: "\(start.timeIntervalSince1970)-\(index)", origin: index.isMultiple(of: 2) ? .kingsCross : .stPancras,
                destination: "Peterborough", callingAt: [.stNeots], scheduled: start.addingTimeInterval(Double(index * 600)),
                status: .onTime, platform: "1", operatorName: "Example", journeyMinutes: 50, disruptionReason: nil)
        }
    }

    @MainActor func testLaterPagesPersistAcrossRefreshAndResetWithRoute() async {
        let now = date("2026-09-22T16:00:00")
        let provider = BoardFixtureProvider(services: services(start: now, count: 24))
        let board = DepartureBoard(provider: provider, settings: RouteSettings(), clock: { now })
        await board.refresh()
        XCTAssertEqual(board.departures.count, 8)
        await board.loadLater()
        XCTAssertEqual(board.departures.count, 16)
        await board.refresh()
        XCTAssertEqual(board.departures.count, 16)
        await board.loadLater()
        XCTAssertEqual(board.departures.count, 24)
        XCTAssertFalse(board.canLoadLater)
        XCTAssertTrue(board.canShowTomorrow)
        var reversed = RouteSettings()
        reversed.reverse(at: now)
        await board.refresh(settings: reversed)
        let limits = await provider.requestedLimits
        XCTAssertEqual(limits.last, 8)
    }

    @MainActor func testTomorrowUsesInjectedProviderAndIndependentPageSize() async {
        let now = date("2026-09-22T22:00:00")
        let provider = BoardFixtureProvider(services: services(start: date("2026-09-23T05:00:00"), count: 20))
        let board = DepartureBoard(provider: provider, settings: RouteSettings(), clock: { now })
        await board.refresh()
        XCTAssertTrue(board.canShowTomorrow)
        await board.loadTomorrow()
        XCTAssertEqual(board.tomorrowDepartures.count, 8)
        await board.loadLaterTomorrow()
        XCTAssertEqual(board.tomorrowDepartures.count, 16)
        XCTAssertTrue(board.departures.isEmpty)
        await board.refresh()
        XCTAssertEqual(board.tomorrowDepartures.count, 16)
    }

    @MainActor func testEarlierKeepsPreviousEveningAfterMidnightAndLoadsEight() async {
        let now = date("2026-09-23T00:30:00")
        let provider = BoardFixtureProvider(services: services(start: date("2026-09-22T21:00:00"), count: 16))
        let board = DepartureBoard(provider: provider, settings: RouteSettings(), clock: { now })
        await board.refresh()
        await board.loadEarlier()
        XCTAssertEqual(board.visibleEarlier.count, 8)
        XCTAssertTrue(board.visibleEarlier.allSatisfy { $0.scheduled < self.date("2026-09-23T00:00:00") })
        await board.loadEarlier()
        XCTAssertEqual(board.visibleEarlier.count, 16)
        XCTAssertEqual(board.visibleEarlier.map(\.scheduled), board.visibleEarlier.map(\.scheduled).sorted())
    }
    @MainActor func testManualRefreshClearsExpandedResultsAndRestartsPagination() async {
        let now = date("2026-09-22T16:00:00")
        let all = services(start: date("2026-09-22T13:00:00"), count: 16)
            + services(start: now, count: 24)
            + services(start: date("2026-09-23T05:00:00"), count: 20)
        let provider = BoardFixtureProvider(services: all)
        let board = DepartureBoard(provider: provider, settings: RouteSettings(), clock: { now })
        await board.refresh()
        await board.loadEarlier()
        let firstEarlierIDs = board.visibleEarlier.map(\.id)
        await board.loadEarlier()
        await board.loadLater()
        await board.loadTomorrow()
        await board.loadLaterTomorrow()
        XCTAssertEqual(board.visibleEarlier.count, 16)
        XCTAssertEqual(board.departures.count, 16)
        XCTAssertEqual(board.tomorrowDepartures.count, 16)

        await board.refresh(resetPagination: true)
        XCTAssertEqual(board.departures.count, 8)
        XCTAssertTrue(board.earlier.isEmpty)
        XCTAssertTrue(board.visibleEarlier.isEmpty)
        XCTAssertFalse(board.hasLoadedEarlier)
        XCTAssertFalse(board.showsTomorrow)
        XCTAssertNil(board.tomorrowSnapshot)
        XCTAssertNil(board.earlierError)
        XCTAssertNil(board.tomorrowError)
        XCTAssertTrue(board.canLoadEarlier)
        XCTAssertTrue(board.canLoadLater)
        let limits = await provider.requestedLimits
        XCTAssertEqual(limits.last, 8)

        await board.loadEarlier()
        XCTAssertEqual(board.visibleEarlier.map(\.id), firstEarlierIDs)
        await board.loadLater()
        XCTAssertEqual(board.departures.count, 16)
        await board.loadTomorrow()
        XCTAssertEqual(board.tomorrowDepartures.count, 8)
    }

    @MainActor func testEmptyBoardShowsLoadingUntilRequestFinishes() async {
        let now = date("2026-09-22T16:00:00")
        let provider = SuspendedBoardProvider()
        let board = DepartureBoard(provider: provider, settings: RouteSettings(), clock: { now })
        XCTAssertTrue(board.showsInitialLoading)
        let initial = Task { await board.refresh() }
        await provider.waitForRequest()
        XCTAssertTrue(board.showsInitialLoading)
        await provider.finish(at: now)
        await initial.value
        XCTAssertFalse(board.showsInitialLoading)
        XCTAssertTrue(board.departures.isEmpty)
        let refresh = Task { await board.refresh() }
        await provider.waitForRequest()
        XCTAssertTrue(board.showsInitialLoading, "A prior empty response must not flash an empty message while refreshing")
        await provider.finish(at: now)
        await refresh.value
        XCTAssertFalse(board.showsInitialLoading)
    }
}
