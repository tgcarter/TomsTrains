import Foundation

/// Daily reference lookups share one credential and cache across app consumers.
struct NationalRailReference: Sendable {
    static let baseURL = URL(string: "https://api1.raildata.org.uk/1010-reference-data1_0/LDBSVWS/api/ref/20211101/")!
    private let apiKey: String
    private let client: RailHTTPClient

    init(apiKey: String = Bundle.main.object(forInfoDictionaryKey: "NationalRailReferenceAPIKey") as? String ?? "",
         transport: NationalRailProvider.Transport? = nil) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        client = RailHTTPClient(transport: transport)
    }

    struct Reason: Decodable, Sendable {
        let code: Int
        let lateReason: String?
        let cancReason: String?
    }

    static func decodeReasons(_ data: Data) throws -> [Int: Reason] {
        guard let rows = try? JSONDecoder().decode([Reason].self, from: data) else { throw RailAPIError.invalidResponse }
        return Dictionary(rows.map { ($0.code, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    func explaining(_ departures: [Departure]) async throws -> [Departure] {
        guard departures.contains(where: { $0.delayReasonCode != nil || $0.cancellationReasonCode != nil }) else { return departures }
        let reasons = try Self.decodeReasons(await load("GetReasonCodeList"))
        return departures.map { departure in
            var result = departure
            let text: String?
            if departure.isCancelledAtDestination {
                text = departure.cancellationReasonCode.flatMap { reasons[$0]?.cancReason }
            } else {
                text = departure.delayReasonCode.flatMap { reasons[$0]?.lateReason }
            }
            if let text {
                let cleaned = StationNotice.plainText(text)
                if !cleaned.isEmpty { result.disruptionReason = cleaned }
            }
            return result
        }
    }

    static func decodeStations(_ data: Data) throws -> [Station] {
        struct Response: Decodable {
            struct Record: Decodable { let crs: String; let Value: String }
            let StationList: [Record]
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { throw RailAPIError.invalidResponse }
        var seen = Set<String>()
        let stations = response.StationList.compactMap { record -> Station? in
            let name = record.Value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard var station = Station(rawValue: record.crs), !name.isEmpty,
                  seen.insert(record.crs).inserted else { return nil }
            station.displayName = name
            return station
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !stations.isEmpty else { throw RailAPIError.invalidResponse }
        return stations
    }

    func stations() async throws -> [Station] {
        try Self.decodeStations(await load("GetStationList/0"))
    }

    private func load(_ path: String) async throws -> Data {
        return try await client.load(URLRequest(url: Self.baseURL.appendingPathComponent(path), timeoutInterval: 20),
            key: apiKey, lifetime: 86400)
    }
}
