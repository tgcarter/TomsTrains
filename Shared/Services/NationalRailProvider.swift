import Foundation

struct NationalRailProvider: DepartureProviding {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let settings: RouteSettings
    private let apiKey: String
    private let detailsKey: String
    private let client: RailHTTPClient
    private let reference: NationalRailReference
    static let baseURL = URL(string: "https://api1.raildata.org.uk/1010-live-departure-board---staff-version1_0/LDBSVWS/api/20220120/")!
    static let detailsURL = URL(string: "https://api1.raildata.org.uk/1010-query-services-and-service-details1_0/LDBSVWS/api/20220120/")!

    init(settings: RouteSettings = RouteSettings(),
         apiKey: String = Bundle.main.object(forInfoDictionaryKey: "NationalRailBoardAPIKey") as? String ?? "",
         detailsKey: String = Bundle.main.object(forInfoDictionaryKey: "NationalRailQueryServicesAPIKey") as? String ?? "",
         transport: Transport? = nil, reference: NationalRailReference = NationalRailReference()) {
        self.settings = settings
        self.reference = reference
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.detailsKey = detailsKey.trimmingCharacters(in: .whitespacesAndNewlines)
        client = RailHTTPClient(transport: transport)
    }

    func snapshot(at date: Date) async throws -> DepartureSnapshot {
        try await snapshot(at: date, tomorrow: false)
    }

    func snapshot(at date: Date, tomorrow: Bool, limit: Int = Departure.defaultBoardLimit) async throws -> DepartureSnapshot {
        let selection = settings.selection(at: date)
        var loaded: [DepartureSnapshot] = []
        var departures: [Departure] = []
        var searchedUntil = date
        // The API returns a time window, not the next N trains. Search both origins
        // in each window, including after midnight, until the requested number of trains is available.
        // Do not fill tonight's board with the following morning's services.
        let searchStart = tomorrow ? settings.travelDayEnd(after: date) : date.addingTimeInterval(-60)
        let cutoff = settings.travelDayEnd(after: tomorrow ? searchStart : date)
        for offset in stride(from: 0, to: 1560, by: 120) {
            try Task.checkCancellation()
            let start = searchStart.addingTimeInterval(Double(offset * 60))
            guard start < cutoff else { break }
            let window = min(120, max(1, Int(ceil(cutoff.timeIntervalSince(start) / 60))))
            loaded += try await boards(selection: selection, start: start, window: window)
            var seen = Set<String>()
            departures = Departure.board(from: loaded.flatMap(\.departures), at: date,
                limit: Int.max, selection: selection).filter { (!tomorrow || $0.scheduled >= searchStart) && $0.scheduled < cutoff && seen.insert($0.id).inserted }
            searchedUntil = min(cutoff, start.addingTimeInterval(Double(window * 60)))
            // A later departure may overtake a slower train. Search through the
            // latest arrival in the visible page before declaring it complete.
            let page = Array(departures.prefix(limit))
            if page.count == limit,
               page.allSatisfy({ $0.expectedArrival != nil && $0.status != .cancelled && $0.arrivalStatus != "Cancelled" }),
               let latestArrival = page.compactMap(\.expectedArrival).max(), searchedUntil >= latestArrival {
                break
            }
        }
        do { departures = try await reference.explaining(departures) }
        catch { try Task.checkCancellation() }
        var noticeIDs = Set<String>()
        let notices = loaded.flatMap { $0.stationNotices ?? [] }
            .filter { noticeIDs.insert($0.id).inserted }.sorted { $0.id < $1.id }
        return DepartureSnapshot(fetchedAt: loaded.map(\.fetchedAt).min() ?? date,
            departures: departures,
            stationNotices: notices, routeKey: selection.key,
            hasLaterDepartures: searchedUntil < cutoff || departures.count > limit)
    }

    func automaticDeparture(for rule: AutoTrackingRule, at date: Date) async throws -> Departure? {
        guard rule.isDue(on: date), let scheduled = rule.scheduled(on: date) else { return nil }
        let loaded = try await stationBoards(origin: rule.origin, destination: rule.destination,
            start: scheduled, window: 1)
        guard loaded.allSatisfy({ date.timeIntervalSince($0.fetchedAt) < 300 && date.timeIntervalSince($0.fetchedAt) >= -60 }) else {
            throw RailAPIError.unavailable
        }
        var seen = Set<String>()
        let matches = loaded.flatMap(\.departures).filter {
            rule.matches($0) && $0.scheduled == scheduled && seen.insert($0.id).inserted
        }
        // Never silently pick another service when the timetable has changed or is ambiguous.
        return matches.count == 1 ? matches.first : nil
    }

    static func historyStart(before: Date, now: Date, settings: RouteSettings = RouteSettings()) -> Date {
        max(settings.travelDayStart(at: now), before.addingTimeInterval(-7200))
    }

