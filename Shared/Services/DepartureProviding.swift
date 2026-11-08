import Foundation

/// The app uses this contract independently of the National Rail response shape.
protocol DepartureProviding: Sendable {
    func snapshot(at date: Date) async throws -> DepartureSnapshot
    func snapshot(at date: Date, tomorrow: Bool, limit: Int) async throws -> DepartureSnapshot
    func earlierDepartures(at date: Date, before: Date?) async throws -> [Departure]
    func serviceDetails(for departure: Departure) async throws -> Departure
    func automaticDeparture(for rule: AutoTrackingRule, at date: Date) async throws -> Departure?
}

// Lightweight test providers can implement only the operations they support.
extension DepartureProviding {
    func snapshot(at date: Date, tomorrow: Bool, limit: Int) async throws -> DepartureSnapshot {
        try await snapshot(at: date)
    }
    func earlierDepartures(at date: Date, before: Date?) async throws -> [Departure] { throw RailAPIError.unavailable }
    func serviceDetails(for departure: Departure) async throws -> Departure { throw RailAPIError.unavailable }
    func automaticDeparture(for rule: AutoTrackingRule, at date: Date) async throws -> Departure? { nil }
}
