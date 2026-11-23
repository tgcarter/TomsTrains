import SwiftUI

struct BoardFooter: View {
    enum Branding { case nationalRail, tfl, journeyPlanner }

    var updatedAt: Date? = nil
    var branding: Branding = .nationalRail
    var manualReversalUntil: Date? = nil
    var attributionOnlyAlignment: Alignment = .trailing

    @ViewBuilder private var timestamp: some View {
        if let updatedAt {
            Text("Updated \(RailTime.string(updatedAt))")
        }
    }

    @ViewBuilder private var attribution: some View {
        switch branding {
        case .nationalRail: NationalRailAttribution()
        case .tfl: Text("Powered by TfL Open Data")
        case .journeyPlanner:
            VStack(alignment: .trailing, spacing: 4) {
                NationalRailAttribution()
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        transitous
                        Text("·").accessibilityHidden(true)
                        openStreetMap
                    }
                    VStack(alignment: .trailing, spacing: 4) {
                        transitous
                        openStreetMap
                    }
                }
            }
        }
    }

    private var transitous: some View {
        Link("Journey data by Transitous", destination: URL(string: "https://transitous.org/sources/")!)
    }

    private var openStreetMap: some View {
        Link("© OpenStreetMap contributors", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if updatedAt == nil {
                attribution
                    .frame(maxWidth: .infinity, alignment: attributionOnlyAlignment)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 8) {
                        timestamp.fixedSize()
                        Spacer(minLength: 0)
                        attribution.fixedSize(horizontal: true, vertical: false)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        timestamp
                        attribution
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let manualReversalUntil {
                Text("Manually reversed · automatic from \(RailTime.string(manualReversalUntil))")
            }
        }
        .padding(.top, 6)
    }
}

/// Official developer artwork, with the permitted blue/white colour treatments.
struct NationalRailAttribution: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Link(destination: URL(string: "https://www.nationalrail.co.uk/")!) {
            Image("NationalRailAttribution")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 160, height: 160 * 78.832 / 371.869)
                .foregroundStyle(colorScheme == .dark
                    ? Color.white
                    : Color(red: 46 / 255, green: 45 / 255, blue: 127 / 255))
                .accessibilityLabel("Powered by National Rail")
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the National Rail website")
    }
}
