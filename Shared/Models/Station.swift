import Foundation

struct Station: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    let rawValue: String
    var displayName: String? = nil
    var id: String { rawValue }
    init?(rawValue: String) {
        guard rawValue.count == 3, rawValue.utf8.allSatisfy({ (65...90).contains($0) }) else { return nil }
        self.rawValue = rawValue
    }
    static let stNeots = Station(rawValue: "SNO")!
    static let kingsCross = Station(rawValue: "KGX")!
    static let stPancras = Station(rawValue: "STP")!
    var name: String {
        switch rawValue {
        case "SNO": "St Neots"
        case "KGX": "King’s Cross"
        case "STP": "St Pancras International"
        default: displayName ?? rawValue
        }
    }
    /// Full API name for grouping, without the compact labels used in departure rows.
    var fullName: String {
        if let displayName, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return displayName }
        switch rawValue {
        case "KGX": return "London Kings Cross"
        case "STP": return "London St Pancras International"
        default: return name
        }
    }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.rawValue == rhs.rawValue }
    func hash(into hasher: inout Hasher) { hasher.combine(rawValue) }
    private enum CodingKeys: String, CodingKey { case rawValue, displayName }
    var shortName: String { self == .stPancras ? "St Pancras" : name }
    init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(String.self), let station = Station(rawValue: value) {
            self = station
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let code = try container.decode(String.self, forKey: .rawValue)
        guard let station = Station(rawValue: code) else {
            throw DecodingError.dataCorruptedError(forKey: .rawValue, in: container, debugDescription: "Invalid station code")
        }
        self = station
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rawValue, forKey: .rawValue)
        try container.encodeIfPresent(displayName, forKey: .displayName)
    }
}
