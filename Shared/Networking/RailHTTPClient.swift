import Foundation

struct RailHTTPClient: Sendable {
    private let transport: NationalRailProvider.Transport
    private let usesCache: Bool

    init(transport: NationalRailProvider.Transport? = nil) {
        usesCache = transport == nil
        self.transport = transport ?? { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw RailAPIError.invalidResponse }
            return (data, http)
        }
    }

    func load(_ request: URLRequest, key: String, lifetime: TimeInterval = 20) async throws -> Data {
        guard !key.isEmpty, !key.contains("$(") else { throw RailAPIError.missingKey }
        var authenticated = request
        authenticated.setValue(key, forHTTPHeaderField: "x-apikey")
        authenticated.setValue("application/json", forHTTPHeaderField: "Accept")
        let finalRequest = authenticated
        let transport = transport
        let operation: @Sendable () async throws -> Data = {
            let (data, response) = try await transport(finalRequest)
            switch response.statusCode {
            case 200: return data
            case 401, 403: throw RailAPIError.accessDenied
            case 429: throw RailAPIError.rateLimited
            default: throw RailAPIError.unavailable
            }
        }
        let data: Data
        if usesCache { data = try await DarwinResponseCache.shared.load(url: request.url!, key: key, lifetime: lifetime, operation: operation) }
        else { data = try await operation() }
        try Task.checkCancellation()
        return data
    }


}
