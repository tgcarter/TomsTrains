import Foundation

struct DelayRepayLink: Identifiable, Sendable {
    let title: String
    let url: URL

    var id: URL { url }
}

enum DelayRepay {
    // National Rail's operator compensation directory provides the individual claim URLs.
    static let directory = URL(string: "https://www.nationalrail.co.uk/help-and-assistance/compensation-and-refunds/")!
    private static let operators: [String: (name: String, url: String)] = [
        "AW": ("Transport for Wales", "https://delayrepay.trc.cymru/"),
        "CC": ("c2c", "https://www.c2c-online.co.uk/help-feedback/delay-repay/"),
        "CH": ("Chiltern Railways", "https://chilternrailways.delayrepaycompensation.com/"),
        "CS": ("Caledonian Sleeper", "https://www.sleeper.scot/help-support/after-your-trip/"),
        "EM": ("East Midlands Railway", "https://www.eastmidlandsrailway.co.uk/help-manage/manage/make-a-delay-repay-claim"),
        "ES": ("Eurostar", "https://www.eurostar.com/uk-en/travel-info/service-information/claiming-compensation"),
        "GC": ("Grand Central", "https://www.grandcentralrail.com/help/refunds-and-compensation"),
        "GN": ("Great Northern", "https://www.greatnorthernrail.com/help-and-support/delay-repay-compensation"),
        "GR": ("LNER", "https://www.lner.co.uk/support/delay-repay/"),
        "GW": ("Great Western Railway", "https://www.gwr.com/help-and-support/refunds-and-compensation/delay-repay"),
        "GX": ("Gatwick Express", "https://www.gatwickexpress.com/help-and-support/delay-repay-compensation"),
        "HT": ("Hull Trains", "https://www.hulltrains.co.uk/support-and-contact/refunds-and-compensation"),
        "HX": ("Heathrow Express", "https://www.heathrowexpress.com/contact-us"),
        "LD": ("Lumo", "https://delayrepay.lumo.co.uk/en/login?loginTarget=%2F"),
        "LE": ("Greater Anglia", "https://greateranglia.delayrepaycompensation.com/"),
        "LN": ("London Northwestern Railway", "https://londonnorthwesternrailway.delayrepaycompensation.com/index.cfm"),
        "LO": ("London Overground", "https://tfl.gov.uk/fares/refunds-and-replacements/overground-and-elizabeth-line-delays"),
        "LT": ("London Underground", "https://tfl.gov.uk/how-to-pay/refunds/apply-for-service-delay-refund"),
        "ME": ("Merseyrail", "https://www.merseyrail.org/help-support/refunds-and-compensation/delay-compensation-for-single-and-return-tickets/"),
        "NT": ("Northern", "https://delayrepay.northernrailway.co.uk/"),
        "SE": ("Southeastern", "https://delayrepay.southeasternrailway.co.uk/"),
        "SN": ("Southern", "https://www.southernrailway.com/help-and-support/delay-repay-compensation"),
        "SR": ("ScotRail", "https://www.scotrail.co.uk/plan-your-journey/our-delay-repay-guarantee"),
        "SW": ("South Western Railway", "https://www.southwesternrailway.com/contact-and-help/delay-repay"),
        "SX": ("Stansted Express", "https://www.stanstedexpress.com/help/delay-repay"),
        "TL": ("Thameslink", "https://delayrepay.thameslinkrailway.com/"),
        "TP": ("TransPennine Express", "https://www.tpexpress.co.uk/help/delay-repay-compensation"),
        "VT": ("Avanti West Coast", "https://www.avantiwestcoast.co.uk/help-and-support/delay-repay"),
        "WM": ("West Midlands Railway", "https://www.westmidlandsrailway.co.uk/about-us/delay-repay"),
        "XC": ("CrossCountry", "https://www.crosscountrytrains.co.uk/help-support/delay-repay"),
        "XR": ("Elizabeth line", "https://tfl.gov.uk/fares/refunds-and-replacements/overground-and-elizabeth-line-delays")
    ]

    static func links(for departure: Departure) -> [DelayRepayLink] {
        let name = departure.operatorName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let code = departure.operatorCode?.uppercased()
        let matchingName = operators.first { $0.value.name.lowercased() == name }?.key
        let codes: [String]
        switch code {
        case "LM":
            if let matchingName, ["LN", "WM"].contains(matchingName) {
                codes = [matchingName]
            } else {
                codes = ["LN", "WM"]
            }
        case "IL": codes = ["SW"]
        case "LF": codes = ["LD"]
        case let code? where operators[code] != nil: codes = [code]
        default:
            if let matchingName {
                codes = [matchingName]
            } else if ["wm trains", "west midlands trains", "lnr & wmr"].contains(name) {
                codes = ["LN", "WM"]
            } else {
                codes = []
            }
        }
        return codes.compactMap { code in
            guard let operatorPage = operators[code], let url = URL(string: operatorPage.url) else { return nil }
            return DelayRepayLink(title: "Claim with \(operatorPage.name)", url: url)
        }
    }
}
