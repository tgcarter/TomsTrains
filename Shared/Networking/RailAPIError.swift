import Foundation

enum RailAPIError: LocalizedError {
    case missingKey, accessDenied, rateLimited, unavailable, invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingKey: "National Rail access isn’t configured in this build."
        case .accessDenied: "National Rail rejected API access. Check the subscription and API key."
        case .rateLimited: "National Rail’s request limit was reached. Please try again later."
        case .unavailable: "National Rail is temporarily unavailable. Pull down to try again."
        case .invalidResponse: "National Rail returned an unreadable departure board."
        }
    }
}
