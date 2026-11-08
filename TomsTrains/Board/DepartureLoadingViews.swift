import SwiftUI

struct DepartureLoadingHeader: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "tram.fill")
                .font(.title2).foregroundStyle(.blue)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Finding Your Trains").font(.headline)
                Text("Checking the latest departures…")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            ProgressView().accessibilityHidden(true)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

struct DepartureSkeletonRow: View {
    let isNext: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var scale = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isNext { bar(width: 112, height: 9) }
            HStack(spacing: 12) {
                bar(width: 72, height: 24)
                bar(width: 80, height: 14)
                Spacer()
            }
            HStack {
                bar(width: 136, height: 14)
                Spacer()
                bar(width: 68, height: 10)
            }
            HStack {
                bar(width: 78, height: 10)
                Spacer()
                bar(width: 90, height: 10)
            }
        }
        .padding(.vertical, 4)
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.quaternary)
            .frame(width: width, height: height * scale)
    }
}
