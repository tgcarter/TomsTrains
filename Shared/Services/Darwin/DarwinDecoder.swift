import Foundation

enum DarwinDecoder {
    static func object(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? [String: Any] else { throw RailAPIError.invalidResponse }
        return object
    }

    /// Darwin location timestamps have London wall time; generatedAt includes its offset.
    static func time(_ raw: Any?) -> Date? {
        guard let value = raw as? String else { return nil }
        if let date = RailDate.timestamp(value) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = JourneyDirection.londonCalendar.timeZone
        formatter.isLenient = false
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSSS", "yyyy-MM-dd'T'HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    static func reported(_ call: [String: Any], arrival: Bool, observed: Date) -> Date? {
        guard call[arrival ? "arrivalType" : "departureType"] as? String == "Actual",
              let value = time(call[arrival ? "ata" : "atd"]), value <= observed else { return nil }
        return value
    }

    // Display suppression hides a train from the live station board. A confirmed
    // movement remains useful in departure history and the journey's completed stops.
    private static func visibleOrCompleted(_ call: [String: Any], observed: Date) -> Bool {
        call["serviceIsSupressed"] as? Bool != true || reported(call, arrival: false, observed: observed) != nil
            || reported(call, arrival: true, observed: observed) != nil
    }

    static func isWithdrawn(_ service: [String: Any]) -> Bool {
        service["isDeleted"] as? Bool == true || service["isCancelled"] as? Bool == true
    }

    static func withdrawnDeparture(_ departure: Departure, service: [String: Any],
                                   observed: Date, rid: String, reason: String? = nil) -> Departure {
        var result = departure
        result.serviceRID = rid
        result.status = .cancelled
        result.arrivalStatus = "Cancelled"
        result.actualArrival = nil
        result.expectedArrival = nil
        result.terminalActual = nil
        result.platform = nil
        result.observedAt = observed
        result.delayReasonCode = nil
        result.cancellationReasonCode = reasonCode(service["cancelReason"])
        result.disruptionReason = reason ?? reasonText(service["cancelReason"])
        for index in result.routeStops?.indices ?? 0..<0 where result.routeStops?[index].actual == nil {
            result.routeStops?[index].isCancelled = true
            result.routeStops?[index].platform = nil
        }
        return result
    }

    static func reasonCode(_ raw: Any?) -> Int? {
        (raw as? [String: Any])?["Value"] as? Int
    }

    static func reasonText(_ raw: Any?) -> String? {
        guard let text = raw as? String else { return nil }
        let cleaned = StationNotice.plainText(text)
        return cleaned.isEmpty || Int(cleaned) != nil ? nil : cleaned
    }

    static func departure(fromBoardService service: [String: Any], board: [String: Any],
                          origin: Station, destination: Station, observed: Date, id: String) -> Departure? {
        var boarding = service
        boarding["crs"] = origin.rawValue
        boarding["locationName"] = board["locationName"] ?? origin.name
        if board["platformsAreHidden"] as? Bool == true { boarding["platformIsHidden"] = true }
        if isWithdrawn(service) { boarding["isCancelled"] = true }
        let previous = service["previousLocations"] as? [[String: Any]] ?? []
        let locations = previous + [boarding] + (service["subsequentLocations"] as? [[String: Any]] ?? [])
        return departure(service: service, locations: locations, boarding: previous.count, destination: destination,
            observed: observed, id: id)
    }

    static func decode(_ data: Data, origin: Station, destination: Station, now: Date) throws -> DepartureSnapshot {
        let board = try object(data)
        guard board["crs"] as? String == origin.rawValue,
              board["servicesAreUnavailable"] as? Bool != true,
              let observed = time(board["generatedAt"]) else { throw RailAPIError.invalidResponse }
        if let services = board["trainServices"], !(services is [[String: Any]]) && !(services is NSNull) {
            throw RailAPIError.invalidResponse
        }
        let departures = (board["trainServices"] as? [[String: Any]] ?? []).compactMap { service -> Departure? in
            guard (service["serviceIsSupressed"] as? Bool != true || reported(service, arrival: false, observed: observed) != nil), service["isPassengerService"] as? Bool != false,
                  let rid = service["rid"] as? String else { return nil }
            return departure(fromBoardService: service, board: board, origin: origin, destination: destination,
                observed: observed, id: "\(origin.rawValue)-\(rid)")
        }
        var station = origin
        station.displayName = board["locationName"] as? String
        return DepartureSnapshot(fetchedAt: observed, departures: departures,
            stationNotices: StationNotice.decode(board["nrccMessages"], station: station))
    }

    static func isPassengerCall(_ call: [String: Any]) -> Bool {
        guard call["isOperational"] as? Bool != true,
              call["isOperationalCall"] as? Bool != true else { return false }
        if call["isPass"] as? Bool != true { return true }
        // A cancelled scheduled stop can become a pass. A cancelled timing
        // point with only a passing/departure time was never a passenger call.
        return call["isCancelled"] as? Bool == true && time(call["sta"]) != nil
    }

    static func forecast(_ call: [String: Any], arrival: Bool) -> Date? {
        guard call[arrival ? "arrivalType" : "departureType"] as? String == "Forecast" else { return nil }
        return time(call[arrival ? "eta" : "etd"])
    }

    static func status(_ call: [String: Any], arrival: Bool, observed: Date) -> ServiceStatus {
        if isWithdrawn(call) { return .cancelled }
        if call[arrival ? "arrivalType" : "departureType"] as? String == "Delayed" { return .delayedWithoutEstimate }
        guard let planned = time(call[arrival ? "sta" : "std"]),
              let report = reported(call, arrival: arrival, observed: observed) ?? forecast(call, arrival: arrival) else {
            return .unknown
        }
        return ServiceStatus.timing(scheduled: planned, reported: report)
    }

    static func platform(_ call: [String: Any], observed: Date) -> String? {
        // A completed call can keep its historical platform after Darwin hides it.
        let completed = !isWithdrawn(call) && (reported(call, arrival: false, observed: observed) != nil
            || reported(call, arrival: true, observed: observed) != nil)
        guard completed || (call["platformIsHidden"] as? Bool != true && call["serviceIsSupressed"] as? Bool != true),
              let value = call["platform"] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func routeStops(_ locations: [[String: Any]], boarding: Int?, destination: Int?,
                           observed: Date, id: String, includesSuppressedCancellations: Bool = false) -> [RouteStop] {
        locations.enumerated().compactMap { index, call -> RouteStop? in
            let isBoarding = index == boarding
            let isDestination = index == destination
            let cancelled = isWithdrawn(call)
            guard let code = call["crs"] as? String, !code.isEmpty, isPassengerCall(call),
                  visibleOrCompleted(call, observed: observed)
                    || includesSuppressedCancellations && (isBoarding || isDestination) && cancelled else { return nil }
            let atd = cancelled ? nil : reported(call, arrival: false, observed: observed)
            let ata = cancelled ? nil : reported(call, arrival: true, observed: observed)
            let sta = time(call["sta"])
            let std = time(call["std"])
            let eta = isBoarding ? nil : forecast(call, arrival: true)
            let etd = forecast(call, arrival: false)
            return RouteStop(id: "\(id)-\(index)", crs: code,
                name: call["locationName"] as? String ?? Station(rawValue: code)?.name ?? code,
                scheduled: isBoarding ? std : (sta ?? std),
                expected: cancelled ? nil : (eta ?? etd),
                actual: atd ?? ata, isCancelled: cancelled,
                estimate: call["departureType"] as? String == "Delayed"
                    || (!isBoarding && call["arrivalType"] as? String == "Delayed") ? "Delayed" : nil,
                isBoarding: isBoarding, isDestination: isDestination, platform: platform(call, observed: observed),
                reportedAt: observed, scheduledDeparture: std, actualDeparture: atd, scheduledArrival: sta,
                forecastEvent: eta != nil ? .arrival : (etd != nil ? .departure : nil))
        }
    }

    static func departure(service: [String: Any], locations: [[String: Any]], boarding: Int,
        destination: Station, observed: Date, id: String, hasCompleteRoute: Bool = false) -> Departure? {
        let originCall = locations[boarding]
        guard isPassengerCall(originCall),
              let originCode = originCall["crs"] as? String, var origin = Station(rawValue: originCode),
              let scheduled = time(originCall["std"]),
              (originCall["serviceIsSupressed"] as? Bool != true || reported(originCall, arrival: false, observed: observed) != nil
                || hasCompleteRoute && originCall["isCancelled"] as? Bool == true),
              let destinationIndex = locations.indices.dropFirst(boarding + 1).first(where: {
                  locations[$0]["crs"] as? String == destination.rawValue &&
                  isPassengerCall(locations[$0])
              }) else { return nil }
        origin.displayName = originCall["locationName"] as? String
        let destinationCall = locations[destinationIndex]
        guard visibleOrCompleted(destinationCall, observed: observed)
                || hasCompleteRoute && destinationCall["isCancelled"] as? Bool == true else { return nil }
        let route = routeStops(locations, boarding: boarding, destination: destinationIndex, observed: observed,
            id: id, includesSuppressedCancellations: hasCompleteRoute)
        let terminal = locations.last(where: { isPassengerCall($0) && !isWithdrawn($0) })
        let terminalActual = terminal.flatMap {
            reported($0, arrival: true, observed: observed) ?? reported($0, arrival: false, observed: observed)
        }
        let arrival = time(destinationCall["sta"])
        let actualArrival = isWithdrawn(destinationCall) ? nil : reported(destinationCall, arrival: true, observed: observed)
        let predictedArrival = isWithdrawn(destinationCall) ? nil : (actualArrival ?? forecast(destinationCall, arrival: true))
        // Darwin normally supplies ReasonCodeWithLocation objects. Preserve the
        // codes for official reference-data resolution; never treat a code as text.
        let delayReason = service["delayReason"] ?? originCall["delayReason"]
        let cancellationReason = service["cancelReason"] ?? originCall["cancelReason"]
        let reason = isWithdrawn(originCall) || isWithdrawn(destinationCall)
            ? reasonText(cancellationReason) ?? reasonText(delayReason) : reasonText(delayReason)
        let finalName = (service["destination"] as? [[String: Any]])?.compactMap { $0["locationName"] as? String }.joined(separator: " / ")
            ?? locations.last(where: isPassengerCall)?["locationName"] as? String ?? destination.name
        // Board history may be truncated; only the declared origin or a complete
        // service-details route can establish where the train actually starts.
        let declaredOrigin = (service["origin"] as? [[String: Any]])?.first
        let firstCall: [String: Any]?
        if hasCompleteRoute {
            firstCall = locations.first(where: isPassengerCall)
        } else if let code = declaredOrigin?["crs"] as? String {
            firstCall = locations.first { $0["crs"] as? String == code && isPassengerCall($0) }
        } else {
            firstCall = nil
        }
        let startName = declaredOrigin?["locationName"] as? String ?? firstCall?["locationName"] as? String
        let serviceOrigin = startName.map {
            Departure.ServiceOrigin(name: $0, scheduledDeparture: firstCall.flatMap { time($0["std"]) })
        }
        let arrivalStatus: String? = switch status(destinationCall, arrival: true, observed: observed) {
        case .cancelled: "Cancelled"
        case .delayedWithoutEstimate: "Delayed"
        default: nil
        }
        return Departure(id: id, origin: origin, destination: finalName, callingAt: [destination], scheduled: scheduled,
            status: status(originCall, arrival: false, observed: observed), platform: platform(originCall, observed: observed),
            operatorName: service["operator"] as? String ?? "National Rail",
            journeyMinutes: arrival.map { Int($0.timeIntervalSince(scheduled) / 60) }, disruptionReason: reason,
            scheduledArrival: arrival, expectedArrival: predictedArrival,
            arrivalStatus: arrivalStatus,
            routeStops: route, observedAt: observed, operatorCode: service["operatorCode"] as? String,
            actualArrival: actualArrival, serviceRID: service["rid"] as? String, terminalActual: terminalActual,
            delayReasonCode: reasonCode(delayReason), cancellationReasonCode: reasonCode(cancellationReason), serviceOrigin: serviceOrigin)
    }

}
