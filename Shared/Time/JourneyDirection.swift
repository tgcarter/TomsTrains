import Foundation

enum JourneyDirection: String, Sendable {
    case toLondon, toStNeots

    static var londonCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    static func at(_ date: Date) -> Self {
        RouteSettings().isReversed(at: date) ? .toStNeots : .toLondon
    }

    var title: String { self == .toLondon ? "To London" : "To St Neots" }
    var subtitle: String {
        self == .toLondon ? "From St Neots" : "From King’s Cross & St Pancras"
    }

    func includes(_ departure: Departure) -> Bool {
        switch self {
        case .toLondon:
            departure.origin == .stNeots &&
                (departure.callingAt.contains(.kingsCross) || departure.callingAt.contains(.stPancras))
        case .toStNeots:
            (departure.origin == .kingsCross || departure.origin == .stPancras) &&
                departure.callingAt.contains(.stNeots)
        }
    }
}
