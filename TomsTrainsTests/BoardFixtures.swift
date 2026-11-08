import Foundation
#if SWIFT_PACKAGE
@testable import TomsTrainsCore
#endif

/// Deterministic timetable fixtures compiled only into the test target.
enum BoardFixtures {
    static func services(around date: Date) -> [Departure] {
        let calendar = JourneyDirection.londonCalendar
        let start = calendar.startOfDay(for: date)
        return (-1...1).flatMap { dayOffset -> [Departure] in
            let day = calendar.date(byAdding: .day, value: dayOffset, to: start)!
            return (5...23).flatMap { hour -> [Departure] in
                [4, 19, 34, 49].enumerated().flatMap { slot, minute -> [Departure] in
                    let scheduled = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
                    let london: Station = slot.isMultiple(of: 2) ? .kingsCross : .stPancras
                    let status: ServiceStatus = switch slot {
                    case 1: .delayed(minutes: 7)
                    case 3: .cancelled
                    default: .onTime
                    }
                    let reason: String? = switch status {
                    case .delayed: "The fixture service is delayed by a signalling problem."
                    case .cancelled: "The fixture service is cancelled because of a train fault."
                    default: nil
                    }
                    let identity = "fixture-\(Int(scheduled.timeIntervalSince1970))"
                    let operatorName = london == .kingsCross ? "Great Northern" : "Thameslink"
                    return [
                        Departure(id: "\(identity)-out", origin: .stNeots,
                                  destination: london == .kingsCross ? "London King’s Cross" : "Horsham",
                                  callingAt: [london], scheduled: scheduled, status: status,
                                  platform: "1", operatorName: operatorName,
                                  journeyMinutes: london == .kingsCross ? 48 : 57, disruptionReason: reason),
                        Departure(id: "\(identity)-back", origin: london,
                                  destination: "Peterborough", callingAt: [.stNeots],
                                  scheduled: scheduled, status: status,
                                  platform: slot == 1 ? nil : (london == .kingsCross ? "8" : "A"),
                                  operatorName: operatorName,
                                  journeyMinutes: london == .kingsCross ? 49 : 58, disruptionReason: reason)
                    ]
                }
            }
        }
    }
}
