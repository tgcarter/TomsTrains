import Foundation

/// Presentation decisions shared by the detail summary and its regression tests.
struct ServiceSummary {
    let service: Departure
    var isTracked = false

    var title: String {
        guard let origin = service.serviceOrigin else { return "To \(service.destination)" }
        let time = origin.scheduledDeparture.map { "\(RailTime.string($0)) " } ?? ""
        return "\(time)\(origin.name) to \(service.destination)"
    }

    var status: ServiceStatus {
        if service.isCancelledAtDestination { return service.journeyStatus }
        let departed = service.routeStops?.first(where: \.isBoarding)?.actualDeparture != nil
        return isTracked || departed || service.actualArrival != nil ? service.journeyStatus : service.status
    }

    var reason: String? {
        guard let reason = service.disruptionReason?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reason.isEmpty else { return nil }
        return reason
    }

    var showsStatusPanel: Bool {
        if service.isCancelledAtDestination { return true }
        switch status {
        case .onTime, .early: return false
        default: return reason != nil
        }
    }

    var position: String? {
        guard !service.isCancelledAtDestination, let stop = service.lastReportedStop else { return nil }
        if service.isBetweenStations, let next = service.nextReportedStop {
            return "Between \(stop.name) and \(next.name)"
        }
        return "Last reported at \(stop.name)"
    }

    var actualDeparture: Date? {
        guard !service.isCancelledAtDestination else { return nil }
        return service.routeStops?.first(where: \.isBoarding)?.actualDeparture
    }

    var expectedDeparture: Date? {
        guard actualDeparture == nil, !service.isCancelledAtDestination else { return nil }
        return differing(service.expected, from: service.scheduled)
    }

    var expectedArrival: Date? {
        guard service.actualArrival == nil, !service.isCancelledAtDestination else { return nil }
        return differing(service.expectedArrival, from: service.scheduledArrival)
    }

    private func differing(_ time: Date?, from scheduled: Date?) -> Date? {
        guard let time else { return nil }
        if let scheduled, JourneyDirection.londonCalendar.isDate(time, equalTo: scheduled, toGranularity: .minute) {
            return nil
        }
        return time
    }
}
