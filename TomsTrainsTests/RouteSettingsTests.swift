import XCTest
#if SWIFT_PACKAGE
@testable import TomsTrainsCore
#endif

final class RouteSettingsTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    func testTravelDayCutoffUsesResetTimeAcrossMidnightAndClockChanges() {
        var settings = RouteSettings()
        XCTAssertEqual(settings.travelDayEnd(after: date("2026-09-22T22:00:00Z")), date("2026-09-23T01:00:00Z"))
        XCTAssertEqual(settings.travelDayEnd(after: date("2026-09-23T00:36:00Z")), date("2026-09-23T01:00:00Z"))
        XCTAssertEqual(settings.travelDayEnd(after: date("2026-09-23T01:00:00Z")), date("2026-09-24T01:00:00Z"))
        XCTAssertEqual(settings.travelDayEnd(after: date("2026-10-24T22:00:00Z")), date("2026-10-25T02:00:00Z"))
        XCTAssertEqual(settings.travelDayEnd(after: date("2026-03-28T22:00:00Z")), date("2026-03-29T01:00:00Z"))
        settings.resetMinutes = 3 * 60
        XCTAssertEqual(settings.travelDayEnd(after: date("2026-09-22T22:00:00Z")), date("2026-09-23T02:00:00Z"))
    }

    func testDefaultNoonAndTwoAMTransitionsInUKTime() {
        let settings = RouteSettings()
        XCTAssertFalse(settings.isReversed(at: date("2026-09-22T10:59:59Z")))
        XCTAssertTrue(settings.isReversed(at: date("2026-09-22T11:00:00Z")))
        XCTAssertTrue(settings.isReversed(at: date("2026-09-23T00:59:59Z")))
        XCTAssertFalse(settings.isReversed(at: date("2026-09-23T01:00:00Z")))
        XCTAssertTrue(settings.isReversed(at: date("2026-12-23T01:59:59Z")))
        XCTAssertFalse(settings.isReversed(at: date("2026-12-23T02:00:00Z")))
    }

    func testManualReversalExpiresAtNextSwapAndSurvivesPersistence() throws {
        var settings = RouteSettings()
        settings.reverse(at: date("2026-09-22T16:00:00Z"))
        XCTAssertFalse(settings.isReversed(at: date("2026-09-23T00:59:59Z")))
        XCTAssertEqual(settings.manualUntil, date("2026-09-23T01:00:00Z"))
        XCTAssertFalse(settings.isManual(at: date("2026-09-23T01:00:00Z")))
        let roundTrip = try JSONDecoder().decode(RouteSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(roundTrip, settings)
        settings.reverse(at: date("2026-09-23T07:00:00Z"))
        XCTAssertTrue(settings.isReversed(at: date("2026-09-23T08:00:00Z")))
        XCTAssertEqual(settings.manualUntil, date("2026-09-23T11:00:00Z"))
    }

    func testSecondReverseRestoresAutomaticSchedule() {
        let now = date("2026-09-22T15:00:00Z")
        var settings = RouteSettings()
        settings.reverse(at: now)
        XCTAssertTrue(settings.isManual(at: now))
        XCTAssertFalse(settings.isReversed(at: now))
        settings.reverse(at: now.addingTimeInterval(1))
        XCTAssertFalse(settings.isManual(at: now))
        XCTAssertNil(settings.manualUntil)
        XCTAssertTrue(settings.isReversed(at: now))
    }

    func testCustomTimesAndDSTBoundary() {
        var settings = RouteSettings()
        settings.swapMinutes = 15 * 60 + 30
        settings.resetMinutes = 3 * 60
        XCTAssertFalse(settings.isReversed(at: date("2026-09-22T14:29:59Z")))
        XCTAssertTrue(settings.isReversed(at: date("2026-09-22T14:30:00Z")))
        XCTAssertEqual(RouteSettings().nextTransition(after: date("2026-03-29T00:00:00Z")), date("2026-03-29T01:00:00Z"))
        XCTAssertEqual(RouteSettings().nextTransition(after: date("2026-10-25T00:00:00Z")), date("2026-10-25T02:00:00Z"))
    }

    func testEditedRouteAndReversalRejectCachedBoard() {
        let now = date("2026-09-22T15:00:00Z")
        var settings = RouteSettings()
        let snapshot = DepartureSnapshot(fetchedAt: now, departures: [], routeKey: settings.selection(at: now).key)
        XCTAssertTrue(snapshot.isFresh(at: now, settings: settings))
        settings.reverse(at: now)
        XCTAssertFalse(snapshot.isFresh(at: now, settings: settings))
        settings.resumeAutomatic()
        settings.starts = [Station(rawValue: "CBG")!]
        XCTAssertFalse(snapshot.isFresh(at: now, settings: settings))
    }

    func testRouteValidationAndStationDirectoryDecode() throws {
        var settings = RouteSettings()
        settings.starts = []
        XCTAssertFalse(settings.isValid)
        settings.starts = [.kingsCross]
        XCTAssertFalse(settings.isValid)
        settings.starts = [.stNeots]
        settings.resetMinutes = settings.swapMinutes
        XCTAssertFalse(settings.isValid)
        let data = Data(#"{"StationList":[{"crs":"CBG","Value":"Cambridge"},{"crs":"CBG","Value":"Duplicate"},{"crs":"INVALID","Value":"Invalid"},{"crs":"EMP","Value":" "}]}"#.utf8)
        let stations = try StationDirectory.decode(data)
        XCTAssertEqual(stations.count, 1)
        XCTAssertEqual(stations.first?.name, "Cambridge")
        XCTAssertEqual(try JSONDecoder().decode([Station].self, from: JSONEncoder().encode(stations)).first?.name, "Cambridge")
        XCTAssertEqual(try JSONDecoder().decode(Station.self, from: Data("\"SNO\"".utf8)), .stNeots)
        XCTAssertThrowsError(try StationDirectory.decode(Data(#"{"StationList":[]}"#.utf8)))
    }


}
