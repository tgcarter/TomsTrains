import Foundation

struct Departure: Identifiable, Equatable, Codable, Sendable {
    var id: String
    let origin: Station
    let destination: String
    let callingAt: [Station]
    let scheduled: Date
    let status: ServiceStatus
    var platform: String?
    let operatorName: String
    let journeyMinutes: Int?
    var disruptionReason: String?
    var scheduledArrival: Date? = nil
    var expectedArrival: Date? = nil
    var arrivalStatus: String? = nil
    var routeStops: [RouteStop]? = nil
    var observedAt: Date? = nil
    var operatorCode: String? = nil
    var actualArrival: Date? = nil
    var serviceRID: String? = nil
    // Terminal evidence comes from the full service, before display suppression.
    var terminalActual: Date? = nil
    var delayReasonCode: Int? = nil
    var cancellationReasonCode: Int? = nil
    struct ServiceOrigin: Equatable, Codable, Sendable {
        let name: String
        let scheduledDeparture: Date?
    }
    var serviceOrigin: ServiceOrigin? = nil

    /// Keep the newest report authoritative, retaining earlier calls omitted by
    /// a shorter board/details response. Never carry history between journeys.
    func mergingEarlierStops(from previous: Departure) -> Departure {
        guard id == previous.id, origin == previous.origin, scheduled == previous.scheduled,
              callingAt == previous.callingAt,
              serviceRID == nil || previous.serviceRID == nil || serviceRID == previous.serviceRID else { return self }
        if (previous.observedAt ?? .distantPast) > (observedAt ?? .distantPast) {
            return previous.mergingEarlierStops(from: self)
        }
        var latest = self
        if latest.serviceOrigin == nil {
            latest.serviceOrigin = previous.serviceOrigin
        } else if latest.serviceOrigin?.name == previous.serviceOrigin?.name,
                  latest.serviceOrigin?.scheduledDeparture == nil {
            latest.serviceOrigin = previous.serviceOrigin
        }
        guard let stops = routeStops, let boarding = stops.firstIndex(where: \.isBoarding),
              let oldStops = previous.routeStops, let oldBoarding = oldStops.firstIndex(where: \.isBoarding),
              oldBoarding > 0 else { return latest }
        func callTime(_ stop: RouteStop) -> Date? {
            stop.scheduledDeparture ?? stop.scheduledArrival ?? stop.scheduled
        }
        var prefix = Array(stops[..<boarding])
        for old in oldStops[..<oldBoarding] {
            if !prefix.contains(where: { $0.crs == old.crs && callTime($0) == callTime(old) }) {
                prefix.append(old)
            }
        }
        guard prefix.count > boarding else { return latest }
        prefix = prefix.enumerated().sorted {
            let lhs = callTime($0.element) ?? .distantPast
            let rhs = callTime($1.element) ?? .distantPast
            return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
        }.map(\.element)
        // API row IDs are positional and can collide when a prefix disappears.
        prefix = prefix.enumerated().map { index, stop in
            var retained = stop
            retained.id = "\(id)-before-\(index)"
            return retained
        }
        var result = latest
        result.routeStops = prefix + stops[boarding...]
        return result
    }

    var departureStatus: ServiceStatus {
        guard status != .cancelled,
              let actual = routeStops?.first(where: \.isBoarding)?.actualDeparture else { return status }
        let minutes = Int((actual.timeIntervalSince(scheduled) / 60).rounded())
        return minutes > 0 ? .delayed(minutes: minutes) : (minutes < 0 ? .early(minutes: -minutes) : .onTime)
    }

