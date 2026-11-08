import Foundation

struct RouteSelection: Equatable, Sendable {
    let starts: [Station]
    let ends: [Station]
    var key: String { starts.map(\.rawValue).sorted().joined(separator: ",") + ">" + ends.map(\.rawValue).sorted().joined(separator: ",") }
    var destinationName: String {
        Self.sharedName(for: ends) ?? ends.map(\.shortName).joined(separator: " & ")
    }
    private static func sharedName(for stations: [Station]) -> String? {
        guard stations.count > 1 else { return nil }
        // Match complete, consecutive words anywhere in each official name, including
        // qualifiers such as "(London)". Never match fragments like York in Yorkshire.
        let names = stations.map { station in
            station.fullName.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        }.sorted { $0.joined(separator: " ") < $1.joined(separator: " ") }
        guard let first = names.first, !first.isEmpty else { return nil }
        let normalised = names.map { $0.map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_GB")) } }
        let generic: Set<String> = ["the", "and", "at", "on", "in", "st", "saint", "station", "rail", "railway", "international", "road", "park", "junction", "central", "north", "south", "east", "west"]
        for length in stride(from: first.count, through: 1, by: -1) {
            for start in 0...(first.count - length) {
                let candidate = Array(normalised[0][start..<(start + length)])
                guard candidate.contains(where: { !generic.contains($0) }) else { continue }
                let shared = normalised.dropFirst().allSatisfy { words in
                    guard words.count >= length else { return false }
                    return (0...(words.count - length)).contains { offset in
                        Array(words[offset..<(offset + length)]) == candidate
                    }
                }
                if shared { return first[start..<(start + length)].joined(separator: " ") }
            }
        }
        return nil
    }
    var title: String { "To \(destinationName)" }
    var subtitle: String { "From " + starts.map(\.shortName).joined(separator: " & ") }
    func includes(_ departure: Departure) -> Bool {
        starts.contains(departure.origin) && departure.callingAt.contains(where: ends.contains)
    }
}

enum AppAppearance: String, Codable, CaseIterable, Sendable {
    case system, light, dark
    var title: String { rawValue.capitalized }
}

struct RouteSettings: Codable, Equatable, Sendable {
    var starts: [Station] = [.stNeots]
    var ends: [Station] = [.kingsCross, .stPancras]
    var swapMinutes = 12 * 60
    var resetMinutes = 2 * 60
    var appearance: AppAppearance = .system
    var manualReversed: Bool?
    var manualUntil: Date?

    var isValid: Bool {
        !starts.isEmpty && !ends.isEmpty && Set(starts).isDisjoint(with: ends)
            && Set(starts).count == starts.count && Set(ends).count == ends.count
            && (0..<1440).contains(swapMinutes) && (0..<1440).contains(resetMinutes) && resetMinutes != swapMinutes
    }
    func isReversed(at date: Date) -> Bool {
        if let manualReversed, let manualUntil, date < manualUntil { return manualReversed }
        let parts = JourneyDirection.londonCalendar.dateComponents([.hour, .minute], from: date)
        let minute = parts.hour! * 60 + parts.minute!
        return swapMinutes > resetMinutes ? (minute >= swapMinutes || minute < resetMinutes)
            : (minute >= swapMinutes && minute < resetMinutes)
    }
    func selection(at date: Date) -> RouteSelection {
        isReversed(at: date) ? RouteSelection(starts: ends, ends: starts) : RouteSelection(starts: starts, ends: ends)
    }
    func travelDayStart(at date: Date) -> Date {
        JourneyDirection.londonCalendar.nextDate(after: date.addingTimeInterval(1),
            matching: DateComponents(hour: resetMinutes / 60, minute: resetMinutes % 60),
            matchingPolicy: .nextTime, direction: .backward)!
    }

    /// The app's travel day ends at the configured overnight reset, in London time.
    func travelDayEnd(after date: Date) -> Date {
        JourneyDirection.londonCalendar.nextDate(after: date,
            matching: DateComponents(hour: resetMinutes / 60, minute: resetMinutes % 60),
            matchingPolicy: .nextTime)!
    }

    func nextTransition(after date: Date) -> Date {
        let calendar = JourneyDirection.londonCalendar
        let reset = calendar.nextDate(after: date, matching: DateComponents(hour: resetMinutes / 60, minute: resetMinutes % 60), matchingPolicy: .nextTime)!
        let swap = calendar.nextDate(after: date, matching: DateComponents(hour: swapMinutes / 60, minute: swapMinutes % 60), matchingPolicy: .nextTime)!
        return min(reset, swap)
    }
    mutating func reverse(at date: Date) {
        if isManual(at: date) {
            resumeAutomatic()
            return
        }
        manualReversed = !isReversed(at: date)
        manualUntil = nextTransition(after: date)
    }
    mutating func resumeAutomatic() { manualReversed = nil; manualUntil = nil }
    func isManual(at date: Date) -> Bool { manualReversed != nil && (manualUntil ?? .distantPast) > date }

    static let groupID = "group.uk.co.thomascarter.TomsTrains"
    static let storageKey = "routeSettings.v1"
    static var defaults: UserDefaults { UserDefaults(suiteName: groupID) ?? .standard }
    static func load(from defaults: UserDefaults = Self.defaults) -> Self {
        guard let data = defaults.data(forKey: storageKey),
              let value = try? JSONDecoder().decode(Self.self, from: data), value.isValid else { return Self() }
        return value
    }
    func save(to defaults: UserDefaults = Self.defaults) {
        guard isValid, let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
