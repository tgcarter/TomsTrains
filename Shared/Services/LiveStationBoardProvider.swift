import Foundation

enum LiveBoardMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case departures = "Departures"
    case arrivals = "Arrivals"

    var id: Self { self }
}

enum LiveBoardWindow: Hashable, Sendable {
    case current
    case earlier
    case later

    var offsetMinutes: Int {
        switch self {
        case .current: 0
        case .earlier: -120
        case .later: 60
        }
    }

    var durationMinutes: Int { self == .current ? 60 : 120 }
}

struct LiveBoardSearches: Codable, Equatable {
    private(set) var station: Station?
    private(set) var recentStations: [Station] = []
    var mode = LiveBoardMode.departures
    var filterStation: Station?

    private static let storageKey = "liveBoardSearches.v1"

    mutating func select(_ station: Station) {
        self.station = station
        if filterStation == station { filterStation = nil }
        recentStations.removeAll { $0 == station }
        recentStations.insert(station, at: 0)
        recentStations = Array(recentStations.prefix(10))
    }

    mutating func clearSelection() {
        station = nil
        filterStation = nil
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: storageKey),
              let searches = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return searches
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}

struct LiveStationBoard: Sendable {
    let station: Station
    let mode: LiveBoardMode
    let filterStation: Station?
    let updatedAt: Date
    var trains: [LiveStationTrain]
    let notices: [StationNotice]
    let servicesUnavailable: Bool
    private(set) var oldestReportAt: Date? = nil

    var expiresAt: Date { (oldestReportAt ?? updatedAt).addingTimeInterval(RailDate.reportLifetime) }

    func isFresh(at date: Date) -> Bool { date < expiresAt && RailDate.isFreshReport(updatedAt, at: date) }

    func combining(_ others: [LiveStationBoard]) -> LiveStationBoard {
        guard !others.isEmpty else { return self }
        let boards = [self] + others
        let latest = boards.max { $0.updatedAt < $1.updatedAt } ?? self
        return LiveStationBoard(station: latest.station, mode: mode, filterStation: filterStation,
            updatedAt: latest.updatedAt, trains: LiveStationTrain.ordered(boards.flatMap(\.trains)),
            notices: latest.notices, servicesUnavailable: boards.contains(where: \.servicesUnavailable),
            oldestReportAt: boards.map { $0.oldestReportAt ?? $0.updatedAt }.min())
    }
}

struct LiveBoardPages {
    enum Page {
        case loading(UUID)
        case loaded(LiveStationBoard)
        case failed

        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }

        var board: LiveStationBoard? {
            if case .loaded(let board) = self { return board }
            return nil
        }
    }

    private var pages: [LiveBoardWindow: Page] = [:]

    subscript(window: LiveBoardWindow) -> Page? { pages[window] }

    mutating func begin(_ window: LiveBoardWindow) -> UUID? {
        switch pages[window] {
        case .loaded, .loading: return nil
        case .failed, nil: break
        }
        let id = UUID()
        pages[window] = .loading(id)
        return id
    }

    mutating func finish(_ window: LiveBoardWindow, id: UUID, with page: Page?) {
        guard case .loading(let activeID) = pages[window], activeID == id else { return }
        pages[window] = page
    }

    mutating func expire(at date: Date) {
        pages = pages.filter { $0.value.board?.isFresh(at: date) ?? true }
    }
}

struct LiveStationTrain: Identifiable, Sendable {
    let id: String
    let headline: String
    let scheduled: Date
    var expected: Date?
    var actual: Date?
    var observedAt: Date
    var status: ServiceStatus
    var platform: String?
    let operatorName: String
    let operatorCode: String?
    var reason: String?
    var stops: [RouteStop]
    var rid: String? = nil
    var reasonCode: Int? = nil
    var boardTime: Date { actual ?? expected ?? scheduled }

    mutating func retainReason(from previous: LiveStationTrain) {
        guard reason == nil, (status == .cancelled) == (previous.status == .cancelled) else { return }
        switch status {
        case .onTime, .early: return
        default: break
        }
        if reasonCode == nil { reasonCode = previous.reasonCode }
        if reasonCode == previous.reasonCode { reason = previous.reason }
    }

