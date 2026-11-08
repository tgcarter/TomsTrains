import SwiftUI

struct StationPicker: View {
    let title: String
    @Binding var selected: [Station]
    let excluded: [Station]
    @State private var query = ""
    @State private var stations: [Station] = []
    @State private var loading = true
    @State private var error: String?

    private var results: [Station] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return stations.filter { search.isEmpty || $0.name.localizedStandardContains(search) || $0.rawValue.localizedStandardContains(search) }
    }
    var body: some View {
        List {
            if loading { ProgressView("Loading stations…") }
            if let error {
                Section {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                    Button("Try Again") { Task { await load() } }
                }
            }
            if !selected.isEmpty && query.isEmpty {
                Section("Selected") { ForEach(selected) { station in stationButton(station) } }
            }
            Section(query.isEmpty ? "All Stations" : "Results") {
                ForEach(results.filter { !query.isEmpty || !selected.contains($0) }) { station in stationButton(station) }
                if results.isEmpty && !loading { Text("No matching stations").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(title)
        .searchable(text: $query, prompt: "Station name or code")
        .task { await load() }
    }
    private func stationButton(_ station: Station) -> some View {
        Group {
            if selected.contains(station) {
                stationLabel(station)
                    .accessibilityAddTraits(.isSelected)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            selected.removeAll { $0 == station }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Remove \(station.name)")
                        .tint(.red)
                    }
            } else {
                Button {
                    selected.append(station)
                } label: {
                    stationLabel(station)
                }
                .disabled(excluded.contains(station))
            }
        }
    }

    private func stationLabel(_ station: Station) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(station.name).foregroundStyle(.primary)
                Text(excluded.contains(station) ? "Selected at the other end" : station.rawValue)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if selected.contains(station) { Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityLabel("Selected") }
        }
        .accessibilityElement(children: .combine)
    }
    @MainActor private func load() async {
        loading = true
        defer { loading = false }
        stations = StationDirectory.cached()?.stations ?? []
        do { stations = try await StationDirectory().stations(); error = nil }
        catch { self.error = stations.isEmpty ? "Couldn’t load stations. Check your connection and try again." : "Couldn’t refresh stations. Showing the saved directory." }
    }
}
