import Foundation
import Security

enum BackendClientError: LocalizedError {
    case unavailable, invalidAddress, disconnected, forbidden, rejected, throttled

    var errorDescription: String? {
        switch self {
        case .unavailable: "The Mac is unavailable. It may be asleep or offline."
        case .invalidAddress: "Enter the HTTPS address for your TomsTrains backend."
        case .disconnected: "Pair this iPhone in Settings to get live rail data."
        case .forbidden: "The invite or device credential was rejected."
        case .rejected: "The Mac could not save or process this request."
        case .throttled: "The rail request limit was reached. Try again later."
        }
    }
}

/// Use the same App Group for the widget preferences and device credential.
struct BackendClient: Sendable {
    static let addressKey = "backend.address.v1"
    static let widgetFallbackKey = "backend.widgetFallback.v1"
    private static let credentialService = "TomsTrains Backend"
    private static let session = URLSession(configuration: .ephemeral, delegate: NoHTTPRedirects(), delegateQueue: nil)

    let address: URL
    var credential: String?

    static var savedAddress: String? { RouteSettings.defaults.string(forKey: addressKey) }

    static func address(from text: String) throws -> URL {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: text),
              components.scheme == "https", let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, components.query == nil,
              components.fragment == nil, components.path.isEmpty || components.path == "/" else {
            throw BackendClientError.invalidAddress
        }
        components.path = ""
        guard let address = components.url else { throw BackendClientError.invalidAddress }
        return address
    }

    static func paired() throws -> BackendClient {
        guard let savedAddress, let address = try? address(from: savedAddress),
              let credential = credential(for: address) else { throw BackendClientError.disconnected }
        return BackendClient(address: address, credential: credential)
    }

    static func save(_ enrollment: BackendEnrollment, at address: URL) throws {
        try removeCredential(for: address)
        var item = keychainItem(for: address)
        item[kSecValueData as String] = Data(enrollment.credential.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw BackendClientError.rejected }
        RouteSettings.defaults.set(address.absoluteString, forKey: addressKey)
    }

    static func disconnect() throws {
        if let savedAddress, let address = try? address(from: savedAddress) {
            try removeCredential(for: address)
        }
        RouteSettings.defaults.removeObject(forKey: addressKey)
    }

    private static func keychainItem(for address: URL) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: credentialService,
         kSecAttrAccount as String: address.absoluteString, kSecAttrAccessGroup as String: RouteSettings.groupID]
    }

    private static func credential(for address: URL) -> String? {
        var query = keychainItem(for: address)
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func removeCredential(for address: URL) throws {
        let status = SecItemDelete(keychainItem(for: address) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw BackendClientError.rejected }
    }

    func enroll(code: String) async throws -> BackendEnrollment {
        try await decode("v1/enroll", method: "POST", body: BackendInvite(code: code))
    }

    func sync(_ value: BackendSync) async throws -> BackendSyncResult {
        try await decode("v1/device", method: "PUT", body: value)
    }

    func registerActivity(_ value: BackendActivityToken) async throws {
        _ = try await send("v1/activity", method: "PUT", body: JSONEncoder().encode(value))
    }

    func revoke() async throws {
        _ = try await send("v1/device", method: "DELETE", body: nil)
    }

    func widget(_ value: BackendWidgetRequest) async throws -> BackendWidgetSnapshot {
        try await decode("v1/widget", method: "POST", body: value)
    }

    func rail(_ url: URL) async throws -> Data {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw RailAPIError.invalidResponse
        }
        let descriptor = BackendRailRequest(path: components.percentEncodedPath, query: components.percentEncodedQuery)
        return try await send("v1/rail", method: "POST", body: JSONEncoder().encode(descriptor))
    }

    private func decode<T: Decodable>(_ path: String, method: String, body: some Encodable) async throws -> T {
        let data = try await send(path, method: method, body: JSONEncoder().encode(body))
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func send(_ path: String, method: String, body: Data?) async throws -> Data {
        var request = URLRequest(url: address.appendingPathComponent(path), cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 25)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let credential { request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await Self.session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw BackendClientError.unavailable }
        switch response.statusCode {
        case 200..<300: return data
        case 401, 403: throw BackendClientError.forbidden
        case 429: throw BackendClientError.throttled
        case 500...599: throw BackendClientError.unavailable
        default: throw BackendClientError.rejected
        }
    }
}

final class NoHTTPRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? { nil }
}
