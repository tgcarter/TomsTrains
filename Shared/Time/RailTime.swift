import Foundation

enum RailTime {
    static func string(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime
            .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
            .locale(Locale(identifier: "en_GB"))
        style.timeZone = TimeZone(identifier: "Europe/London")!
        return date.formatted(style)
    }
}
