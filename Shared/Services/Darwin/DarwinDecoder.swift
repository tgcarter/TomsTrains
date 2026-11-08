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

    private static func reported(_ call: [String: Any], arrival: Bool, observed: Date) -> Date? {
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
            var boarding = service
            boarding["crs"] = origin.rawValue
            boarding["locationName"] = board["locationName"] ?? origin.name
            if board["platformsAreHidden"] as? Bool == true { boarding["platformIsHidden"] = true }
            let previous = service["previousLocations"] as? [[String: Any]] ?? []
            let locations = previous + [boarding] + (service["subsequentLocations"] as? [[String: Any]] ?? [])
            return departure(service: service, locations: locations, boarding: previous.count, destination: destination,
                observed: observed, id: "\(origin.rawValue)-\(rid)")
        }
        var station = origin
        station.displayName = board["locationName"] as? String
        return DepartureSnapshot(fetchedAt: observed, departures: departures,
            stationNotices: StationNotice.decode(board["nrccMessages"], station: station))
    }

    private static func isPassengerCall(_ call: [String: Any]) -> Bool {
        guard call["isOperational"] as? Bool != true,
              call["isOperationalCall"] as? Bool != true else { return false }
        if call["isPass"] as? Bool != true { return true }
        // A cancelled scheduled stop can become a pass. A cancelled timing
        // point with only a passing/departure time was never a passenger call.
        return call["isCancelled"] as? Bool == true && time(call["sta"]) != nil
    }

    static func departure(service: [String: Any], locations: [[String: Any]], boarding: Int,
        destination: Station, observed: Date, id: String, hasCompleteRoute: Bool = false) -> Departure? {
        let originCall = locations[boarding]
        guard isPassengerCall(originCall),
              let originCode = originCall["crs"] as? String, var origin = Station(rawValue: originCode),
              let scheduled = time(originCall["std"]),
              (originCall["serviceIsSupressed"] as? Bool != true || reported(originCall, arrival: false, observed: observed) != nil),
              let destinationIndex = locations.indices.dropFirst(boarding + 1).first(where: {
                  locations[$0]["crs"] as? String == destination.rawValue &&
                  isPassengerCall(locations[$0])
              }) else { return nil }
        origin.displayName = originCall["locationName"] as? String
        let destinationCall = locations[destinationIndex]
        guard visibleOrCompleted(destinationCall, observed: observed) else { return nil }
        func cancelled(_ call: [String: Any]) -> Bool { call["isCancelled"] as? Bool == true }
        func actual(_ call: [String: Any], arrival: Bool) -> Date? {
            reported(call, arrival: arrival, observed: observed)
        }
        func forecast(_ call: [String: Any], arrival: Bool) -> Date? {
            guard call[arrival ? "arrivalType" : "departureType"] as? String == "Forecast" else { return nil }
            return time(call[arrival ? "eta" : "etd"])
        }
        func platform(_ call: [String: Any]) -> String? {
            // Completed calls retain the platform used even after Darwin hides
            // them from the current station display. Forecasts do not prove use.
            let completed = !cancelled(call) && (actual(call, arrival: false) != nil || actual(call, arrival: true) != nil)
            guard completed || (call["platformIsHidden"] as? Bool != true && call["serviceIsSupressed"] as? Bool != true),
                  let value = call["platform"] as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        func status(_ call: [String: Any], arrival: Bool) -> ServiceStatus {
            if cancelled(call) { return .cancelled }
            guard let planned = time(call[arrival ? "sta" : "std"]),
                  let reported = actual(call, arrival: arrival) ?? forecast(call, arrival: arrival) else { return .unknown }
            let minutes = Int((reported.timeIntervalSince(planned) / 60).rounded())
            return minutes > 0 ? .delayed(minutes: minutes) : (minutes < 0 ? .early(minutes: -minutes) : .onTime)
        }
        let route = locations.enumerated().compactMap { index, call -> RouteStop? in
            guard let code = call["crs"] as? String, !code.isEmpty,
                  visibleOrCompleted(call, observed: observed),
                  isPassengerCall(call) else { return nil }
            let isBoarding = index == boarding
            let isDestination = index == destinationIndex
            let atd = cancelled(call) ? nil : actual(call, arrival: false)
            let ata = cancelled(call) ? nil : actual(call, arrival: true)
            let sta = time(call["sta"])
            let std = time(call["std"])
            let eta = isBoarding ? nil : forecast(call, arrival: true)
            let etd = forecast(call, arrival: false)
            return RouteStop(id: "\(id)-\(index)", crs: code,
                name: call["locationName"] as? String ?? Station(rawValue: code)?.name ?? code,
                scheduled: isBoarding ? std : (sta ?? std),
                expected: cancelled(call) ? nil : (eta ?? etd),
                actual: atd ?? ata, isCancelled: cancelled(call), estimate: nil,
                isBoarding: isBoarding, isDestination: isDestination, platform: platform(call), reportedAt: observed,
                scheduledDeparture: std, actualDeparture: atd, scheduledArrival: sta,
                forecastEvent: eta != nil ? .arrival : (etd != nil ? .departure : nil))
        }
        let terminal = locations.last(where: { isPassengerCall($0) && !cancelled($0) })
        let terminalActual = terminal.flatMap { actual($0, arrival: true) ?? actual($0, arrival: false) }
        let arrival = time(destinationCall["sta"])
        let actualArrival = cancelled(destinationCall) ? nil : actual(destinationCall, arrival: true)
        let predictedArrival = cancelled(destinationCall) ? nil : (actualArrival ?? forecast(destinationCall, arrival: true))
        // Darwin normally supplies ReasonCodeWithLocation objects. Preserve the
        // codes for official reference-data resolution; never treat a code as text.
        func reasonCode(_ raw: Any?) -> Int? {
            (raw as? [String: Any])?["Value"] as? Int
        }
        func reasonText(_ raw: Any?) -> String? {
            guard let text = raw as? String else { return nil }
            let cleaned = StationNotice.plainText(text)
            return cleaned.isEmpty || Int(cleaned) != nil ? nil : cleaned
        }
        let delayReason = service["delayReason"] ?? originCall["delayReason"]
        let cancellationReason = service["cancelReason"] ?? originCall["cancelReason"]
        let reason = cancelled(originCall) || cancelled(destinationCall)
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
        return Departure(id: id, origin: origin, destination: finalName, callingAt: [destination], scheduled: scheduled,
            status: status(originCall, arrival: false), platform: platform(originCall),
            operatorName: service["operator"] as? String ?? "National Rail",
            journeyMinutes: arrival.map { Int($0.timeIntervalSince(scheduled) / 60) }, disruptionReason: reason,
            scheduledArrival: arrival, expectedArrival: predictedArrival,
            arrivalStatus: cancelled(destinationCall) ? "Cancelled" : nil,
            routeStops: route, observedAt: observed, operatorCode: service["operatorCode"] as? String,
            actualArrival: actualArrival, serviceRID: service["rid"] as? String, terminalActual: terminalActual,
            delayReasonCode: reasonCode(delayReason), cancellationReasonCode: reasonCode(cancellationReason), serviceOrigin: serviceOrigin)
    }

}
