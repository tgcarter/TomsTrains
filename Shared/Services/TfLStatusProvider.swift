import Foundation

struct TfLLine: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let modeName: String
    let lineStatuses: [Status]

    struct Status: Decodable, Sendable {
        let statusSeverity: Int
        let statusSeverityDescription: String
        let reason: String?

        var isDisrupted: Bool { statusSeverity != 10 }
    }

    var isDisrupted: Bool { lineStatuses.contains(where: \.isDisrupted) }

    var orderedStatuses: [Status] {
        lineStatuses.filter(\.isDisrupted) + lineStatuses.filter { !$0.isDisrupted }
    }

    var reasons: [String] {
        var seen = Set<String>()
        return orderedStatuses.compactMap(\.reason)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

struct TfLStatusProvider: Sendable {
    static let endpoint = URL(string: "https://api.tfl.gov.uk/Line/Mode/tube,overground,elizabeth-line,dlr,tram/Status")!

    func lines() async throws -> [TfLLine] {
        let request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try Self.decode(data)
    }

    static func decode(_ data: Data) throws -> [TfLLine] {
        try JSONDecoder().decode([TfLLine].self, from: data)
            .sorted {
                if $0.isDisrupted != $1.isDisrupted { return $0.isDisrupted }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }
}
