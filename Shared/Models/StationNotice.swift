import Foundation

struct StationNotice: Identifiable, Codable, Equatable, Sendable {
    let station: Station
    let text: String
    let severity: String?
    var id: String { station.rawValue + ":" + text }
    var isSevere: Bool { severity == "Major" || severity == "Severe" }

    struct Group: Identifiable, Equatable, Sendable {
        let id: String
        let text: String
        let stations: [Station]
        let isSevere: Bool
        var stationNames: String { stations.map(\.name).joined(separator: " · ") }
    }

    static func grouped(_ notices: [StationNotice]) -> [Group] {
        // Paragraph spacing can differ between stations for the same message.
        let groups = Dictionary(grouping: notices) {
            $0.text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        }
        return groups.keys.sorted().compactMap { key in
            guard let notices = groups[key], let first = notices.first else { return nil }
            var codes = Set<String>()
            let stations = notices.map(\.station)
                .sorted { $0.rawValue < $1.rawValue }
                .filter { codes.insert($0.rawValue).inserted }
            return Group(id: key, text: first.text, stations: stations,
                isSevere: notices.contains(where: \.isSevere))
        }
    }

    static func decode(_ messages: Any?, station: Station) -> [StationNotice] {
        var seen = Set<String>()
        return (messages as? [[String: Any]] ?? []).compactMap { message in
            guard message["isSuppressed"] as? Bool != true,
                  let html = message["xhtmlMessage"] as? String else { return nil }
            let text = plainText(html)
            guard !text.isEmpty else { return nil }
            let category = (message["category"] as? String ?? "").lowercased()
            // Service disruption notices, plus delay warnings filed under another category.
            let delayWarning = text.range(of: "delay|disrupt|cancel|suspend|closed|closure", options: [.regularExpression, .caseInsensitive]) != nil
            guard category == "trainservice" || category == "connectingservices" || delayWarning else { return nil }
            let notice = StationNotice(station: station, text: text, severity: message["severity"] as? String)
            return seen.insert(notice.id).inserted ? notice : nil
        }
    }

    // NRCC messages use HTML-like paragraphs and links. Display their enclosed
    // text, without loading remote HTML or inheriting fixed fonts/colours.
    static func plainText(_ html: String) -> String {
        var text = html
        for (entity, value) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&nbsp;", " ")] {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        text = text.replacingOccurrences(of: "(?is)<(script|style)\\b[^>]*>.*?</\\1>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</p\\s*>|<br\\s*/?>", with: "\n\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        if let regex = try? NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);") {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                guard let range = Range(match.range(at: 1), in: text), let full = Range(match.range, in: text) else { continue }
                let number = String(text[range])
                let value = number.hasPrefix("x") ? UInt32(number.dropFirst(), radix: 16) : UInt32(number)
                if let value, let scalar = UnicodeScalar(value) { text.replaceSubrange(full, with: String(scalar)) }
            }
        }
        return text.replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