    func explaining(using reasons: [Int: NationalRailReference.Reason]) -> LiveStationTrain {
        guard reason == nil, let reasonCode,
              let text = reasons[reasonCode]?.explanation(isCancelled: status == .cancelled) else { return self }
        var explained = self
        explained.reason = text
        return explained
    }

    func statusLabel(for mode: LiveBoardMode) -> String {
        guard actual != nil else { return status.label }
        let movement = mode == .departures ? "Departed" : "Arrived"
        return status == .onTime ? movement : "\(movement) · \(status.label.lowercased())"
    }

    static func ordered(_ trains: [LiveStationTrain]) -> [LiveStationTrain] {
        var byID: [String: LiveStationTrain] = [:]
        for train in trains {
            if let previous = byID[train.id] {
                if previous.actual != nil && train.actual == nil { continue }
                if train.observedAt < previous.observedAt && (previous.actual != nil || train.actual == nil) { continue }
            }
            byID[train.id] = train
        }
        return byID.values.sorted { lhs, rhs in
            lhs.boardTime == rhs.boardTime ? lhs.id < rhs.id : lhs.boardTime < rhs.boardTime
        }
    }

    var position: RoutePosition? {
        RoutePosition(stops: stops, observedAt: observedAt, hasEnded: status == .cancelled)
    }
}

struct LiveStationBoardProvider: Sendable {
    static let arrivalBase = URL(string:
        "https://api1.raildata.org.uk/1010-live-arrival-and-departure-boards-arr-and-dep1_1/LDBWS/api/20220120/")!

    private static let arrivalRowLimit = 25
    private let departures: NationalRailProvider
    private let arrivalsKey: String
    private let client: RailHTTPClient
    private let reference: NationalRailReference

    init(departuresKey: String = Bundle.main.object(forInfoDictionaryKey: "NationalRailBoardAPIKey") as? String ?? "",
         arrivalsKey: String = Bundle.main.object(forInfoDictionaryKey: "NationalRailArrivalsAPIKey") as? String ?? "",
         detailsKey: String = Bundle.main.object(forInfoDictionaryKey: "NationalRailQueryServicesAPIKey") as? String ?? "",
         transport: NationalRailProvider.Transport? = nil, reference: NationalRailReference = NationalRailReference()) {
        departures = NationalRailProvider(apiKey: departuresKey, detailsKey: detailsKey, transport: transport)
        self.arrivalsKey = arrivalsKey.trimmingCharacters(in: .whitespacesAndNewlines)
        client = RailHTTPClient(transport: transport)
        self.reference = reference
    }

    func board(for station: Station, mode: LiveBoardMode, filter: Station? = nil,
               window: LiveBoardWindow = .current, at now: Date) async throws -> LiveStationBoard {
        var board: LiveStationBoard
        switch mode {
        case .departures:
            let overlap = window == .current ? 1 : 0
            let start = now.addingTimeInterval(Double((window.offsetMinutes - overlap) * 60))
            let boards = try await departures.stationBoardData(origin: station, destination: filter,
                start: start, window: window.durationMinutes + overlap).map {
                    try Self.decode($0, station: station, mode: mode, filter: filter, now: now, includeRecent: window == .earlier)
                }
            guard let first = boards.first else { throw RailAPIError.unavailable }
            board = first.combining(Array(boards.dropFirst()))
        case .arrivals:
            board = try await arrivalsBoard(for: station, filter: filter, offset: window.offsetMinutes,
                duration: window.durationMinutes, at: now, includeRecent: window == .earlier)
        }
        let reasons = try await reasons(for: board.trains)
        board.trains = board.trains.map { $0.explaining(using: reasons) }
        return board
    }

