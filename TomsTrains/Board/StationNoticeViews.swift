import SwiftUI

struct StationNoticeRow: View {
    let notice: StationNotice.Group
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(notice.isSevere ? .red : .orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(notice.stationNames).font(.subheadline.weight(.semibold))
                Text(notice.text).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Read the full disruption notice")
    }
}

struct StationNoticeSheet: View {
    let notice: StationNotice.Group
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label(notice.stationNames, systemImage: "exclamationmark.triangle.fill")
                        .font(.headline).foregroundStyle(notice.isSevere ? .red : .orange)
                    Text(notice.text).font(.body).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .navigationTitle("Travel Disruption")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
