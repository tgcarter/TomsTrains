import Foundation

struct EarlierDeparturePagination: Equatable, Sendable {
    private(set) var visibleCount = 0

    mutating func revealMore() { visibleCount += Departure.defaultBoardLimit }

    func visible(in departures: [Departure]) -> [Departure] {
        Array(departures.suffix(visibleCount))
    }

    func hasMore(in departures: [Departure]) -> Bool { departures.count > visibleCount }
}