    /// Page through the current travel day’s retained station-board data. This is not an archive guarantee.
    func earlierDepartures(at date: Date, before: Date? = nil) async throws -> [Departure] {
        let end = min(before ?? date, date)
        let start = Self.historyStart(before: end, now: date, settings: settings)
        guard end > start else { return [] }
        let selection = settings.selection(at: date)
        let boards = try await boards(selection: selection, start: start,
            window: min(120, max(1, Int(ceil(end.timeIntervalSince(start) / 60)))))
        guard boards.allSatisfy({ $0.isFresh(at: date, settings: settings) }) else { throw RailAPIError.unavailable }
        return Departure.earlier(from: boards.flatMap(\.departures).filter { $0.scheduled < end },
            at: date, selection: selection, since: start)
    }

    private func boards(selection: RouteSelection, start: Date, window: Int) async throws -> [DepartureSnapshot] {
        let pairs = selection.starts.flatMap { origin in selection.ends.map { (origin, $0) } }
        var result: [DepartureSnapshot] = []
        for offset in stride(from: 0, to: pairs.count, by: 4) {
            try Task.checkCancellation()
            result += try await withThrowingTaskGroup(of: [DepartureSnapshot].self) { group in
                for (origin, destination) in pairs[offset..<min(offset + 4, pairs.count)] {
                    group.addTask {
                        try await stationBoards(origin: origin, destination: destination, start: start, window: window)
                    }
                }
                var values: [DepartureSnapshot] = []
                for try await board in group { values += board }
                return values
            }
        }
        return result
    }

    private func stationBoards(origin: Station, destination: Station, start: Date, window: Int) async throws -> [DepartureSnapshot] {
        let end = start.addingTimeInterval(Double(window * 60))
        var cursor = start
        var results: [DepartureSnapshot] = []
        // Follow explicitly truncated boards; never silently drop a busy station's services.
        while cursor < end {
            try Task.checkCancellation()
            let request = request(origin: origin, destination: destination, start: cursor,
                window: max(1, Int(ceil(end.timeIntervalSince(cursor) / 60))))
            let data = try await send(request, key: apiKey)
            let object = try DarwinDecoder.object(data)
            results.append(try DarwinDecoder.decode(data, origin: origin, destination: destination, now: start))
            guard object["isTruncated"] as? Bool == true else { break }
            let services = object["trainServices"] as? [[String: Any]] ?? []
            guard let last = services.compactMap({ DarwinDecoder.time($0["std"]) }).max(), last >= cursor else {
                throw RailAPIError.invalidResponse
            }
            cursor = last.addingTimeInterval(1)
        }
        return results
    }

    func request(origin: Station, destination: Station, start: Date, window: Int = 120) -> URLRequest {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = JourneyDirection.londonCalendar.timeZone
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        var components = URLComponents(url: Self.baseURL.appendingPathComponent("GetDepBoardWithDetails")
            .appendingPathComponent(origin.rawValue).appendingPathComponent(formatter.string(from: start)), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "numRows", value: "150"),
            URLQueryItem(name: "filterCrs", value: destination.rawValue), URLQueryItem(name: "filterType", value: "to"),
            URLQueryItem(name: "timeWindow", value: String(window))]
        return URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
    }

    func serviceDetails(for departure: Departure) async throws -> Departure {
        guard let destination = departure.callingAt.first else { throw RailAPIError.invalidResponse }
        var rid = departure.serviceRID
        if rid == nil {
            // Migrate saved public-board IDs using the boarding date/time and operator.
            let boards = try await stationBoards(origin: departure.origin, destination: destination,
                start: departure.scheduled, window: 1)
            let matches = boards.flatMap(\.departures).filter {
                $0.scheduled == departure.scheduled && $0.operatorCode == departure.operatorCode
            }
            let rids = Set(matches.compactMap(\.serviceRID))
            guard rids.count == 1 else { throw RailAPIError.unavailable }
            rid = rids.first
        }
        guard let rid else { throw RailAPIError.unavailable }
        let request = URLRequest(url: Self.detailsURL.appendingPathComponent("GetServiceDetailsByRID").appendingPathComponent(rid),
            cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        let data = try await send(request, key: detailsKey)
        let object = try DarwinDecoder.object(data)
        guard object["rid"] as? String == rid,
              let observed = DarwinDecoder.time(object["generatedAt"]),
              let locations = object["locations"] as? [[String: Any]],
              let boarding = locations.firstIndex(where: { $0["crs"] as? String == departure.origin.rawValue && DarwinDecoder.time($0["std"]) == departure.scheduled }),
              let result = DarwinDecoder.departure(service: object, locations: locations, boarding: boarding,
                destination: destination, observed: observed, id: departure.id, hasCompleteRoute: true) else { throw RailAPIError.invalidResponse }
        let merged = result.mergingEarlierStops(from: departure)
        do { return try await reference.explaining([merged]).first ?? merged }
        catch {
            try Task.checkCancellation()
            // A reference-data outage must never prevent fresh train updates.
            return merged
        }
    }

    private func send(_ request: URLRequest, key: String) async throws -> Data {
        try await client.load(request, key: key)
    }
}
