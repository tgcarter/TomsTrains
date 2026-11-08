import XCTest
#if SWIFT_PACKAGE
@testable import TomsTrainsCore
#endif

final class StationDirectoryTests: XCTestCase {
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
