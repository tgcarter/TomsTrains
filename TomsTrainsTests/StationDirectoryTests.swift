import XCTest
#if SWIFT_PACKAGE
@testable import TomsTrainsCore
#endif

final class StationDirectoryTests: XCTestCase {
    func testLiveStationSearchRestoresBoardAndKeepsRecentStationsAfterClear() {
        let suite = "live-board-search-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var cambridge = Station(rawValue: "CBG")!
        cambridge.displayName = "Cambridge"
        var searches = LiveBoardSearches()
        searches.select(cambridge)
        searches.select(.stPancras)
        searches.select(cambridge)
        searches.mode = .arrivals
        searches.filterStation = .stNeots
        searches.save(to: defaults)

        var restored = LiveBoardSearches.load(from: defaults)
        XCTAssertEqual(restored.station?.name, "Cambridge")
        XCTAssertEqual(restored.mode, .arrivals)
        XCTAssertEqual(restored.filterStation, .stNeots)
        XCTAssertEqual(restored.recentStations.map(\.rawValue), ["CBG", "STP"])

        restored.clearSelection()
        restored.save(to: defaults)
        let cleared = LiveBoardSearches.load(from: defaults)
        XCTAssertNil(cleared.station)
        XCTAssertNil(cleared.filterStation)
        XCTAssertEqual(cleared.recentStations.map(\.rawValue), ["CBG", "STP"])
    }

    func testAuthenticatedNationalRailRequestAndDecode() async throws {
        let directory = StationDirectory(apiKey: "stations-test-key", transport: { request in
            XCTAssertEqual(request.url, StationDirectory.endpoint)
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-apikey"), "stations-test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            let data = Data(#"{"version":"test","StationList":[{"Value":"Cambridge","crs":"CBG"}]}"#.utf8)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let stations = try await directory.fetch()
        XCTAssertEqual(stations.map(\.rawValue), ["CBG"])
        XCTAssertEqual(stations.first?.name, "Cambridge")
    }

    func testRejectedStationCredentialsAndMalformedResponsesFail() async {
        for statusCode in [401, 403, 429, 500, 200] {
            let directory = StationDirectory(apiKey: "test", transport: { request in
                (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!)
            })
            do { _ = try await directory.fetch(); XCTFail("Expected failure for \(statusCode)") }
            catch { XCTAssertTrue(error is RailAPIError) }
        }
        let directory = StationDirectory(apiKey: "", transport: { _ in
            XCTFail("Missing credentials must not make a request")
            throw RailAPIError.unavailable
        })
        do { _ = try await directory.fetch(); XCTFail("Expected missing-key failure") }
        catch { XCTAssertTrue(error is RailAPIError) }
    }
}