    /// Retain previously reported boarding data when a historical refresh omits it.
    func retainingHistoricalReport(from previous: Departure?) -> Departure {
        guard let previous, previous.id == id, previous.origin == origin,
              previous.scheduled == scheduled, previous.callingAt == callingAt else { return self }
        var result = self
        if (previous.observedAt ?? .distantPast) > (observedAt ?? .distantPast) { return previous.retainingHistoricalReport(from: self) }
        if result.serviceRID == nil, result.platform?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            result.platform = previous.platform
        }
        if let oldBoarding = previous.routeStops?.first(where: \.isBoarding),
           let index = result.routeStops?.firstIndex(where: \.isBoarding) {
            if result.serviceRID == nil, result.routeStops?[index].platform == nil { result.routeStops?[index].platform = oldBoarding.platform }
            if result.routeStops?[index].actualDeparture == nil, result.status != .cancelled {
                result.routeStops?[index].actualDeparture = oldBoarding.actualDeparture
            }
        }
        return result
    }

    /// The boarding delay is historical once underway; tracking describes arrival
    /// at the user's selected destination, which can improve or worsen en route.
    var journeyStatus: ServiceStatus {
        if status == .cancelled { return .cancelled }
        if arrivalStatus == "Cancelled" || routeStops?.contains(where: { $0.isDestination && $0.isCancelled }) == true {
            return .disrupted("Not calling at \(callingAt.first?.shortName ?? destination)")
        }
        if let scheduledArrival, let arrival = actualArrival ?? expectedArrival {
            let minutes = Int((arrival.timeIntervalSince(scheduledArrival) / 60).rounded())
            if minutes > 0 { return .delayed(minutes: minutes) }
            if minutes < 0 { return .early(minutes: -minutes) }
            return .onTime
        }
        if let arrivalStatus, !arrivalStatus.isEmpty {
            return arrivalStatus == "On time" ? .onTime : .disrupted(arrivalStatus)
        }
        return .unknown
    }

    var lastReportedStop: RouteStop? {
        guard status != .cancelled, let observedAt else { return nil }
        return routeStops?.filter { !$0.isCancelled && $0.actual.map { $0 <= observedAt } == true }
            .max { $0.actual! < $1.actual! }
    }

    var isServiceComplete: Bool {
        guard status != .cancelled, let observedAt,
              let actual = terminalActual else { return false }
        return actual <= observedAt
    }

    /// Position along the full service, independent of the selected destination.
    var routeProgress: Double? {
        guard let stops = routeStops, let last = lastReportedStop,
              let index = stops.firstIndex(where: { $0.id == last.id }) else { return nil }
        return Double(index) + (isBetweenStations ? 0.5 : 0)
    }

    var nextReportedStop: RouteStop? {
        guard let routeStops, let last = lastReportedStop,
              let index = routeStops.firstIndex(where: { $0.id == last.id }) else { return nil }
        return routeStops.dropFirst(index + 1).first(where: {
            !$0.isCancelled && ($0.actual == nil || $0.actual! > (observedAt ?? .distantPast))
        })
    }

    var isBetweenStations: Bool {
        guard let last = lastReportedStop, let departed = last.actualDeparture,
              let observedAt, departed <= observedAt, nextReportedStop != nil else { return false }
        return true
    }

    var arrivalLabel: String {
        if status == .cancelled { return "Cancelled" }
        if let expectedArrival { return RailTime.string(expectedArrival) }
        return arrivalStatus ?? "Awaiting update"
    }

    var expected: Date? {
        switch status {
        case .onTime: scheduled
        case .delayed(let minutes): scheduled.addingTimeInterval(Double(minutes * 60))
        case .early(let minutes): scheduled.addingTimeInterval(Double(-minutes * 60))
        case .cancelled, .unknown, .disrupted: nil
        }
    }

    var londonStation: Station {
        origin == .stNeots ? (callingAt.first { $0 != .stNeots } ?? .kingsCross) : origin
    }

    var routeLabel: String {
        "\(origin.shortName) → \(callingAt.first?.shortName ?? destination)"
    }

    private func isUpcoming(at date: Date) -> Bool {
        if let departed = routeStops?.first(where: \.isBoarding)?.actualDeparture, departed <= date { return false }
        // An unquantified delay remains on the board until a fresh response removes it.
        // The containing snapshot expires after five minutes.
        switch status {
        case .unknown, .disrupted: return true
        default: return (expected ?? scheduled).addingTimeInterval(60) > date
        }
    }

    static let defaultBoardLimit = 8

    static func board(from services: [Departure], at date: Date, limit: Int = defaultBoardLimit, selection: RouteSelection? = nil) -> [Departure] {
        let route = selection ?? RouteSettings().selection(at: date)
        let matching = services.filter { route.includes($0) && $0.isUpcoming(at: date) }
        var ordered = matching.filter { !$0.isCancelledAtDestination }.sorted {
            if $0.arrivalSortPriority != $1.arrivalSortPriority {
                return $0.arrivalSortPriority < $1.arrivalSortPriority
            }
            if $0.arrivalSortTime != $1.arrivalSortTime { return $0.arrivalSortTime < $1.arrivalSortTime }
            return $0.scheduled == $1.scheduled ? $0.id < $1.id : $0.scheduled < $1.scheduled
        }
        // Keep live trains in ETA order. Insert cancellations after their earlier
        // timetable neighbours, so a delayed train isn't overtaken by a train
        // that will never run. A separate insertion avoids a non-transitive sort.
        func timetableBefore(_ lhs: Departure, _ rhs: Departure) -> Bool {
            let first = lhs.scheduledArrival ?? lhs.scheduled
            let second = rhs.scheduledArrival ?? rhs.scheduled
            if first != second { return first < second }
            return lhs.scheduled == rhs.scheduled ? lhs.id < rhs.id : lhs.scheduled < rhs.scheduled
        }
        for cancelled in matching.filter(\.isCancelledAtDestination).sorted(by: timetableBefore) {
            let index = ordered.lastIndex(where: { timetableBefore($0, cancelled) }).map { $0 + 1 } ?? 0
            ordered.insert(cancelled, at: index)
        }
        return Array(ordered.prefix(limit))
    }

    var isCancelledAtDestination: Bool {
        status == .cancelled || arrivalStatus == "Cancelled"
            || routeStops?.contains(where: { $0.isDestination && $0.isCancelled }) == true
    }

    private var arrivalSortTime: Date {
        return expectedArrival ?? scheduledArrival ?? scheduled
    }

    private var arrivalSortPriority: Int {
        return expectedArrival == nil ? 1 : 0
    }
}


extension Departure {
    static func earlier(from services: [Departure], at date: Date, selection: RouteSelection, since: Date? = nil) -> [Departure] {
        var seen = Set<String>()
        return services.filter { service in
            guard selection.includes(service), service.scheduled >= (since ?? date.addingTimeInterval(-7200)) else { return false }
            // History and upcoming must use the same departure boundary.
            return !service.isUpcoming(at: date)
        }.sorted {
            if $0.scheduled != $1.scheduled { return $0.scheduled < $1.scheduled }
            return ($0.expectedArrival ?? .distantFuture) < ($1.expectedArrival ?? .distantFuture)
        }.filter { seen.insert($0.id).inserted }
    }
}
