import XCTest
#if SWIFT_PACKAGE
@testable import TomsTrainsCore
#endif

final class NationalRailTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-09-22T14:50:00Z")!
    private func date(_ value: String) -> Date { DarwinDecoder.time(value)! }

    private static func board(origin: String = "STP", rid: String = "202609220001",
                              serviceChanges: [String: Any] = [:], destinationChanges: [String: Any] = [:],
                              boardChanges: [String: Any] = [:]) -> Data {
        var stop: [String: Any] = ["crs": "SNO", "locationName": "St Neots", "sta": "2026-09-22T15:42:00",
            "std": "2026-09-22T15:43:00", "ata": "2026-09-22T15:44:00", "atd": "2026-09-22T15:45:00",
            "arrivalType": "Actual", "departureType": "Actual", "platform": "1", "platformIsHidden": false]
        stop.merge(destinationChanges) { _, new in new }
        var service: [String: Any] = ["rid": rid, "std": "2026-09-22T14:46:00", "atd": "2026-09-22T14:49:00",
            "departureType": "Actual", "platform": "B", "platformIsHidden": false,
            "operator": "Thameslink", "operatorCode": "TL", "isPassengerService": true,
            "destination": [["locationName": "Peterborough"]],
            "previousLocations": [["crs": "LBG", "locationName": "London Bridge", "std": "2026-09-22T14:30:00", "atd": "2026-09-22T14:31:00", "departureType": "Actual", "platform": "5"]],
            "subsequentLocations": [stop, ["crs": "HUN", "locationName": "Huntingdon", "sta": "2026-09-22T15:50:00", "eta": "2026-09-22T15:52:00", "arrivalType": "Forecast", "platform": "3"]]]
        service.merge(serviceChanges) { _, new in new }
        var board: [String: Any] = ["crs": origin, "generatedAt": "2026-09-22T15:50:00+01:00", "trainServices": [service]]
        board.merge(boardChanges) { _, new in new }
        return try! JSONSerialization.data(withJSONObject: board)
    }

    private func decode(_ data: Data) throws -> Departure {
        try XCTUnwrap(DarwinDecoder.decode(data, origin: .stPancras, destination: .stNeots, now: now).departures.first)
    }

    func testBoardDoesNotMistakePreviousLocationForServiceOrigin() throws {
        let partial = try decode(Self.board())
        XCTAssertNil(partial.serviceOrigin)
        XCTAssertEqual(ServiceSummary(service: partial).title, "To Peterborough")
        let declared = try decode(Self.board(serviceChanges: [
            "origin": [["crs": "HRH", "locationName": "Horsham"]]
        ]))
        XCTAssertEqual(declared.serviceOrigin?.name, "Horsham")
        XCTAssertNil(declared.serviceOrigin?.scheduledDeparture)
        XCTAssertEqual(ServiceSummary(service: declared).title, "Horsham to Peterborough")
    }

    func testCompleteRoutePreservesOriginEvenWhenDisplaySuppressesIt() throws {
        let locations: [[String: Any]] = [
            ["crs": "HRH", "locationName": "Horsham", "std": "2026-09-22T12:30:00", "serviceIsSupressed": true],
            ["crs": "STP", "locationName": "St Pancras", "std": "2026-09-22T14:46:00"],
            ["crs": "SNO", "locationName": "St Neots", "sta": "2026-09-22T15:42:00"],
            ["crs": "PBO", "locationName": "Peterborough", "sta": "2026-09-22T16:00:00"]
        ]
        let train = try XCTUnwrap(DarwinDecoder.departure(service: [:],
            locations: locations, boarding: 1, destination: .stNeots, observed: now, id: "full", hasCompleteRoute: true))
        XCTAssertEqual(train.routeStops?.first?.crs, "STP")
        XCTAssertEqual(ServiceSummary(service: train).title, "12:30 Horsham to Peterborough")
        let restored = try JSONDecoder().decode(Departure.self, from: JSONEncoder().encode(train))
        XCTAssertEqual(restored.serviceOrigin, train.serviceOrigin)
    }

    func testServiceTitleIgnoresOperationalLocationsAfterFinalPassengerStop() throws {
        for cancelled in [false, true] {
            let locations: [[String: Any]] = [
                ["crs": "HRH", "locationName": "Horsham", "std": "2026-09-22T12:30:00"],
                ["crs": "STP", "locationName": "St Pancras", "std": "2026-09-22T14:46:00"],
                ["crs": "SNO", "locationName": "St Neots", "sta": "2026-09-22T15:42:00"],
                ["crs": "PBO", "locationName": "Peterborough", "sta": "2026-09-22T16:00:00",
                 "isCancelled": cancelled, "isPass": cancelled],
                ["locationName": "Operational depot", "isOperational": true, "sta": "2026-09-22T16:10:00"]
            ]
            let train = try XCTUnwrap(DarwinDecoder.departure(service: [:], locations: locations,
                boarding: 1, destination: .stNeots, observed: now, id: "depot", hasCompleteRoute: true))
            XCTAssertEqual(train.destination, "Peterborough")
            XCTAssertEqual(ServiceSummary(service: train).title, "12:30 Horsham to Peterborough")
        }
    }

    func testActualDarwinFieldsAndPlatformsAtAllStops() throws {
        let train = try decode(Self.board())
        XCTAssertEqual(train.serviceRID, "202609220001")
        XCTAssertEqual(train.id, "STP-202609220001")
        XCTAssertEqual(train.platform, "B")
        XCTAssertEqual(train.status, .delayed(minutes: 3))
        XCTAssertEqual(train.journeyStatus, .delayed(minutes: 2))
        XCTAssertEqual(train.actualArrival, date("2026-09-22T15:44:00"))
        XCTAssertEqual(train.routeStops?.map(\.crs), ["LBG", "STP", "SNO", "HUN"])
        XCTAssertEqual(train.routeStops?.map(\.platform), ["5", "B", "1", "3"])
        XCTAssertEqual(train.routeStops?.first(where: \.isDestination)?.timingLabel, "Departed 2 min late")
        XCTAssertTrue(TrackedJourney(departure: train).hasArrived)
        XCTAssertTrue(train.isBetweenStations)
    }

    func testForecastAndNoLogNeverBecomeActualReports() throws {
        for type in ["Forecast", "NoLog", "Delayed"] {
            let train = try decode(Self.board(serviceChanges: ["departureType": type],
                destinationChanges: ["arrivalType": type, "departureType": type]))
            XCTAssertNil(train.actualArrival)
            XCTAssertNil(train.routeStops?.first(where: \.isDestination)?.actualDeparture)
            XCTAssertFalse(TrackedJourney(departure: train).hasArrived)
        }
    }

    func testFutureActualReportDoesNotConfirmArrival() throws {
        let train = try decode(Self.board(destinationChanges: ["ata": "2026-09-22T16:00:00", "atd": "2026-09-22T16:01:00"]))
        XCTAssertNil(train.actualArrival)
        XCTAssertFalse(TrackedJourney(departure: train).hasArrived)
    }

    func testCancelledAndPassingDestination() throws {
        let cancelled = try decode(Self.board(destinationChanges: ["isCancelled": true, "isPass": true]))
        XCTAssertEqual(cancelled.arrivalStatus, "Cancelled")
        XCTAssertNil(cancelled.actualArrival)
        XCTAssertFalse(TrackedJourney(departure: cancelled).hasArrived)
        XCTAssertEqual(cancelled.routeStops?.first(where: \.isDestination)?.timingLabel, "Not calling")
        let pass = try DarwinDecoder.decode(Self.board(destinationChanges: ["isPass": true]), origin: .stPancras, destination: .stNeots, now: now)
        XCTAssertTrue(pass.departures.isEmpty)
    }

    func testCancelledPassingAndOperationalPointsAreNotPassengerStops() throws {
        var object = try JSONSerialization.jsonObject(with: Self.board()) as! [String: Any]
        var services = object["trainServices"] as! [[String: Any]]
        var stops = services[0]["subsequentLocations"] as! [[String: Any]]
        stops.insert(["crs": "HRN", "locationName": "Hornsey", "isPass": true,
            "isCancelled": true, "std": "2026-09-22T15:00:00"], at: 0)
        stops.insert(["crs": "XXX", "locationName": "Operational point", "isOperational": true,
            "isCancelled": true, "sta": "2026-09-22T15:01:00"], at: 1)
        services[0]["subsequentLocations"] = stops
        object["trainServices"] = services
        let payload = try JSONSerialization.data(withJSONObject: object)
        let train = try decode(payload)
        XCTAssertEqual(train.routeStops?.map(\.crs), ["LBG", "STP", "SNO", "HUN"])
        let passingDestination = try DarwinDecoder.decode(payload, origin: .stPancras,
            destination: Station(rawValue: "HRN")!, now: now)
        XCTAssertTrue(passingDestination.departures.isEmpty)
    }

    func testUnconfirmedHiddenPlatformsAndSuppressedServicesStayHiddenAfterRefresh() throws {
        let old = try decode(Self.board())
        let hidden = try decode(Self.board(serviceChanges: ["platformIsHidden": true, "departureType": "Forecast"], destinationChanges: ["platformIsHidden": true, "departureType": "Forecast", "arrivalType": "Forecast"]))
        XCTAssertNil(hidden.platform)
        XCTAssertNil(hidden.routeStops?.first(where: \.isDestination)?.platform)
        XCTAssertNil(hidden.retainingHistoricalReport(from: old).platform)
        let wholeBoard = try decode(Self.board(serviceChanges: ["departureType": "Forecast"], boardChanges: ["platformsAreHidden": true]))
        XCTAssertNil(wholeBoard.platform)
        let suppressed = try DarwinDecoder.decode(Self.board(serviceChanges: ["serviceIsSupressed": true, "departureType": "Forecast"]), origin: .stPancras, destination: .stNeots, now: now)
        XCTAssertTrue(suppressed.departures.isEmpty)
    }

    func testCompletedCallsRetainHistoricalPlatformWhenDisplayHidden() throws {
        let data = Self.board(origin: "KGX", serviceChanges: ["platform": "8", "platformIsHidden": true, "serviceIsSupressed": true],
            destinationChanges: ["platformIsHidden": true])
        let train = try XCTUnwrap(DarwinDecoder.decode(data, origin: .kingsCross, destination: .stNeots, now: now).departures.first)
        XCTAssertEqual(train.platform, "8")
        XCTAssertEqual(train.routeStops?.first(where: \.isBoarding)?.platform, "8")
        XCTAssertEqual(train.routeStops?.first(where: \.isDestination)?.platform, "1")
    }

    func testRouteProgressContinuesPastDestinationAndIdentifiesCompletedService() throws {
        var train = try decode(Self.board())
        let destination = try XCTUnwrap(train.routeStops?.firstIndex(where: \.isDestination))
        XCTAssertEqual(train.routeProgress, Double(destination) + 0.5)
        XCTAssertTrue(train.isBetweenStations)
        XCTAssertFalse(train.isServiceComplete)
        let final = try XCTUnwrap(train.routeStops?.indices.last)
        train.routeStops?[final].actual = now
        train.terminalActual = now
        XCTAssertEqual(train.routeProgress, Double(final))
        XCTAssertTrue(train.isServiceComplete)
        XCTAssertFalse(train.isBetweenStations)
        train.routeStops?[final].actual = now.addingTimeInterval(60)
        train.terminalActual = now.addingTimeInterval(60)
        XCTAssertFalse(train.isServiceComplete)
        XCTAssertEqual(train.routeProgress, Double(destination) + 0.5, "Future reports must not advance the graphic")
    }

    func testLondonTimesIncludeDateAndRespectSummerWinterAndMidnight() {
        XCTAssertEqual(date("2026-09-22T15:44:00"), date("2026-09-22T14:44:00Z"))
        XCTAssertEqual(date("2026-12-22T15:44:00"), date("2026-12-22T15:44:00Z"))
        XCTAssertEqual(date("2026-09-23T00:05:00").timeIntervalSince(date("2026-09-22T23:55:00")), 600)
        XCTAssertNil(DarwinDecoder.time("On time"))
    }

    func testEarlierHistoryExtendsBeyondTwoHoursButNotBeforeTravelDay() throws {
        let train = try decode(Self.board())
        let later = date("2026-09-22T23:00:00")
        let selection = RouteSelection(starts: [.stPancras], ends: [.stNeots])
        XCTAssertTrue(Departure.earlier(from: [train], at: later, selection: selection).isEmpty)
        XCTAssertEqual(Departure.earlier(from: [train], at: later, selection: selection, since: date("2026-09-22T00:00:00")).count, 1)
        XCTAssertEqual(NationalRailProvider.historyStart(before: date("2026-09-22T01:00:00"), now: later), date("2026-09-22T02:00:00"))
    }

    func testRequestUsesSubscribedEndpointAndIntermediateStationFilter() {
        let request = NationalRailProvider(apiKey: "test").request(origin: .stPancras, destination: .stNeots, start: date("2026-09-22T20:00:00"))
        XCTAssertEqual(request.url!.lastPathComponent, "20260922T200000")
        XCTAssertTrue(request.url!.path.contains("1010-live-departure-board---staff-version1_0/LDBSVWS"))
        let params = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(params.first(where: { $0.name == "filterCrs" })?.value, "SNO")
        XCTAssertEqual(params.first(where: { $0.name == "numRows" })?.value, "150")
        XCTAssertNil(params.first(where: { $0.name == "timeOffset" }))
    }

    func testEarlierBoardSuppliesDetailsWithoutExtraPerStationRequests() async throws {
        let provider = NationalRailProvider(apiKey: "board-key", transport: { request in
            XCTAssertTrue(request.url!.path.contains("GetDepBoardWithDetails"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-apikey"), "board-key")
            let origin = request.url!.deletingLastPathComponent().lastPathComponent
            return (Self.board(origin: origin), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let trains = try await provider.earlierDepartures(at: now)
        XCTAssertEqual(trains.count, 2)
        XCTAssertTrue(trains.allSatisfy { $0.platform == "B" && $0.departureStatus == .delayed(minutes: 3) })
    }

    func testDetailsUseRIDAndPreserveTrackingIdentity() async throws {
        let train = try decode(Self.board())
        let payload = try Self.details(from: Self.board())
        let provider = NationalRailProvider(detailsKey: "details-key", transport: { request in
            XCTAssertEqual(request.url!.lastPathComponent, "202609220001")
            XCTAssertTrue(request.url!.path.contains("GetServiceDetailsByRID"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-apikey"), "details-key")
            return (payload, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let result = try await provider.serviceDetails(for: train)
        XCTAssertEqual(result.id, train.id)
        XCTAssertTrue(TrackedJourney(departure: result).hasArrived)
        XCTAssertEqual(result.routeStops?.first(where: \.isBoarding)?.platform, "B")
    }

    func testSavedPublicIDMigratesWithoutUsingOldAPIs() async throws {
        var train = try decode(Self.board())
        train.serviceRID = nil
        train.id = "STP-old-public-service-id"
        let board = Self.board()
        let details = try Self.details(from: board)
        let provider = NationalRailProvider(apiKey: "board", detailsKey: "details", transport: { request in
            XCTAssertTrue(request.url!.path.contains("LDBSVWS"))
            return (request.url!.path.contains("GetServiceDetailsByRID") ? details : board,
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let result = try await provider.serviceDetails(for: train)
        XCTAssertEqual(result.id, train.id)
        XCTAssertEqual(result.serviceRID, "202609220001")
        XCTAssertTrue(TrackedJourney(departure: result).hasArrived)
    }

    private static func details(from board: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: board) as! [String: Any]
        var service = (object["trainServices"] as! [[String: Any]])[0]
        var boarding = service
        boarding["crs"] = object["crs"]
        let previous = service["previousLocations"] as! [[String: Any]]
        let next = service["subsequentLocations"] as! [[String: Any]]
        service["locations"] = previous + [boarding] + next
        service["generatedAt"] = object["generatedAt"]
        return try JSONSerialization.data(withJSONObject: service)
    }

    func testDetailsRejectWrongRIDAndBoardErrors() async throws {
        let train = try decode(Self.board())
        let wrong = try Self.details(from: Self.board(rid: "another"))
        let provider = NationalRailProvider(detailsKey: "key", transport: { request in
            (wrong, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        do { _ = try await provider.serviceDetails(for: train); XCTFail("Wrong train accepted") } catch {}
        XCTAssertThrowsError(try DarwinDecoder.decode(Self.board(boardChanges: ["servicesAreUnavailable": true]), origin: .stPancras, destination: .stNeots, now: now))
        XCTAssertThrowsError(try DarwinDecoder.decode(Self.board(origin: "KGX"), origin: .stPancras, destination: .stNeots, now: now))
        XCTAssertThrowsError(try DarwinDecoder.decode(Data("null".utf8), origin: .stPancras, destination: .stNeots, now: now))
    }

    func testHTTPFailuresPropagateWithoutInventingDepartures() async {
        for status in [401, 403, 429, 500] {
            let provider = NationalRailProvider(apiKey: "key", transport: { request in
                (Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            })
            do { _ = try await provider.snapshot(at: now); XCTFail("HTTP failure accepted") } catch {}
        }
    }

    func testMissingKeyFailsBeforeNetworking() async {
        let provider = NationalRailProvider(apiKey: "", transport: { _ in XCTFail("Must not call API"); throw RailAPIError.unavailable })
        do { _ = try await provider.snapshot(at: now); XCTFail("Missing key accepted") } catch {}
    }

    func testTruncatedBoardLoadsNextWindowWithoutDuplicates() async throws {
        var settings = RouteSettings()
        settings.starts = [.stPancras]; settings.ends = [.stNeots]
        settings.manualReversed = false; settings.manualUntil = now.addingTimeInterval(86400)
        let first = Self.board(boardChanges: ["isTruncated": true])
        let second = Self.board(rid: "202609220002", serviceChanges: ["std": "2026-09-22T14:56:00", "atd": "2026-09-22T14:57:00"])
        let provider = NationalRailProvider(settings: settings, apiKey: "key", transport: { request in
            let isFirst = request.url!.lastPathComponent == "20260922T135000"
            return (isFirst ? first : second, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let result = try await provider.earlierDepartures(at: now)
        XCTAssertEqual(result.map(\.serviceRID), ["202609220001", "202609220002"])
    }

    private actor RequestCount {
        var value = 0
        func increment() { value += 1 }
    }

    func testOverlappingDetailsRequestsShareOneFetchAndSeparateCredentials() async throws {
        let cache = DarwinResponseCache()
        let counter = RequestCount()
        let url = URL(string: "https://api1.raildata.org.uk/test")!
        let operation: @Sendable () async throws -> Data = {
            await counter.increment()
            try await Task.sleep(for: .milliseconds(10))
            return Data("response".utf8)
        }
        async let first = cache.load(url: url, key: "key-one", operation: operation)
        async let second = cache.load(url: url, key: "key-one", operation: operation)
        let values = try await [first, second]
        XCTAssertEqual(values[0], values[1])
        let sharedCount = await counter.value
        XCTAssertEqual(sharedCount, 1)
        _ = try await cache.load(url: url, key: "key-two", operation: operation)
        let separateCount = await counter.value
        XCTAssertEqual(separateCount, 2)
    }

    func testBothLondonStationsMergeAndSortByArrivalNotDeparture() async throws {
        let kgx = Self.board(origin: "KGX", rid: "kgx", serviceChanges: ["std": "2026-09-22T16:00:00", "etd": "2026-09-22T16:00:00", "departureType": "Forecast"],
            destinationChanges: ["sta": "2026-09-22T16:35:00", "eta": "2026-09-22T16:35:00", "arrivalType": "Forecast", "departureType": "Forecast"])
        let stp = Self.board(origin: "STP", rid: "stp", serviceChanges: ["std": "2026-09-22T15:55:00", "etd": "2026-09-22T15:55:00", "departureType": "Forecast"],
            destinationChanges: ["sta": "2026-09-22T16:45:00", "eta": "2026-09-22T16:45:00", "arrivalType": "Forecast", "departureType": "Forecast"])
        let provider = NationalRailProvider(apiKey: "key", transport: { request in
            let origin = request.url!.deletingLastPathComponent().lastPathComponent
            return (origin == "KGX" ? kgx : stp, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let result = try await provider.snapshot(at: now)
        XCTAssertEqual(result.departures.map(\.origin), [.kingsCross, .stPancras])
        XCTAssertGreaterThan(result.departures[0].scheduled, result.departures[1].scheduled)
    }

    func testNextEightIncludeBothStationsAcrossMidnight() async throws {
        let late = date("2026-09-22T22:30:00")
        func payload(origin: String, times: [(String, String)]) throws -> Data {
            let services = try times.enumerated().map { index, times in
                let data = Self.board(origin: origin, rid: "\(origin)-\(times.0)",
                    serviceChanges: ["std": times.0, "etd": times.0, "departureType": "Forecast"],
                    destinationChanges: ["sta": times.1, "eta": times.1,
                        "arrivalType": "Forecast", "departureType": "Forecast"])
                return (try JSONSerialization.jsonObject(with: data) as! [String: Any])["trainServices"] as! [[String: Any]]
            }.flatMap { $0 }
            return try JSONSerialization.data(withJSONObject: ["crs": origin,
                "generatedAt": "2026-09-22T22:30:00+01:00", "trainServices": services])
        }
        let firstSTP = try payload(origin: "STP", times: [
            ("2026-09-22T22:31:00", "2026-09-22T23:27:00"),
            ("2026-09-22T22:46:00", "2026-09-22T23:42:00"),
            ("2026-09-22T23:01:00", "2026-09-22T23:57:00"),
            ("2026-09-22T23:16:00", "2026-09-23T00:12:00"),
            ("2026-09-22T23:31:00", "2026-09-23T00:27:00"),
            ("2026-09-22T23:46:00", "2026-09-23T00:42:00")])
        let laterSTP = try payload(origin: "STP", times: [
            ("2026-09-23T00:46:00", "2026-09-23T01:42:00"),
            ("2026-09-23T02:00:00", "2026-09-23T03:00:00")])
        let emptyKGX = try payload(origin: "KGX", times: [])
        let laterKGX = try payload(origin: "KGX", times: [("2026-09-23T01:36:00", "2026-09-23T02:40:00")])
        let counter = RequestCount()
        let provider = NationalRailProvider(apiKey: "key", transport: { request in
            await counter.increment()
            let first = request.url!.lastPathComponent == "20260922T222900"
            let kgx = request.url!.deletingLastPathComponent().lastPathComponent == "KGX"
            let data = kgx ? (first ? emptyKGX : laterKGX) : (first ? firstSTP : laterSTP)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let snapshot = try await provider.snapshot(at: late)
        XCTAssertFalse(snapshot.departures.contains { $0.scheduled >= self.date("2026-09-23T02:00:00") })
        let visible = Departure.board(from: snapshot.departures, at: late)
        XCTAssertEqual(visible.count, 8)
        XCTAssertEqual(visible.suffix(2).map { RailTime.string($0.scheduled) }, ["00:46", "01:36"])
        XCTAssertEqual(visible.suffix(2).map(\.origin), [.stPancras, .kingsCross])
        let calls = await counter.value
        XCTAssertEqual(calls, 4, "Stop searching once both station boards provide eight distinct trains")
    }

    func testTomorrowUsesCurrentRouteAndExcludesTonight() async throws {
        let late = date("2026-09-22T22:30:00")
        var object = try JSONSerialization.jsonObject(with: Self.board(origin: "KGX")) as! [String: Any]
        let services = try (0..<8).flatMap { index -> [[String: Any]] in
            let payload = Self.board(origin: "KGX", rid: "tomorrow-\(index)",
                serviceChanges: ["std": "2026-09-23T05:1\(index):00", "etd": "2026-09-23T05:1\(index):00", "departureType": "Forecast"],
                destinationChanges: ["sta": "2026-09-23T06:1\(index):00", "eta": "2026-09-23T06:1\(index):00", "arrivalType": "Forecast", "departureType": "Forecast"])
            return (try JSONSerialization.jsonObject(with: payload) as! [String: Any])["trainServices"] as! [[String: Any]]
        }
        let tonight = Self.board(origin: "KGX", rid: "tonight", serviceChanges: ["std": "2026-09-23T01:36:00", "departureType": "Forecast"])
        object["trainServices"] = services + ((try JSONSerialization.jsonObject(with: tonight) as! [String: Any])["trainServices"] as! [[String: Any]])
        object["generatedAt"] = "2026-09-22T22:30:00+01:00"
        let data = try JSONSerialization.data(withJSONObject: object)
        let empty = Self.board(boardChanges: ["trainServices": [], "generatedAt": "2026-09-22T22:30:00+01:00"])
        let provider = NationalRailProvider(apiKey: "key", transport: { request in
            let origin = request.url!.deletingLastPathComponent().lastPathComponent
            XCTAssertTrue(["KGX", "STP"].contains(origin), "Do not apply tomorrow morning’s reverse route")
            XCTAssertTrue(["20260923T020000", "20260923T040000", "20260923T060000"].contains(request.url!.lastPathComponent))
            return (origin == "KGX" ? data : empty, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let result = try await provider.snapshot(at: late, tomorrow: true)
        XCTAssertEqual(result.departures.count, 8)
        XCTAssertTrue(result.departures.allSatisfy { $0.scheduled >= date("2026-09-23T02:00:00") })
        XCTAssertTrue(result.isFresh(at: late))
        XCTAssertEqual(result.routeKey, RouteSettings().selection(at: late).key)
    }

    func testAutomaticLookupUsesExactRouteAndScheduledTime() async throws {
        let train = try decode(Self.board())
        let rule = AutoTrackingRule(departure: train)
        let payload = Self.board(rid: "new-daily-rid")
        let provider = NationalRailProvider(apiKey: "key", transport: { request in
            XCTAssertEqual(request.url!.lastPathComponent, "20260922T144600")
            XCTAssertEqual(request.url!.deletingLastPathComponent().lastPathComponent, "STP")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(query.first { $0.name == "filterCrs" }?.value, "SNO")
            XCTAssertEqual(query.first { $0.name == "timeWindow" }?.value, "1")
            return (payload, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let matched = try await provider.automaticDeparture(for: rule, at: now)
        XCTAssertEqual(matched?.serviceRID, "new-daily-rid")
    }

    func testLaterPagesExpandByEightAndStopAtTravelDayEnd() async throws {
        func payload(origin: String, hour: Int) throws -> Data {
            var object = try JSONSerialization.jsonObject(with: Self.board(origin: origin)) as! [String: Any]
            object["trainServices"] = try (0..<8).flatMap { index -> [[String: Any]] in
                let data = Self.board(origin: origin, rid: "\(origin)-\(index)",
                    serviceChanges: ["std": "2026-09-22T\(hour):0\(index):00", "etd": "2026-09-22T\(hour):0\(index):00", "departureType": "Forecast"],
                    destinationChanges: ["sta": "2026-09-22T\(hour):4\(index):00", "eta": "2026-09-22T\(hour):4\(index):00", "arrivalType": "Forecast", "departureType": "Forecast"])
                return (try JSONSerialization.jsonObject(with: data) as! [String: Any])["trainServices"] as! [[String: Any]]
            }
            return try JSONSerialization.data(withJSONObject: object)
        }
        let early = try payload(origin: "STP", hour: 16)
        let late = try payload(origin: "KGX", hour: 18)
        let empty = Self.board(origin: "KGX", boardChanges: ["trainServices": []])
        let provider = NationalRailProvider(apiKey: "key", transport: { request in
            let origin = request.url!.deletingLastPathComponent().lastPathComponent
            let firstWindow = request.url!.lastPathComponent == "20260922T154900"
            return (origin == "STP" ? early : (firstWindow ? empty : late),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let initial = try await provider.snapshot(at: now)
        XCTAssertEqual(initial.departures.count, 8)
        XCTAssertEqual(initial.hasLaterDepartures, true)
        let expanded = try await provider.snapshot(at: now, tomorrow: false, limit: 16)
        XCTAssertEqual(expanded.departures.count, 16)
        XCTAssertEqual(Array(expanded.departures.prefix(8)), initial.departures)
        XCTAssertEqual(Set(expanded.departures.map(\.origin)), [.kingsCross, .stPancras])
        let exhausted = try await provider.snapshot(at: now, tomorrow: false, limit: 24)
        XCTAssertEqual(exhausted.departures.count, 16)
        XCTAssertEqual(exhausted.hasLaterDepartures, false)
    }

    func testEmptyUpcomingSearchStopsAtOvernightReset() async throws {
        let counter = RequestCount()
        let provider = NationalRailProvider(apiKey: "key", transport: { request in
            await counter.increment()
            let origin = request.url!.deletingLastPathComponent().lastPathComponent
            let data = Self.board(origin: origin, boardChanges: ["trainServices": []])
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let snapshot = try await provider.snapshot(at: now)
        XCTAssertTrue(snapshot.departures.isEmpty)
        let calls = await counter.value
        XCTAssertEqual(calls, 12)
    }

    func testCompletedSuppressedServicesRemainInMixedHistoryButNotUpcoming() throws {
        let kgx = Self.board(origin: "KGX", rid: "kgx-completed", serviceChanges: ["serviceIsSupressed": true],
            destinationChanges: ["serviceIsSupressed": true])
        let decoded = try DarwinDecoder.decode(kgx, origin: .kingsCross, destination: .stNeots, now: now)
        let stp = try decode(Self.board())
        let selection = RouteSelection(starts: [.kingsCross, .stPancras], ends: [.stNeots])
        let mixed = Departure.earlier(from: decoded.departures + [stp], at: now, selection: selection)
        XCTAssertEqual(Set(mixed.map(\.origin)), [.kingsCross, .stPancras])
        XCTAssertTrue(Departure.board(from: mixed, at: now, selection: selection).isEmpty)
        let train = try XCTUnwrap(decoded.departures.first)
        XCTAssertNotNil(train.routeStops?.first(where: \.isBoarding)?.actualDeparture)
        XCTAssertTrue(TrackedJourney(departure: train).hasArrived)
        XCTAssertEqual(train.platform, "B", "Confirmed departures retain their historical platform")
    }

    func testMultipleDestinationsDeduplicateAtEarliestArrival() async throws {
        var settings = RouteSettings()
        settings.starts = [.stPancras]
        settings.ends = [.stNeots, Station(rawValue: "HUN")!]
        settings.manualReversed = false
        settings.manualUntil = now.addingTimeInterval(86400)
        let payload = Self.board(serviceChanges: ["std": "2026-09-22T16:00:00", "departureType": "Forecast", "etd": "2026-09-22T16:00:00"])
        let provider = NationalRailProvider(settings: settings, apiKey: "key", transport: { request in
            (payload, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let result = try await provider.snapshot(at: now)
        XCTAssertEqual(result.departures.count, 1)
        XCTAssertEqual(result.departures.first?.callingAt, [.stNeots])
    }

    func testFasterArrivalInLaterWindowIsNotOmitted() async throws {
        var board = try JSONSerialization.jsonObject(with: Self.board()) as! [String: Any]
        board["trainServices"] = try (0..<8).flatMap { index -> [[String: Any]] in
            let data = Self.board(rid: "slow-\(index)",
                serviceChanges: ["std": "2026-09-22T16:0\(index):00", "etd": "2026-09-22T16:0\(index):00", "departureType": "Forecast"],
                destinationChanges: ["sta": "2026-09-22T20:00:00", "eta": "2026-09-22T20:00:00", "arrivalType": "Forecast", "departureType": "Forecast"])
            return (try JSONSerialization.jsonObject(with: data) as! [String: Any])["trainServices"] as! [[String: Any]]
        }
        let slow = try JSONSerialization.data(withJSONObject: board)
        let fast = Self.board(origin: "KGX", rid: "fast",
            serviceChanges: ["std": "2026-09-22T18:00:00", "etd": "2026-09-22T18:00:00", "departureType": "Forecast"],
            destinationChanges: ["sta": "2026-09-22T18:45:00", "eta": "2026-09-22T18:45:00", "arrivalType": "Forecast", "departureType": "Forecast"])
        let empty = Self.board(origin: "KGX", boardChanges: ["trainServices": []])
        let provider = NationalRailProvider(apiKey: "key", transport: { request in
            let origin = request.url!.deletingLastPathComponent().lastPathComponent
            let first = request.url!.lastPathComponent == "20260922T154900"
            return (origin == "STP" ? slow : (first ? empty : fast), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let snapshot = try await provider.snapshot(at: now)
        let visible = Departure.board(from: snapshot.departures, at: now)
        XCTAssertEqual(visible.count, 8)
        XCTAssertEqual(visible.first?.serviceRID, "fast")
    }

    func testOperationalBoardingCallIsExcluded() throws {
        let snapshot = try DarwinDecoder.decode(Self.board(serviceChanges: ["isOperationalCall": true]),
            origin: .stPancras, destination: .stNeots, now: now)
        XCTAssertTrue(snapshot.departures.isEmpty)
    }

    func testCustomOriginKeepsItsOfficialName() throws {
        let snapshot = try DarwinDecoder.decode(Self.board(origin: "HUN", boardChanges: ["locationName": "Huntingdon"]),
            origin: Station(rawValue: "HUN")!, destination: .stNeots, now: now)
        XCTAssertEqual(snapshot.departures.first?.origin.name, "Huntingdon")
    }

    func testHistoryCrossesMidnightWithinTravelDay() {
        let afterMidnight = date("2026-09-23T00:30:00")
        XCTAssertEqual(NationalRailProvider.historyStart(before: afterMidnight, now: afterMidnight), date("2026-09-22T22:30:00"))
        XCTAssertEqual(RouteSettings().travelDayStart(at: afterMidnight), date("2026-09-22T02:00:00"))
        XCTAssertEqual(RouteSettings().travelDayStart(at: date("2026-09-23T02:00:00")), date("2026-09-23T02:00:00"))
        var settings = RouteSettings()
        settings.resetMinutes = 3 * 60
        XCTAssertEqual(settings.travelDayStart(at: date("2026-09-23T02:30:00")), date("2026-09-22T03:00:00"))
    }
    func testSuppressedFutureTerminusDoesNotCompleteService() throws {
        let stops: [[String: Any]] = [
            ["crs": "SNO", "sta": "2026-09-22T15:20:00", "isCancelled": true],
            ["crs": "HUN", "std": "2026-09-22T15:30:00", "atd": "2026-09-22T15:30:00", "departureType": "Actual"],
            ["crs": "PBO", "sta": "2026-09-22T16:00:00", "eta": "2026-09-22T16:00:00", "arrivalType": "Forecast", "serviceIsSupressed": true]
        ]
        let train = try decode(Self.board(serviceChanges: ["subsequentLocations": stops]))
        XCTAssertEqual(train.routeStops?.last?.crs, "HUN")
        XCTAssertFalse(train.isServiceComplete)
        XCTAssertFalse(TrackedJourney(departure: train).hasFinished)
        var completedStops = stops
        completedStops[2]["arrivalType"] = "Actual"
        completedStops[2]["ata"] = "2026-09-22T15:49:00"
        let completed = try decode(Self.board(serviceChanges: ["subsequentLocations": completedStops]))
        XCTAssertTrue(completed.isServiceComplete)
        XCTAssertTrue(TrackedJourney(departure: completed).hasFinished)
        let restored = try JSONDecoder().decode(Departure.self, from: JSONEncoder().encode(train))
        XCTAssertFalse(restored.isServiceComplete)
    }

    func testDepartureForecastUsesDepartureScheduleIncludingDwell() throws {
        for (time, status) in [("17:05:00", ServiceStatus.onTime), ("17:08:00", .delayed(minutes: 3)), ("17:03:00", .early(minutes: 2))] {
            let train = try decode(Self.board(destinationChanges: ["sta": "2026-09-22T17:00:00", "std": "2026-09-22T17:05:00",
                "arrivalType": "NoLog", "departureType": "Forecast", "etd": "2026-09-22T" + time]))
            let stop = try XCTUnwrap(train.routeStops?.first(where: \.isDestination))
            XCTAssertEqual(stop.forecastEvent, .departure)
            XCTAssertEqual(stop.timingStatus, status)
        }
        let train = try decode(Self.board(destinationChanges: ["sta": "2026-09-22T17:00:00", "std": "2026-09-22T17:05:00",
            "arrivalType": "Forecast", "eta": "2026-09-22T17:02:00", "departureType": "Forecast", "etd": "2026-09-22T17:05:00"]))
        XCTAssertEqual(train.routeStops?.first(where: \.isDestination)?.timingStatus, .delayed(minutes: 2))
    }

    func testUnknownDepartureRemainsUpcomingUntilActualDeparture() throws {
        for type in ["Delayed", "NoLog"] {
            let train = try decode(Self.board(serviceChanges: ["departureType": type]))
            let selection = RouteSettings().selection(at: now)
            XCTAssertEqual(Departure.board(from: [train], at: now, selection: selection).count, 1)
            XCTAssertTrue(Departure.earlier(from: [train], at: now, selection: selection).isEmpty)
        }
        let actual = try decode(Self.board())
        let selection = RouteSettings().selection(at: now)
        XCTAssertTrue(Departure.board(from: [actual], at: now, selection: selection).isEmpty)
        XCTAssertEqual(Departure.earlier(from: [actual], at: now, selection: selection).count, 1)
    }

    func testStationNoticesMergeAcrossOriginsAndDeduplicateWindows() async throws {
        let provider = NationalRailProvider(apiKey: "key", transport: { request in
            let origin = request.url!.deletingLastPathComponent().lastPathComponent
            let data = Self.board(origin: origin, boardChanges: ["nrccMessages": [
                ["category": "Trainservice", "severity": "Major", "xhtmlMessage": "<p>Delays &amp; cancellations</p><p>Read <a href=\"https://nationalrail.co.uk\">more</a>.</p>"],
                ["category": "Station", "xhtmlMessage": "Lift out of service"],
                ["category": "Trainservice", "xhtmlMessage": " "]]])
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let snapshot = try await provider.snapshot(at: now)
        XCTAssertEqual(snapshot.stationNotices?.count, 2)
        XCTAssertEqual(Set(snapshot.stationNotices?.map(\.station) ?? []), [.kingsCross, .stPancras])
        XCTAssertEqual(snapshot.stationNotices?.first?.text, "Delays & cancellations\n\nRead more.")
        XCTAssertTrue(snapshot.stationNotices?.first?.isSevere == true)
        let without = try DarwinDecoder.decode(Self.board(), origin: .stPancras, destination: .stNeots, now: now)
        XCTAssertEqual(without.stationNotices, [])
    }

    func testIdenticalStationWarningsGroupWithAllStationsAndHighestSeverity() {
        let notices = [
            StationNotice(station: .stPancras, text: "Delays between stations.\n\nCheck before travel.", severity: "Minor"),
            StationNotice(station: .kingsCross, text: "Delays between stations. Check before travel.", severity: "Severe"),
            StationNotice(station: .kingsCross, text: "Delays between stations. Check before travel.", severity: "Minor"),
            StationNotice(station: .stPancras, text: "Cancelled services due to a separate incident.", severity: "Minor")
        ]
        let groups = StationNotice.grouped(notices)
        XCTAssertEqual(groups.count, 2)
        let shared = groups.first { $0.stations.count == 2 }
        XCTAssertEqual(shared?.stations, [.kingsCross, .stPancras])
        XCTAssertEqual(shared?.stationNames, [Station.kingsCross.name, Station.stPancras.name].joined(separator: " · "))
        XCTAssertTrue(shared?.isSevere == true)
        XCTAssertEqual(groups.first { $0.stations.count == 1 }?.stations, [.stPancras])
        XCTAssertEqual(StationNotice.grouped(Array(notices.reversed())).map(\.id), groups.map(\.id))
        XCTAssertTrue(StationNotice.grouped([]).isEmpty)
    }

    func testRefreshRetainsEarlierCallsWithoutReplacingFreshStopData() throws {
        let original = try decode(Self.board())
        var shorter = try decode(Self.board(serviceChanges: ["previousLocations": []],
            boardChanges: ["generatedAt": "2026-09-22T15:51:00+01:00"]))
        shorter.platform = "9"
        let merged = shorter.mergingEarlierStops(from: original)
        XCTAssertEqual(merged.routeStops?.map(\.crs), original.routeStops?.map(\.crs))
        XCTAssertEqual(merged.platform, "9")
        XCTAssertEqual(merged.observedAt, shorter.observedAt)
        XCTAssertEqual(Set(merged.routeStops!.map(\.id)).count, merged.routeStops!.count)
        XCTAssertEqual(merged.mergingEarlierStops(from: original), merged)
        XCTAssertEqual(original.mergingEarlierStops(from: shorter), merged)
        XCTAssertEqual(TrackedJourney(departure: original).accepting(shorter).departure, merged)
        XCTAssertEqual(try JSONDecoder().decode(Departure.self, from: JSONEncoder().encode(merged)), merged)

        let corrected = try decode(Self.board(serviceChanges: ["previousLocations": [["crs": "LBG", "std": "2026-09-22T14:30:00", "isCancelled": true]]],
            boardChanges: ["generatedAt": "2026-09-22T15:52:00+01:00"]))
        let final = corrected.mergingEarlierStops(from: merged)
        XCTAssertTrue(final.routeStops!.first!.isCancelled)
        XCTAssertEqual(final.routeStops?.count, corrected.routeStops?.count)
        shorter.id = "another-train"
        XCTAssertEqual(shorter.mergingEarlierStops(from: original), shorter)
    }

    func testDetailsResponseWithoutPreviousStopsRetainsKnownHistory() async throws {
        let original = try decode(Self.board())
        let payload = try Self.details(from: Self.board(serviceChanges: ["previousLocations": []],
            boardChanges: ["generatedAt": "2026-09-22T15:51:00+01:00"]))
        let provider = NationalRailProvider(detailsKey: "key", transport: { request in
            (payload, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let refreshed = try await provider.serviceDetails(for: original)
        XCTAssertEqual(refreshed.routeStops?.map(\.crs), original.routeStops?.map(\.crs))
        XCTAssertEqual(refreshed.routeStops?.first?.actualDeparture, original.routeStops?.first?.actualDeparture)
    }

    func testDelayReasonsPreserveOfficialCodesWithoutInventingDescriptions() throws {
        let coded = try decode(Self.board(serviceChanges: ["delayReason": ["Value": 832, "tiploc": "STPANCI", "near": true]]))
        XCTAssertEqual(coded.delayReasonCode, 832)
        XCTAssertNil(coded.disruptionReason)
        let text = try decode(Self.board(serviceChanges: ["delayReason": "<p>Delayed by a signalling fault.</p>"]))
        XCTAssertEqual(text.disruptionReason, "Delayed by a signalling fault.")
        let cancelled = try decode(Self.board(serviceChanges: ["isCancelled": true,
            "delayReason": "Earlier delay", "cancelReason": "Cancelled because of a train fault."]))
        XCTAssertEqual(cancelled.disruptionReason, "Cancelled because of a train fault.")
        let numeric = try decode(Self.board(serviceChanges: ["delayReason": "832"]))
        XCTAssertNil(numeric.disruptionReason)
    }

    func testReferenceDataResolvesDelayAndCancellationDescriptions() async throws {
        let reference = NationalRailReference(apiKey: "reference-test", transport: { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api1.raildata.org.uk/1010-reference-data1_0/LDBSVWS/api/ref/20211101/GetReasonCodeList")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-apikey"), "reference-test")
            let data = Data(#"[{"code":832,"lateReason":"Delayed by a signalling fault.","cancReason":"Cancelled because of a signalling fault."}]"#.utf8)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let delayed = try decode(Self.board(serviceChanges: ["delayReason": ["Value": 832]]))
        let cancelled = try decode(Self.board(serviceChanges: ["isCancelled": true, "cancelReason": ["Value": 832]]))
        let unknown = try decode(Self.board(serviceChanges: ["delayReason": ["Value": 99999]]))
        let explained = try await reference.explaining([delayed, cancelled, unknown])
        XCTAssertEqual(explained.map(\.disruptionReason), ["Delayed by a signalling fault.", "Cancelled because of a signalling fault.", nil])
    }

    func testReferenceFailureDoesNotDiscardFreshServiceInformation() async throws {
        let original = try decode(Self.board())
        let payload = try Self.details(from: Self.board(serviceChanges: ["delayReason": ["Value": 832]]))
        let reference = NationalRailReference(apiKey: "reference-test", transport: { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!)
        })
        let provider = NationalRailProvider(detailsKey: "details-test", transport: { request in
            (payload, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, reference: reference)
        let updated = try await provider.serviceDetails(for: original)
        XCTAssertEqual(updated.delayReasonCode, 832)
        XCTAssertNil(updated.disruptionReason)
        XCTAssertEqual(updated.platform, original.platform)
        XCTAssertEqual(updated.routeStops?.count, original.routeStops?.count)
    }

    func testReferenceStationListContainsNamesAndCRSCodes() throws {
        let data = Data(#"{"version":"example","StationList":[{"crs":"SNO","Value":"St Neots"},{"crs":"KGX","Value":"London Kings Cross"},{"crs":"STP","Value":"London St Pancras International"},{"crs":"SNO","Value":"Duplicate"},{"crs":"bad","Value":"Invalid"}]}"#.utf8)
        let stations = try NationalRailReference.decodeStations(data)
        XCTAssertEqual(Set(stations.map(\.rawValue)), ["SNO", "KGX", "STP"])
        XCTAssertEqual(stations.first { $0.rawValue == "STP" }?.fullName, "London St Pancras International")
        XCTAssertThrowsError(try NationalRailReference.decodeStations(Data(#"{"StationList":[]}"#.utf8)))
    }

}
