import Foundation

struct DepartureSnapshot: Codable, Sendable {
    let fetchedAt: Date
    let departures: [Departure]
    var notices: [String] = []
    var stationNotices: [StationNotice]? = nil
    var routeKey: String? = nil
    var hasLaterDepartures: Bool? = nil

    func isFresh(at date: Date, settings: RouteSettings = RouteSettings()) -> Bool {
        date.timeIntervalSince(fetchedAt) < 300 && date.timeIntervalSince(fetchedAt) >= -60
            && (routeKey ?? settings.selection(at: fetchedAt).key) == settings.selection(at: date).key
    }


}