    private func arrivalsBoard(for station: Station, filter: Station?, offset: Int, duration: Int,
                               at now: Date, includeRecent: Bool) async throws -> LiveStationBoard {
        let request = arrivalsRequest(for: station, filter: filter, offset: offset, duration: duration)
        let data = try await client.load(request, key: arrivalsKey)
        let board = try Self.decode(data, station: station, mode: .arrivals, filter: filter, now: now, includeRecent: includeRecent)
        let rowCount = (try DarwinDecoder.object(data)["trainServices"] as? [[String: Any]])?.count ?? 0
        // The public feed caps the mixed board at 25 rows without marking it as truncated.
        // Split a full response while the second request can still start before +120 minutes.
        let split = min(duration / 2, 119 - offset)
        guard !board.servicesUnavailable, rowCount >= Self.arrivalRowLimit, split > 0 else { return board }
        async let first = arrivalsBoard(for: station, filter: filter, offset: offset, duration: split,
            at: now, includeRecent: includeRecent)
        async let second = arrivalsBoard(for: station, filter: filter, offset: offset + split, duration: duration - split,
            at: now, includeRecent: includeRecent)
        return try await first.combining([second])
    }

    private func arrivalsRequest(for station: Station, filter: Station?, offset: Int, duration: Int) -> URLRequest {
        let url = Self.arrivalBase.appendingPathComponent("GetArrDepBoardWithDetails").appendingPathComponent(station.rawValue)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        var query = [URLQueryItem(name: "numRows", value: String(Self.arrivalRowLimit)),
            URLQueryItem(name: "timeWindow", value: String(duration))]
        if offset != 0 { query.append(URLQueryItem(name: "timeOffset", value: String(offset))) }
        if let filter {
            query.append(URLQueryItem(name: "filterCrs", value: filter.rawValue))
            query.append(URLQueryItem(name: "filterType", value: "from"))
        }
        components.queryItems = query
        return URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
    }

    func details(for train: LiveStationTrain, at station: Station, filter: Station?, now: Date) async throws -> LiveStationTrain {
        var updated: LiveStationTrain
        if let rid = train.rid {
            let data = try await departures.serviceDetailsData(forRID: rid)
            updated = try Self.decodeDetails(data, for: train, at: station, now: now)
        } else {
            // Arrivals use public service IDs. Keep looking for the same arrival
            // briefly after its time so the sheet can receive the arrival report.
            let board = try await arrivalsBoard(for: station, filter: filter, offset: -10, duration: 70,
                at: now, includeRecent: true)
            guard let match = board.trains.first(where: { $0.id == train.id }) else { throw RailAPIError.serviceNotFound }
            guard match.observedAt >= train.observedAt else { return train }
            updated = match
            updated.retainReason(from: train)
        }
        return updated.explaining(using: try await reasons(for: [updated]))
    }

    private func reasons(for trains: [LiveStationTrain]) async throws -> [Int: NationalRailReference.Reason] {
        guard trains.contains(where: { $0.reasonCode != nil && $0.reason == nil }) else { return [:] }
        do { return try await reference.reasons() }
        catch {
            try Task.checkCancellation()
            return [:]
        }
    }

    static func decodeDetails(_ data: Data, for train: LiveStationTrain, at station: Station, now: Date) throws -> LiveStationTrain {
        let object = try DarwinDecoder.object(data)
        guard let rid = train.rid, object["rid"] as? String == rid,
              let observed = DarwinDecoder.time(object["generatedAt"]), RailDate.isFreshReport(observed, at: now) else {
            throw RailAPIError.invalidResponse
        }
        guard observed >= train.observedAt else { return train }
        var updated = train
        updated.observedAt = observed
        if DarwinDecoder.isWithdrawn(object) {
            updated.status = .cancelled
            updated.expected = nil
            updated.actual = nil
            updated.platform = nil
            updated.reason = DarwinDecoder.reasonText(object["cancelReason"])
            updated.reasonCode = DarwinDecoder.reasonCode(object["cancelReason"])
            updated.retainReason(from: train)
            for index in updated.stops.indices where updated.stops[index].actual == nil {
                updated.stops[index].isCancelled = true
            }
            return updated
        }
        guard let locations = object["locations"] as? [[String: Any]],
              let index = locations.firstIndex(where: {
                  $0["crs"] as? String == station.rawValue && DarwinDecoder.time($0["std"]) == train.scheduled
              }) else { throw RailAPIError.invalidResponse }
        let call = locations[index]
        let status = DarwinDecoder.status(call, arrival: false, observed: observed)
        updated.status = status
        updated.actual = status == .cancelled ? nil : DarwinDecoder.reported(call, arrival: false, observed: observed)
        updated.expected = status == .cancelled ? nil : DarwinDecoder.forecast(call, arrival: false)
        updated.platform = DarwinDecoder.platform(call, observed: observed)
        let reasonKey = status == .cancelled ? "cancelReason" : "delayReason"
        let reason = call[reasonKey].flatMap { $0 is NSNull ? nil : $0 } ?? object[reasonKey]
        updated.reason = DarwinDecoder.reasonText(reason)
        updated.reasonCode = DarwinDecoder.reasonCode(reason)
        updated.retainReason(from: train)
        updated.stops = DarwinDecoder.routeStops(locations, boarding: index, destination: nil, observed: observed,
            id: train.id, includesSuppressedCancellations: true)
        return updated
    }

