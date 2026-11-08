import Foundation

enum RailDate {
    static func timestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    static func clock(_ value: String, nearest reference: Date) -> Date? {
        let parts = value.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        let calendar = JourneyDirection.londonCalendar
        return (-1...1).compactMap { offset -> Date? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: reference) else { return nil }
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
        }.min { abs($0.timeIntervalSince(reference)) < abs($1.timeIntervalSince(reference)) }
    }

    static func clock(_ value: String, onOrAfter reference: Date) -> Date? {
        guard let result = clock(value, nearest: reference) else { return nil }
        return result >= reference ? result : JourneyDirection.londonCalendar.date(byAdding: .day, value: 1, to: result)
    }
}
