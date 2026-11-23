import Foundation

struct DepartureSnapshot: Codable, Sendable {
    let fetchedAt: Date
    let departures: [Departure]
    var notices: [String] = []
    var stationNotices: [StationNotice]? = nil
    var routeKey: String? = nil
    var hasLaterDepartures: Bool? = nil

    func isFresh(at date: Date, settings: RouteSettings = RouteSettings()) -> Bool {
        RailDate.isFreshReport(fetchedAt, at: date)
            && (routeKey ?? settings.selection(at: fetchedAt).key) == settings.selection(at: date).key
    }


}
