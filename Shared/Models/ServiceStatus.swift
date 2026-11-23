import Foundation

enum ServiceStatus: Equatable, Codable, Sendable {
    case onTime
    case delayed(minutes: Int)
    case delayedWithoutEstimate
    case early(minutes: Int)
    case cancelled
    case unknown
    case disrupted(String)

    static func timing(scheduled: Date, reported: Date) -> ServiceStatus {
        let minutes = Int((reported.timeIntervalSince(scheduled) / 60).rounded())
        if minutes > 0 { return .delayed(minutes: minutes) }
        if minutes < 0 { return .early(minutes: -minutes) }
        return .onTime
    }

    var label: String {
        switch self {
        case .onTime: "On time"
        case .delayed(let minutes): "\(minutes) min late"
        case .delayedWithoutEstimate: "Delayed"
        case .early(let minutes): "\(minutes) min early"
        case .cancelled: "Cancelled"
        case .unknown: "Awaiting update"
        case .disrupted(let message): message
        }
    }

    var symbol: String {
        switch self {
        case .onTime: "checkmark.circle.fill"
        case .delayed, .delayedWithoutEstimate, .early: "clock.badge.exclamationmark"
        case .cancelled: "xmark.circle.fill"
        case .unknown: "questionmark.circle"
        case .disrupted: "exclamationmark.triangle.fill"
        }
    }
}
