import Foundation

enum JourneySearchMode: String, CaseIterable, Identifiable {
    case leaveNow = "Leave now"
    case departAt = "Depart at"
    case arriveBy = "Arrive by"

    var id: Self { self }
}

struct PlannedJourney: Decodable {
    struct Leg: Decodable {
        struct Stop: Decodable {
            let name: String
            let stopId: String?
            let parentId: String?
            let stopCode: String?
            let cancelled: Bool?

            var stationID: String? { parentId ?? stopId }
        }

        let mode: String
        let from: Stop
        let to: Stop
        let startTime: Date
        let endTime: Date
        let scheduledStartTime: Date?
        let agencyName: String?
        let agencyId: String?
        let routeShortName: String?
        let interlineWithPreviousLeg: Bool?
        let cancelled: Bool?

        var isTrain: Bool { JourneyPlanningProvider.railModes.contains(mode) }

        var operatorCode: String? {
            guard let agencyId else { return nil }
            // The GB timetable prefixes National Rail agency codes with an equals sign.
            let code = agencyId.hasPrefix("=") ? String(agencyId.dropFirst()) : agencyId
            switch code {
            case "LF": return "LD"
            case "LM":
                switch routeShortName?.uppercased() {
                case "LNR": return "LN"
                case "WMR": return "WM"
                default: return "LM"
                }
            default: return code
            }
        }

        var operatorName: String {
            switch operatorCode {
            case "LN": return "London Northwestern Railway"
            case "WM": return "West Midlands Railway"
            case "LM": return "London Northwestern Railway and West Midlands Railway"
            default: return agencyName ?? "Train"
            }
        }

        var changesStationOnFoot: Bool {
            mode == "WALK" && from.name != to.name && from.stationID != to.stationID
                && !(from.stopCode != nil && from.stopCode == to.stopCode)
        }
    }

    let startTime: Date
    let endTime: Date
    let legs: [Leg]

    var changes: Int {
        max(0, legs.filter { $0.isTrain && $0.interlineWithPreviousLeg != true }.count - 1)
    }

    var duration: TimeInterval { endTime.timeIntervalSince(startTime) }

    func bookingURL(from origin: Station, to destination: Station) -> URL {
        // The ticket retailer searches by the published departure time.
        let firstTrain = legs.first(where: \.isTrain)
        let departure = firstTrain?.scheduledStartTime ?? firstTrain?.startTime ?? startTime
        let calendar = JourneyDirection.londonCalendar
        let date = departure.formatted(Date.ISO8601FormatStyle(timeZone: calendar.timeZone).year().month().day())
        var url = URLComponents(string: "https://railsmartr.co.uk/booking/fares")!
        url.queryItems = [
            URLQueryItem(name: "origin", value: origin.rawValue),
            URLQueryItem(name: "destination", value: destination.rawValue),
            URLQueryItem(name: "outwardDate", value: date),
            URLQueryItem(name: "outwardDepartAt", value: RailTime.string(departure)),
            URLQueryItem(name: "adults", value: "1"),
            URLQueryItem(name: "children", value: "0"),
            URLQueryItem(name: "limit", value: "5"),
            URLQueryItem(name: "useSplits", value: "true")
        ]
        return url.url!
    }
}

struct JourneyPlanningProvider {
    static let railModes = ["HIGHSPEED_RAIL", "LONG_DISTANCE", "NIGHT_RAIL", "REGIONAL_RAIL", "SUBURBAN"]
    private static let endpoint = URL(string: "https://api.transitous.org/api/v6/plan")!
    private static let feedPrefix = "gb-national-rail_"

    enum Failure: LocalizedError {
        case unavailable
        case outsideTimetable
        case stationUnavailable

        var errorDescription: String? {
            switch self {
            case .unavailable: "The journey planner couldn’t load results. Try again in a moment."
            case .outsideTimetable: "The timetable doesn’t cover that date yet. Try a nearer date."
            case .stationUnavailable: "One of these stations isn’t available in the current timetable."
            }
        }
    }

    private struct Response: Decodable { let itineraries: [PlannedJourney] }
    private struct ErrorResponse: Decodable { let error: String? }

    static func request(from: String, to: String, mode: JourneySearchMode, time: Date) -> URLRequest {
        var url = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        url.queryItems = [
            URLQueryItem(name: "fromPlace", value: feedPrefix + from),
            URLQueryItem(name: "toPlace", value: feedPrefix + to),
            URLQueryItem(name: "time", value: ISO8601DateFormatter().string(from: time)),
            URLQueryItem(name: "arriveBy", value: mode == .arriveBy ? "true" : "false"),
            URLQueryItem(name: "transitModes", value: railModes.joined(separator: ",")),
            URLQueryItem(name: "maxDirectTime", value: "0"),
            URLQueryItem(name: "numItineraries", value: "5")
        ]
        var request = URLRequest(url: url.url!, timeoutInterval: 20)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        request.setValue("TomsTrains/\(version) (+https://github.com/tgcarter/TomsTrains)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    func journeys(from: String, to: String, mode: JourneySearchMode, time: Date) async throws -> [PlannedJourney] {
        let request = Self.request(from: from, to: to, mode: mode, time: time)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.unavailable }
        guard http.statusCode == 200 else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error?.lowercased() ?? ""
            if message.contains("outside of loaded timetable window") {
                throw Failure.outsideTimetable
            }
            if http.statusCode == 404 && message.contains("timetable location") {
                throw Failure.stationUnavailable
            }
            throw Failure.unavailable
        }
        return try Self.decode(data, mode: mode, time: time)
    }

    static func decode(_ data: Data, mode: JourneySearchMode, time: Date) throws -> [PlannedJourney] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { value in
            let container = try value.singleValueContainer()
            let timestamp = try container.decode(String.self)
            guard let date = RailDate.timestamp(timestamp) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid journey timestamp")
            }
            return date
        }
        return try decoder.decode(Response.self, from: data).itineraries.filter { journey in
            guard journey.legs.contains(where: \.isTrain), journey.duration >= 0 else { return false }
            guard journey.legs.allSatisfy({ leg in
                (leg.isTrain || leg.mode == "WALK") && leg.cancelled != true
                    && leg.from.cancelled != true && leg.to.cancelled != true
            }) else { return false }
            return mode == .arriveBy ? journey.endTime <= time : journey.startTime >= time
        }.sorted { first, second in
            if mode == .arriveBy {
                return (first.endTime, first.startTime) > (second.endTime, second.startTime)
            }
            return (first.startTime, first.endTime) < (second.startTime, second.endTime)
        }
    }
}
