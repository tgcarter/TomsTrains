import Foundation

struct TrackedJourney: Codable, Identifiable, Equatable, Sendable {
    var departure: Departure
    var id: String { departure.id }

    var hasArrived: Bool { arrivalReport != nil }

    var reportedArrival: Date? {
        guard let observed = departure.observedAt, !departure.isCancelledAtDestination else { return nil }
        if let actual = departure.actualArrival, actual <= observed { return actual }
        // RouteStop.actual holds the arrival when there is no actual departure.
        guard let stop = departure.routeStops?.first(where: \.isDestination), stop.actualDeparture == nil,
              let actual = stop.actual, actual >= departure.scheduled, actual <= observed else { return nil }
        return actual
    }

    var reportedDepartureFromDestination: Date? {
        guard let observed = departure.observedAt, !departure.isCancelledAtDestination,
              let actual = departure.routeStops?.first(where: \.isDestination)?.actualDeparture,
              actual >= departure.scheduled, actual <= observed else { return nil }
        return actual
    }

    private var arrivalReport: Date? {
        guard let observed = departure.observedAt, !departure.isCancelledAtDestination else { return nil }
        if let reportedArrival { return reportedArrival }
        let stops = departure.routeStops ?? []
        guard let destinationIndex = stops.firstIndex(where: \.isDestination) else { return nil }
        // An actual report at or beyond the selected destination proves the
        // journey has reached it, even when that station's own report is absent.
        // Estimates and cancelled calls must never count as arrival evidence.
        return stops[destinationIndex...].filter { !$0.isCancelled }
            .flatMap { [$0.actual, $0.actualDeparture].compactMap { $0 } }
            .filter { $0 >= departure.scheduled && $0 <= observed }.min()
    }

    /// Completed journeys stay on the board until the travel-day reset.
    var hasFinished: Bool { hasArrived || departure.isServiceComplete }

    /// History records the full route even after the passenger reaches their stop.
    var needsLiveDetails: Bool { !departure.isServiceComplete }

    func isCurrent(since dayStart: Date) -> Bool {
        if departure.scheduled >= dayStart { return true }
        if let arrivalReport { return arrivalReport >= dayStart }
        guard !hasFinished, !departure.isCancelledAtDestination else { return false }
        // A train due to arrive after the reset still belongs on the board while en route.
        return (departure.expectedArrival ?? departure.scheduledArrival ?? departure.expected ?? departure.scheduled) >= dayStart
    }

    func accepting(_ update: Departure) -> TrackedJourney {
        guard update.id == id, update.origin == departure.origin,
              update.callingAt == departure.callingAt,
              (update.observedAt ?? .distantPast) >= (departure.observedAt ?? .distantPast)
        else { return self }
        var merged = update.mergingEarlierStops(from: departure)
        merged.scheduledArrival = merged.scheduledArrival ?? departure.scheduledArrival
        if !merged.isCancelledAtDestination {
            merged.actualArrival = TrackedJourney(departure: merged).reportedArrival ?? reportedArrival
            if let previousDeparture = reportedDepartureFromDestination,
               let index = merged.routeStops?.firstIndex(where: \.isDestination),
               merged.routeStops?[index].actualDeparture == nil {
                merged.routeStops?[index].actualDeparture = previousDeparture
                merged.routeStops?[index].actual = previousDeparture
            }
        }
        let updated = TrackedJourney(departure: merged)
        if hasArrived && !updated.hasArrived || hasFinished && !updated.hasFinished { return self }
        if departure.isServiceComplete {
            guard merged.isServiceComplete else { return self }
            // A station-board refresh can end its stop list before the saved terminus.
            if let lastStop = departure.lastReportedStop,
               merged.routeStops?.contains(where: {
                   $0.crs == lastStop.crs && $0.scheduled == lastStop.scheduled && !$0.isCancelled && $0.actual != nil
               }) != true { return self }
        }
        return updated
    }
}
