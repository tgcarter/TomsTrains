import Foundation

struct TrackedJourney: Codable, Identifiable, Equatable, Sendable {
    var departure: Departure
    var id: String { departure.id }

    var hasArrived: Bool {
        guard let observed = departure.observedAt, departure.status != .cancelled,
              departure.arrivalStatus != "Cancelled" else { return false }
        let stops = departure.routeStops ?? []
        let destinationIndex = stops.firstIndex(where: \.isDestination)
        if let destinationIndex, stops[destinationIndex].isCancelled { return false }
        if let actual = departure.actualArrival, actual <= observed { return true }
        guard let destinationIndex else { return false }
        // An actual report at or beyond the selected destination proves the
        // journey has reached it, even when that station's own report is absent.
        // Estimates and cancelled calls must never count as arrival evidence.
        return stops[destinationIndex...].contains { stop in
            !stop.isCancelled && [stop.actual, stop.actualDeparture].compactMap { $0 }.contains {
                $0 >= departure.scheduled && $0 <= observed
            }
        }
    }

    /// Completion ends tracking even if the selected call was cancelled.
    var hasFinished: Bool { hasArrived || departure.isServiceComplete }

    func accepting(_ update: Departure) -> TrackedJourney {
        guard update.id == id, update.origin == departure.origin,
              update.callingAt == departure.callingAt,
              (update.observedAt ?? .distantPast) >= (departure.observedAt ?? .distantPast)
        else { return self }
        return TrackedJourney(departure: update.mergingEarlierStops(from: departure))
    }
}