    static func decode(_ data: Data, station: Station, mode: LiveBoardMode, filter: Station? = nil,
                       now: Date, includeRecent: Bool = false) throws -> LiveStationBoard {
        let object = try DarwinDecoder.object(data)
        guard object["crs"] as? String == station.rawValue,
              let observed = DarwinDecoder.time(object["generatedAt"]) else { throw RailAPIError.invalidResponse }
        guard RailDate.isFreshReport(observed, at: now) else {
            throw RailAPIError.unavailable
        }
        let rawServices = object["trainServices"]
        guard rawServices == nil || rawServices is NSNull || rawServices is [[String: Any]] else {
            throw RailAPIError.invalidResponse
        }
        var station = station
        station.displayName = object["locationName"] as? String ?? station.displayName
        let unavailable = object["servicesAreUnavailable"] as? Bool == true || object["areServicesAvailable"] as? Bool == false
        let services = unavailable ? [] : (rawServices as? [[String: Any]] ?? [])
        let trains = services.compactMap { service -> LiveStationTrain? in
            if let filter, !matches(service, mode: mode, filter: filter) { return nil }
            return switch mode {
            case .departures: departure(service, at: station, observed: observed,
                hidePlatforms: object["platformsAreHidden"] as? Bool == true, includeRecent: includeRecent)
            case .arrivals: arrival(service, at: station, observed: observed, hidePlatforms: object["platformAvailable"] as? Bool == false)
            }
        }.filter { train in
            includeRecent || (train.actual.map { $0 >= observed.addingTimeInterval(-60) } ?? true)
        }

        let rawNotices = object["nrccMessages"] as? [[String: Any]] ?? []
        let notices = rawNotices.map { notice -> [String: Any] in
            if let text = notice["Value"] as? String {
                return ["xhtmlMessage": text, "category": "trainservice"]
            }
            return notice
        }
        return LiveStationBoard(station: station, mode: mode, filterStation: filter, updatedAt: observed, trains: LiveStationTrain.ordered(trains),
            notices: StationNotice.decode(notices, station: station), servicesUnavailable: unavailable)
    }

    private static func matches(_ service: [String: Any], mode: LiveBoardMode, filter: Station) -> Bool {
        let serviceCancelled = DarwinDecoder.isWithdrawn(service) || (service["eta"] as? String)?.lowercased() == "cancelled"
        if service["filterLocationCancelled"] as? Bool == true && !serviceCancelled { return false }
        func callsThere(_ call: [String: Any]) -> Bool {
            call["crs"] as? String == filter.rawValue && (serviceCancelled || !DarwinDecoder.isWithdrawn(call))
        }
        switch mode {
        case .departures:
            let onward = service["subsequentLocations"] as? [[String: Any]] ?? []
            if onward.contains(where: { DarwinDecoder.isPassengerCall($0) && callsThere($0) }) { return true }
            return (service["currentDestinations"] as? [[String: Any]] ?? service["destination"] as? [[String: Any]] ?? [])
                .contains { callsThere($0) && $0["isOperationalEndPoint"] as? Bool != true && $0["assocIsCancelled"] as? Bool != true }
        case .arrivals:
            let previous = service["previousCallingPoints"] as? [[String: Any]] ?? []
            let calls = previous.filter { $0["serviceChangeRequired"] as? Bool != true && $0["assocIsCancelled"] as? Bool != true }
                .flatMap { $0["callingPoint"] as? [[String: Any]] ?? [] }
            if calls.contains(where: callsThere) { return true }
            return (service["currentOrigins"] as? [[String: Any]] ?? service["origin"] as? [[String: Any]] ?? [])
                .contains { callsThere($0) && $0["assocIsCancelled"] as? Bool != true }
        }
    }

