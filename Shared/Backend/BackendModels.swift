import Foundation

enum LiveActivityPreference: String, Codable, CaseIterable, Sendable {
    case off, manual, automatic

    var title: String {
        switch self {
        case .off: "Off"
        case .manual: "Manual Tracking"
        case .automatic: "Manual & Auto-Tracking"
        }
    }
}

struct BackendPreferences: Codable, Equatable, Sendable {
    static let leadTimes = [10, 30, 60]
    static let delayThresholds = [5, 10, 15]

    var backgroundTracking = false
    var leadMinutes = 30
    var notifications = false
    var cancellations = true
    var platforms = true
    var delays = true
    var delayMinutes = 5
    var liveActivities: LiveActivityPreference = .automatic

    var isValid: Bool {
        Self.leadTimes.contains(leadMinutes) && Self.delayThresholds.contains(delayMinutes)
    }
}

struct BackendRegistration: Codable, Equatable, Sendable {
    var notificationToken: String?
    var activityStartToken: String?
    var production = false
    var alertsAllowed = false
    var activitiesAllowed = false

    var isValid: Bool {
        [notificationToken, activityStartToken].compactMap { $0 }.allSatisfy(Self.validToken)
    }

    static func validToken(_ token: String) -> Bool {
        (16...512).contains(token.utf8.count) && token.utf8.count.isMultiple(of: 2)
            && token.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

struct BackendWatchCommand: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var departure: Departure
    var tracking: Bool
}

struct BackendSync: Codable, Equatable, Sendable {
    var revision = 0
    var preferences = BackendPreferences()
    var rules: [AutoTrackingRule] = []
    var commands: [BackendWatchCommand] = []
    var registration = BackendRegistration()
}

struct BackendSyncResult: Codable, Sendable {
    var revision: Int
    var journeys: [Departure]
}

struct BackendInvite: Codable, Sendable {
    var code: String
}

struct BackendEnrollment: Codable, Sendable {
    var credential: String
}

struct BackendActivityToken: Codable, Sendable {
    var watchID: UUID
    var token: String
}

struct BackendRailRequest: Codable, Sendable {
    var path: String
    var query: String?
}

struct BackendWidgetRequest: Codable, Equatable, Sendable {
    var route: RouteSettings
    var fallback = true
    var station: Station?
    var mode: LiveBoardMode
    var filter: Station?
}

struct BackendWidgetSnapshot: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable { case commute, live }

    var source: Source
    var title: String
    var service: String?
    var time: Date?
    var platform: String?
    var status: String?
    var observedAt: Date

    var displayUntil: Date {
        min(time ?? .distantFuture, observedAt.addingTimeInterval(300))
    }
}

struct TrainActivityState: Codable, Hashable, Sendable {
    var expectedDeparture: Date?
    var expectedArrival: Date?
    var platform: String?
    var status: String
}

#if canImport(ActivityKit) && os(iOS)
import ActivityKit

struct TrainActivityAttributes: ActivityAttributes {
    typealias ContentState = TrainActivityState

    var watchID: UUID
    var origin: String
    var destination: String
    var scheduled: Date
}
#endif
