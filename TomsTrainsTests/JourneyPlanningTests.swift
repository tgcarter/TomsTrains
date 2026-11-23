import XCTest
#if SWIFT_PACKAGE
@testable import TomsTrainsCore
#endif

final class JourneyPlanningTests: XCTestCase {
    func testJourneyRequestUsesExactStationIDsAndBritishSummerTime() throws {
        let time = try XCTUnwrap(RailDate.timestamp("2026-07-10T18:00:00+01:00"))
        for mode in JourneySearchMode.allCases {
            let request = JourneyPlanningProvider.request(from: "910GSTNEOTS", to: "910GCAMBDGE", mode: mode, time: time)
            let url = try XCTUnwrap(request.url)
            let parameters = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            let values = Dictionary(uniqueKeysWithValues: parameters.map { ($0.name, $0.value) })
            XCTAssertEqual(values["fromPlace"], "gb-great-britain_910GSTNEOTS")
            XCTAssertEqual(values["toPlace"], "gb-great-britain_910GCAMBDGE")
            XCTAssertEqual(values["time"], "2026-07-10T17:00:00Z")
            XCTAssertEqual(values["arriveBy"], mode == .arriveBy ? "true" : "false")
            XCTAssertEqual(values["transitModes"], "HIGHSPEED_RAIL,LONG_DISTANCE,NIGHT_RAIL,REGIONAL_RAIL,SUBURBAN")
        }
    }

    func testJourneyWithTwoTrainLegsAndWalkingTransfer() throws {
        let time = try XCTUnwrap(RailDate.timestamp("2026-11-16T09:30:00Z"))
        let journeys = try JourneyPlanningProvider.decode(fixture, mode: .arriveBy, time: time)
        let first = try XCTUnwrap(journeys.first)

        XCTAssertEqual(journeys.count, 1)
        XCTAssertEqual(first.changes, 1)
        XCTAssertEqual(first.duration, 4800)
        XCTAssertEqual(first.legs.filter(\.isTrain).map(\.agencyName), ["Thameslink", "CrossCountry"])
        XCTAssertEqual(first.legs.filter(\.isTrain).map(\.operatorCode), ["TL", "XC"])
        XCTAssertFalse(first.legs[1].changesStationOnFoot)
    }

    func testJourneysMustRespectRequestedDepartureAndArrivalTimes() throws {
        let time = try XCTUnwrap(RailDate.timestamp("2026-11-16T08:40:00Z"))
        XCTAssertTrue(try JourneyPlanningProvider.decode(fixture, mode: .arriveBy, time: time).isEmpty)
        XCTAssertTrue(try JourneyPlanningProvider.decode(fixture, mode: .departAt, time: time).isEmpty)
    }

    func testWestMidlandsTrainsUsesTheJointOperatorCodeWhenTheBrandIsUnknown() {
        let time = Date(timeIntervalSince1970: 0)
        let origin = PlannedJourney.Leg.Stop(name: "London Euston", stopId: nil, parentId: nil, stopCode: "EUS", cancelled: nil)
        let destination = PlannedJourney.Leg.Stop(name: "Milton Keynes Central", stopId: nil, parentId: nil, stopCode: "MKC", cancelled: nil)
        let routes: [(name: String?, expectedCode: String)] = [(nil, "LM"), ("LNR", "LN"), ("WMR", "WM")]

        for route in routes {
            let leg = PlannedJourney.Leg(
                mode: "REGIONAL_RAIL", from: origin, to: destination, startTime: time, endTime: time,
                scheduledStartTime: nil, agencyName: "West Midlands Trains", agencyId: "=LM",
                routeShortName: route.name, interlineWithPreviousLeg: nil, cancelled: nil
            )
            XCTAssertEqual(leg.operatorCode, route.expectedCode)
        }
    }

    func testBookingUsesTheSelectedTrainsScheduledDepartureInBritishSummerTime() throws {
        let data = Data("""
            {"itineraries": [{
              "startTime": "2026-07-10T23:18:00Z", "endTime": "2026-07-11T00:03:00Z",
              "legs": [{
                "mode": "REGIONAL_RAIL", "agencyId": "=LM", "routeShortName": "LNR",
                "startTime": "2026-07-10T23:18:00Z", "endTime": "2026-07-11T00:03:00Z",
                "scheduledStartTime": "2026-07-10T23:05:00Z",
                "from": {"name": "London Euston"}, "to": {"name": "Milton Keynes Central"}
              }]
            }]}
            """.utf8)
        let time = try XCTUnwrap(RailDate.timestamp("2026-07-10T23:00:00Z"))
        let journey = try XCTUnwrap(JourneyPlanningProvider.decode(data, mode: .departAt, time: time).first)
        let origin = try XCTUnwrap(Station(rawValue: "EUS"))
        let destination = try XCTUnwrap(Station(rawValue: "MKC"))
        let url = journey.bookingURL(from: origin, to: destination)
        let parameters = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: parameters.map { ($0.name, $0.value) })

        XCTAssertEqual(journey.legs.first?.operatorCode, "LN")
        XCTAssertEqual(url.host, "railsmartr.co.uk")
        XCTAssertEqual(url.path, "/booking/fares")
        XCTAssertEqual(values["origin"], "EUS")
        XCTAssertEqual(values["destination"], "MKC")
        XCTAssertEqual(values["outwardDate"], "2026-07-11")
        XCTAssertEqual(values["outwardDepartAt"], "00:05")
        XCTAssertEqual(values["useSplits"], "true")
    }

    private let fixture = Data("""
        {"itineraries": [{
          "startTime": "2026-11-16T08:00:00Z", "endTime": "2026-11-16T09:20:00Z",
          "legs": [{
            "mode": "SUBURBAN", "agencyName": "Thameslink", "agencyId": "=TL",
            "startTime": "2026-11-16T08:00:00Z", "endTime": "2026-11-16T08:25:00Z",
            "from": {"name": "St Neots", "stopCode": "SNO"},
            "to": {"name": "Peterborough", "stopCode": "PBO"}
          }, {
            "mode": "WALK",
            "startTime": "2026-11-16T08:25:00Z", "endTime": "2026-11-16T08:30:00Z",
            "from": {"name": "Peterborough", "stopId": "pbo2", "parentId": "pbo"},
            "to": {"name": "Peterborough", "stopId": "pbo6", "parentId": "pbo"}
          }, {
            "mode": "LONG_DISTANCE", "agencyName": "CrossCountry", "agencyId": "=XC",
            "startTime": "2026-11-16T08:35:00Z", "endTime": "2026-11-16T09:20:00Z",
            "from": {"name": "Peterborough", "stopCode": "PBO"},
            "to": {"name": "Cambridge", "stopCode": "CBG"}
          }]
        }]}
        """.utf8)
}