    private static func departure(_ service: [String: Any], at station: Station, observed: Date,
                                  hidePlatforms: Bool, includeRecent: Bool) -> LiveStationTrain? {
        guard service["isPassengerService"] as? Bool != false, service["isOperationalCall"] as? Bool != true,
              let id = service["rid"] as? String, let scheduled = DarwinDecoder.time(service["std"]) else { return nil }
        let status = DarwinDecoder.status(service, arrival: false, observed: observed)
        let actual = status == .cancelled ? nil : DarwinDecoder.reported(service, arrival: false, observed: observed)
        guard service["serviceIsSupressed"] as? Bool != true || (includeRecent && actual != nil) else { return nil }
        let expected = status == .cancelled ? nil : DarwinDecoder.forecast(service, arrival: false)
        let reason = service[status == .cancelled ? "cancelReason" : "delayReason"]
        let previous = service["previousLocations"] as? [[String: Any]] ?? []
        let subsequent = service["subsequentLocations"] as? [[String: Any]] ?? []
        var call = service
        call["crs"] = station.rawValue
        call["locationName"] = station.name
        let hidesPlatform = hidePlatforms && (!includeRecent || actual == nil)
        let platform = hidesPlatform ? nil : DarwinDecoder.platform(service, observed: observed)
        if hidesPlatform { call["platform"] = nil }
        let identity = "\(id)-\(scheduled.timeIntervalSinceReferenceDate)"
        let route = DarwinDecoder.routeStops(previous + [call] + subsequent, boarding: previous.count, destination: nil,
            observed: observed, id: identity)
        let destination = names(in: service["currentDestinations"]) ?? names(in: service["destination"])
        return LiveStationTrain(id: identity, headline: destination.map { "To \($0)" } ?? "Destination unavailable",
            scheduled: scheduled, expected: expected, actual: actual, observedAt: observed, status: status, platform: platform,
            operatorName: service["operator"] as? String ?? "National Rail", operatorCode: service["operatorCode"] as? String,
            reason: DarwinDecoder.reasonText(reason), stops: route, rid: id, reasonCode: DarwinDecoder.reasonCode(reason))
    }

    private static func arrival(_ service: [String: Any], at station: Station, observed: Date,
                                hidePlatforms: Bool) -> LiveStationTrain? {
        guard service["serviceType"] as? String != "bus", service["serviceType"] as? String != "ferry",
              let id = service["serviceID"] as? String, let scheduled = publicTime(service["sta"], near: observed) else { return nil }
        let timing = publicTiming(scheduled: scheduled, estimate: service["eta"], report: service["ata"],
            cancelled: service["isCancelled"] as? Bool == true, observed: observed)
        let reason = service[timing.status == .cancelled ? "cancelReason" : "delayReason"]
        let previous = publicStops(service["previousCallingPoints"], beforeStation: true, reference: scheduled, observed: observed, id: id)
        let subsequent = publicStops(service["subsequentCallingPoints"], beforeStation: false, reference: scheduled, observed: observed, id: id)
        let platform = hidePlatforms ? nil : service["platform"] as? String
        let call = RouteStop(id: "\(id)-station", crs: station.rawValue, name: station.name,
            scheduled: scheduled, expected: timing.expected, actual: timing.actual,
            isCancelled: timing.status == .cancelled, estimate: timing.estimate,
            isBoarding: false, isDestination: true, platform: platform, reportedAt: observed,
            scheduledArrival: scheduled, forecastEvent: .arrival)
        let origin = names(in: service["currentOrigins"]) ?? names(in: service["origin"])
        return LiveStationTrain(id: id, headline: origin.map { "From \($0)" } ?? "Origin unavailable",
            scheduled: scheduled, expected: timing.expected, actual: timing.actual, observedAt: observed,
            status: timing.status, platform: platform,
            operatorName: service["operator"] as? String ?? "National Rail", operatorCode: service["operatorCode"] as? String,
            reason: DarwinDecoder.reasonText(reason), stops: previous + [call] + subsequent,
            reasonCode: DarwinDecoder.reasonCode(reason))
    }

