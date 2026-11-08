import Foundation

enum ServiceStatus: Equatable, Codable, Sendable {
    case onTime
    case delayed(minutes: Int)
    case early(minutes: Int)
    case cancelled
    case unknown
    case disrupted(String)

    var label: String {
        switch self {
        case .onTime: "On time"
        case .delayed(let minutes): "\(minutes) min late"
        case .early(let minutes): "\(minutes) min early"
        case .cancelled: "Cancelled"
        case .unknown: "Awaiting update"
        case .disrupted(let message): message
        }
    }

    var symbol: String {
        switch self {
        case .onTime: "checkmark.circle.fill"
        case .delayed, .early: "clock.badge.exclamationmark"
        case .cancelled: "xmark.circle.fill"
        case .unknown: "questionmark.circle"
        case .disrupted: "exclamationmark.triangle.fill"
        }
    }
}
