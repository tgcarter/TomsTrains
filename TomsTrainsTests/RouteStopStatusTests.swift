import XCTest
#if SWIFT_PACKAGE
@testable import TomsTrainsCore
#endif

final class RouteStopStatusTests: XCTestCase {
    private let planned = Date(timeIntervalSince1970: 1_800_000_000)

    private func stop(offset: TimeInterval?, departed: Bool = true, cancelled: Bool = false) -> RouteStop {
        let actual = offset.map { planned.addingTimeInterval($0) }
        return RouteStop(id: "stop", crs: "SNO", name: "St Neots", scheduled: planned,
            expected: nil, actual: actual, isCancelled: cancelled, estimate: nil,
            isBoarding: false, isDestination: true, actualDeparture: departed ? actual : nil)
    }

    func testScheduledCaptionUsesArrivalBaselineAndMinutePrecision() {
        var arrival = stop(offset: 0, departed: false)
        arrival.scheduledArrival = planned
        arrival.scheduledDeparture = planned.addingTimeInterval(120)
        XCTAssertNil(arrival.differingScheduledTime)
        arrival.actual = planned.addingTimeInterval(180)
        XCTAssertEqual(arrival.differingScheduledTime, planned)
        XCTAssertEqual(arrival.timingStatus, .delayed(minutes: 3))
        XCTAssertNil(stop(offset: 10).differingScheduledTime)
        XCTAssertNil(stop(offset: 180, cancelled: true).differingScheduledTime)
    }

    func testForecastCaptionUsesForecastEvent() {
        let arrival = RouteStop(id: "forecast", crs: "SNO", name: "St Neots", scheduled: planned,
            expected: planned.addingTimeInterval(180), actual: nil, isCancelled: false,
            estimate: nil, isBoarding: false, isDestination: true,
            scheduledDeparture: planned.addingTimeInterval(120), scheduledArrival: planned,
            forecastEvent: .arrival)
        XCTAssertEqual(arrival.differingScheduledTime, planned)
        XCTAssertEqual(arrival.timingStatus, .delayed(minutes: 3))
    }

    func testDepartureTimingLabels() {
        XCTAssertEqual(stop(offset: 0).timingLabel, "Departed on time")
        XCTAssertEqual(stop(offset: 420).timingLabel, "Departed 7 min late")
        XCTAssertEqual(stop(offset: -120).timingLabel, "Departed 2 min early")
        XCTAssertEqual(stop(offset: 420).timingStatus, .delayed(minutes: 7))
    }

    func testArrivalReportsAreNotLabelledTomsTrains() {
        XCTAssertEqual(stop(offset: 180, departed: false).timingLabel, "Arrived 3 min late")
    }

    func testMissingAndCancelledReports() {
        XCTAssertEqual(stop(offset: nil).timingLabel, "Awaiting update")
        XCTAssertEqual(stop(offset: nil, cancelled: true).timingLabel, "Not calling")
        XCTAssertEqual(stop(offset: nil, cancelled: true).timingStatus, .cancelled)
    }
}
