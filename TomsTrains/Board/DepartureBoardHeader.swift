import SwiftUI

struct DepartureBoardHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.largeTitle.bold())
            .lineLimit(1)
            .minimumScaleFactor(0.25)
            .allowsTightening(true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 148)
            .frame(minHeight: 44)
            .accessibilityAddTraits(.isHeader)
            .padding(.bottom, 4)
    }
}

struct DepartureBoardControls: View {
    var isLoading: Bool
    var refresh: () -> Void
    var reverse: () -> Void
    var settings: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: reverse) {
                Label("Reverse", systemImage: "arrow.left.arrow.right")
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .accessibilityHint("Reverses your route until the next automatic change")
            Button(action: refresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .disabled(isLoading)
            Button(action: settings) {
                Label("Settings", systemImage: "gearshape")
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
        }
        .labelStyle(.iconOnly)
        .font(.system(size: 17, weight: .medium))
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .glassEffect(.regular, in: .capsule)
        .fixedSize()
        .tint(.primary)
    }
}