    private static func names(in value: Any?) -> String? {
        let names = (value as? [[String: Any]] ?? []).compactMap { location -> String? in
            guard location["isOperationalEndPoint"] as? Bool != true,
                  let name = location["locationName"] as? String, !name.isEmpty else { return nil }
            if let via = location["via"] as? String, !via.isEmpty {
                return name + " " + via
            }
            return name
        }
        return names.isEmpty ? nil : names.joined(separator: " / ")
    }

    private static func publicTime(_ value: Any?, near reference: Date) -> Date? {
        guard let clock = value as? String else { return nil }
        return RailDate.clock(clock.trimmingCharacters(in: CharacterSet(charactersIn: "* ")), nearest: reference)
    }

    private static func publicTiming(scheduled: Date, estimate: Any?, report: Any?, cancelled: Bool,
                                     observed: Date) -> (expected: Date?, actual: Date?, status: ServiceStatus, estimate: String?) {
        let label = estimate as? String
        if cancelled || label?.lowercased() == "cancelled" { return (nil, nil, .cancelled, nil) }
        if let actual = publicTime(report, near: scheduled), actual <= observed {
            return (nil, actual, .timing(scheduled: scheduled, reported: actual), nil)
        }
        if label?.lowercased() == "on time" { return (scheduled, nil, .onTime, nil) }
        if let forecast = publicTime(estimate, near: scheduled) {
            return (forecast, nil, .timing(scheduled: scheduled, reported: forecast), nil)
        }
        if label?.lowercased() == "delayed" { return (nil, nil, .delayedWithoutEstimate, "Delayed") }
        return (nil, nil, .unknown, nil)
    }

    private static func publicStops(_ value: Any?, beforeStation: Bool, reference: Date, observed: Date, id: String) -> [RouteStop] {
        // Darwin puts the through train first. Other lists describe portions that attach or split.
        guard let primary = (value as? [[String: Any]])?.first,
              let calls = primary["callingPoint"] as? [[String: Any]] else { return [] }
        let ordered = beforeStation ? Array(calls.reversed()) : calls
        let calendar = JourneyDirection.londonCalendar
        var cursor = reference
        let result = ordered.enumerated().compactMap { index, call -> RouteStop? in
            guard let code = call["crs"] as? String, let name = call["locationName"] as? String,
                  var scheduled = publicTime(call["st"], near: cursor) else { return nil }
            if beforeStation && scheduled > cursor {
                scheduled = calendar.date(byAdding: .day, value: -1, to: scheduled) ?? scheduled
            } else if !beforeStation && scheduled < cursor {
                scheduled = calendar.date(byAdding: .day, value: 1, to: scheduled) ?? scheduled
            }
            cursor = scheduled
            let timing = publicTiming(scheduled: scheduled, estimate: call["et"], report: call["at"],
                cancelled: call["isCancelled"] as? Bool == true, observed: observed)
            return RouteStop(id: "\(id)-\(beforeStation)-\(index)", crs: code, name: name,
                scheduled: scheduled, expected: timing.expected, actual: timing.actual,
                isCancelled: timing.status == .cancelled, estimate: timing.estimate,
                isBoarding: false, isDestination: false, reportedAt: observed,
                scheduledDeparture: beforeStation ? scheduled : nil, actualDeparture: beforeStation ? timing.actual : nil,
                scheduledArrival: beforeStation ? nil : scheduled, forecastEvent: beforeStation ? .departure : .arrival)
        }
        return beforeStation ? Array(result.reversed()) : result
    }
}
