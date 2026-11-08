import Foundation

struct AutoTrackingRule: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var origin: Station
    var destination: Station
    var departureMinutes: Int
    var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    var isEnabled = true
    var lastHandledDay: Date?

    init(departure: Departure) {
        origin = departure.origin
        destination = departure.callingAt.first ?? departure.origin
        let parts = JourneyDirection.londonCalendar.dateComponents([.hour, .minute], from: departure.scheduled)
        departureMinutes = parts.hour! * 60 + parts.minute!
    }

    var isValid: Bool {
        origin != destination && (0..<1440).contains(departureMinutes)
            && !weekdays.isEmpty && weekdays.allSatisfy { (1...7).contains($0) }
    }

    func scheduled(on date: Date) -> Date? {
        JourneyDirection.londonCalendar.date(bySettingHour: departureMinutes / 60,
            minute: departureMinutes % 60, second: 0, of: date)
    }

    func matches(_ departure: Departure) -> Bool {
        let parts = JourneyDirection.londonCalendar.dateComponents([.hour, .minute], from: departure.scheduled)
        return departure.origin == origin && departure.callingAt.contains(destination)
            && parts.hour! * 60 + parts.minute! == departureMinutes
    }

    func isDue(on date: Date) -> Bool {
        let calendar = JourneyDirection.londonCalendar
        return isEnabled && isValid && weekdays.contains(calendar.component(.weekday, from: date))
            && !(lastHandledDay.map { calendar.isDate($0, inSameDayAs: date) } ?? false)
    }
}
