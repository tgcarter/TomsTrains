import Foundation

struct StationDirectory: Sendable {
    static let endpoint = NationalRailReference.baseURL.appendingPathComponent("GetStationList/0")
    private static let cacheKey = "stationDirectory.reference.v1"
    struct Cache: Codable { let fetchedAt: Date; let stations: [Station] }
    private let reference: NationalRailReference

    init(apiKey: String = Bundle.main.object(forInfoDictionaryKey: "NationalRailReferenceAPIKey") as? String ?? "",
         transport: NationalRailProvider.Transport? = nil) {
        reference = NationalRailReference(apiKey: apiKey, transport: transport)
    }

    static func decode(_ data: Data) throws -> [Station] {
        try NationalRailReference.decodeStations(data)
    }

    static func cached() -> Cache? {
        RouteSettings.defaults.data(forKey: cacheKey).flatMap { try? JSONDecoder().decode(Cache.self, from: $0) }
    }

    func fetch() async throws -> [Station] { try await reference.stations() }

    func stations() async throws -> [Station] {
        if let cache = Self.cached(), (0..<86400).contains(Date().timeIntervalSince(cache.fetchedAt)) { return cache.stations }
        let stations = try await fetch()
        if let data = try? JSONEncoder().encode(Cache(fetchedAt: Date(), stations: stations)) {
            RouteSettings.defaults.set(data, forKey: Self.cacheKey)
        }
        return stations
    }
}
