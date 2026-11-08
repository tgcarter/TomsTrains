import XCTest
#if SWIFT_PACKAGE
@testable import TomsTrainsCore
#endif

final class DestinationHeadingTests: XCTestCase {
    private func station(_ code: String, _ name: String) -> Station {
        var station = Station(rawValue: code)!
        station.displayName = name
        return station
    }
    private func heading(_ stations: [Station]) -> String {
        RouteSelection(starts: [.stNeots], ends: stations).title
    }
    func testDefaultLondonNamesGroupWithoutRouteSpecialCase() {
        XCTAssertEqual(heading([.kingsCross, .stPancras]), "To London")
    }
    func testSharedCityAndMultiwordPlaceNames() {
        XCTAssertEqual(heading([station("CBG", "Cambridge"), station("CMB", "Cambridge North"), station("CMS", "Cambridge South")]), "To Cambridge")
        XCTAssertEqual(heading([station("AAA", "Milton Keynes Central"), station("BBB", "Milton Keynes North")]), "To Milton Keynes")
    }
    func testSharedWordsCanAppearInDifferentPositions() {
        XCTAssertEqual(heading([station("AAA", "London Bridge"), station("BBB", "Blackfriars (London)")]), "To London")
        XCTAssertEqual(heading([station("AAA", "Cambridge North"), station("BBB", "cambridge South")]), "To Cambridge")
    }
    func testEveryDestinationMustMatchAndWholeWordsOnly() {
        XCTAssertEqual(heading([station("AAA", "York"), station("BBB", "Yorkshire")]), "To York & Yorkshire")
        XCTAssertEqual(heading([station("AAA", "Cambridge North"), station("BBB", "Cambridge South"), station("CCC", "Ely")]), "To Cambridge North & Cambridge South & Ely")
    }
    func testSingleStationAndGenericWordsKeepSpecificNames() {
        XCTAssertEqual(heading([station("CMB", "Cambridge North")]), "To Cambridge North")
        XCTAssertEqual(heading([station("AAA", "St Neots"), station("BBB", "St Albans")]), "To St Neots & St Albans")
    }
}
