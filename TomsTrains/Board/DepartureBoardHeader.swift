import SwiftUI

struct DepartureBoardHeader: View {
    let title: String
    var trailingSpace: CGFloat = 0

    var body: some View {
        Section {
            EmptyView()
        } header: {
            Text(title)
                .font(.largeTitle.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.25)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, trailingSpace)
                .frame(minHeight: 44)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
                .foregroundStyle(.primary)
                .textCase(nil)
                .listRowInsets(EdgeInsets())
        }
        .listSectionMargins(.top, 0)
    }
}

struct DepartureBoardControls: View {
    var isLoading: Bool
    var refresh: () -> Void
    var reverse: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            if let reverse {
                Button(action: reverse) {
                    Label("Reverse", systemImage: "arrow.left.arrow.right")
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .accessibilityHint("Reverses your route until the next automatic change")
            }
            Button(action: refresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .disabled(isLoading)
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

struct BoardPageButton: View {
    let title: LocalizedStringKey
    let isLoading: Bool
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            HStack {
                Text(title)
                Spacer()
                if isLoading { ProgressView() }
            }
        }
        .disabled(isLoading)
    }
}
