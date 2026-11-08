import Foundation

struct RouteStop: Identifiable, Equatable, Codable, Sendable {
    var id: String
    let crs: String
    let name: String
    let scheduled: Date?
    let expected: Date?
    var actual: Date?
    let isCancelled: Bool
    let estimate: String?
    let isBoarding: Bool
    let isDestination: Bool
    var platform: String? = nil
    var reportedAt: Date? = nil
    var scheduledDeparture: Date? = nil
    var actualDeparture: Date? = nil
    var scheduledArrival: Date? = nil
    enum ForecastEvent: String, Codable, Sendable { case arrival, departure }
    var forecastEvent: ForecastEvent? = nil

    var timingStatus: ServiceStatus {
        if isCancelled { return .cancelled }
        let baseline = timingBaseline
        guard let baseline, let time = actual ?? expected else {
            return estimate.map { .disrupted($0) } ?? .unknown
        }
        let minutes = Int((time.timeIntervalSince(baseline) / 60).rounded())
        if minutes > 0 { return .delayed(minutes: minutes) }
        if minutes < 0 { return .early(minutes: -minutes) }
        return .onTime
    }

    var timingBaseline: Date? {
        if actualDeparture != nil {
            return scheduledDeparture ?? scheduled
        } else if actual != nil {
            return scheduledArrival ?? (isBoarding ? nil : scheduled)
        } else {
            switch forecastEvent {
            case .departure: return scheduledDeparture
            case .arrival: return scheduledArrival
            case nil: return scheduled
            }
        }
    }

    /// Match the event being shown, and compare at the same minute precision as the UI.
    var differingScheduledTime: Date? {
        guard !isCancelled, let baseline = timingBaseline, let time = actual ?? expected,
              !JourneyDirection.londonCalendar.isDate(time, equalTo: baseline, toGranularity: .minute)
        else { return nil }
        return baseline
    }

    var timingLabel: String {
        if isCancelled { return "Not calling" }
        if actual != nil {
            let event = actualDeparture != nil ? "Departed" : "Arrived"
            switch timingStatus {
            case .onTime: return "\(event) on time"
            case .delayed(let minutes): return "\(event) \(minutes) min late"
            case .early(let minutes): return "\(event) \(minutes) min early"
            default: return event
            }
        }
        switch timingStatus {
        case .onTime: return "Expected on time"
        case .delayed(let minutes): return "Expected \(minutes) min late"
        case .early(let minutes): return "Expected \(minutes) min early"
        case .disrupted(let message): return message
        default: return "Awaiting update"
        }
    }

    var timeLabel: String {
        if isCancelled { return "Cancelled" }
        if let actual { return RailTime.string(actual) }
        if let expected { return RailTime.string(expected) }
        return estimate ?? scheduled.map(RailTime.string) ?? "—"
    }
}
