import SwiftUI

/// Official developer artwork, with the permitted blue/white colour treatments.
struct NationalRailAttribution: View {
    var alignment: Alignment = .trailing
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
        .frame(maxWidth: .infinity, alignment: alignment)
        .buttonStyle(.plain)
        .accessibilityHint("Opens the National Rail website")
    }
}
