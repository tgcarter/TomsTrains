import SwiftUI

enum StationSelection {
    case single((Station) -> Void)
    case multiple(Binding<[Station]>, excluding: [Station])
}

struct StationPicker: View {
    let title: String
    let selection: StationSelection
    var currentStation: Station?
    var hiddenStation: Station?
    var clearSelection: (() -> Void)?
    var guidance: String?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String?
    @State private var directory = StationSearchDirectory()

    var body: some View {
        List {
            StationSearch(draft: $draft, directory: directory, hiddenStation: hiddenStation,
                          selection: dismissingSelection) { choose in
                if let clearSelection {
                    Section {
                        Button {
                            clearSelection()
                            dismiss()
                        } label: {
                            Label("Any Station", systemImage: "line.3.horizontal.decrease")
                        }
                        if let currentStation {
                            Button { choose(currentStation) } label: {
                                StationResultLabel(station: currentStation, isSelected: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(.isSelected)
                        }
                    } footer: {
                        if let guidance { Text(guidance) }
                    }
                }
            }
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if case .single = selection {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private var dismissingSelection: StationSelection {
        guard case .single(let select) = selection else { return selection }
        return .single { station in
            select(station)
            dismiss()
        }
    }
}

/// Shared search field and list sections for embedded and standalone station searches.
struct StationSearch<IdleContent: View>: View {
    @Binding var draft: String?
    let directory: StationSearchDirectory
    var displayedStation: Station?
    var clearSelection: (() -> Void)?
    var hiddenStation: Station?
    var isActive = true
    let selection: StationSelection
    @ViewBuilder let idle: (@escaping (Station) -> Void) -> IdleContent

    @FocusState private var fieldFocused: Bool

    private var stations: [Station] { directory.stations }
    private var query: String { (draft ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

    private var fieldText: Binding<String> {
        Binding {
            draft ?? displayedStation?.name ?? ""
        } set: { text in
            draft = text == (displayedStation?.name ?? "") ? nil : text
        }
    }

    var body: some View {
        Section {
            searchField
                .task(id: isActive) {
                    if isActive { await directory.load() }
                }
        }
        .listSectionMargins(.top, 0)

        if directory.loadFailed {
            Section {
                Text(stations.isEmpty ? "Couldn’t load the station directory." : "Couldn’t refresh stations. Showing the saved directory.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Try Again") { Task { await directory.load() } }
            }
        }

        if query.isEmpty {
            if case .multiple(let selected, _) = selection {
                if !selected.wrappedValue.isEmpty {
                    Section {
                        ForEach(selected.wrappedValue) { station in resultRow(station) }
                    } header: {
                        Text("Selected")
                    } footer: {
                        if selected.wrappedValue.count == 1 { Text("Add another station before removing this one.") }
                    }
                }
                let unselected = stations.filter { !selected.wrappedValue.contains($0) }
                if !unselected.isEmpty {
                    Section("All Stations") {
                        ForEach(unselected) { station in resultRow(station) }
                    }
                } else if stations.isEmpty && !directory.loadFailed {
                    Section { ProgressView("Loading stations…") }
                }
            }
            idle(choose)
        } else {
            Section {
                let results = matchingStations
                if stations.isEmpty && !directory.loadFailed {
                    ProgressView("Loading stations…")
                } else if !stations.isEmpty && results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    ForEach(results) { station in resultRow(station) }
                }
            } header: {
                Text("Results")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Station name or code", text: fieldText)
                .focused($fieldFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit(submitSearch)
                .onChange(of: fieldFocused) { _, focused in
                    if !focused && query.isEmpty { draft = nil }
                }
            if displayedStation != nil || !(draft ?? "").isEmpty {
                Button("Clear") {
                    draft = nil
                    if let clearSelection {
                        clearSelection()
                        fieldFocused = false
                    }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear station search")
            }
        }
    }

    private var matchingStations: [Station] {
        let query = self.query
        let code = query.uppercased()
        return stations.filter {
            $0 != hiddenStation && ($0.name.localizedStandardContains(query) ||
                $0.fullName.localizedStandardContains(query) || $0.rawValue.localizedStandardContains(query))
        }.sorted { first, second in
            let firstExact = first.rawValue == code
            let secondExact = second.rawValue == code
            if firstExact != secondExact { return firstExact }
            return first.name.localizedStandardCompare(second.name) == .orderedAscending
        }
    }

    @ViewBuilder private func resultRow(_ station: Station) -> some View {
        switch selection {
        case .multiple(let selected, _) where selected.wrappedValue.contains(station):
            StationResultLabel(station: station, isSelected: true)
                .accessibilityAddTraits(.isSelected)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if selected.wrappedValue.count > 1 {
                        Button(role: .destructive) {
                            selected.wrappedValue.removeAll { $0 == station }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Remove \(station.name)")
                    }
                }
        default:
            let unavailable = isExcluded(station)
            Button { choose(station) } label: {
                StationResultLabel(station: station, isExcluded: unavailable)
            }
            .buttonStyle(.plain)
            .disabled(unavailable)
        }
    }

    private func isExcluded(_ station: Station) -> Bool {
        guard case .multiple(_, let excluded) = selection else { return false }
        return excluded.contains(station)
    }

    private func submitSearch() {
        guard !query.isEmpty else { return }
        let results = matchingStations
        if let first = results.first, results.count == 1 || first.rawValue == query.uppercased() {
            choose(first)
        }
    }

    private func choose(_ station: Station) {
        switch selection {
        case .single(let select):
            draft = nil
            fieldFocused = false
            select(station)
        case .multiple(let selected, let excluded):
            guard !selected.wrappedValue.contains(station), !excluded.contains(station) else { return }
            selected.wrappedValue.append(station)
        }
    }
}

@MainActor @Observable
final class StationSearchDirectory {
    private(set) var stations = StationDirectory.cached()?.stations ?? []
    private(set) var loadFailed = false

    func load() async {
        loadFailed = false
        if stations.isEmpty { stations = StationDirectory.cached()?.stations ?? [] }
        do {
            let updated = try await StationDirectory().stations()
            guard !Task.isCancelled else { return }
            stations = updated
        } catch {
            if !Task.isCancelled { loadFailed = true }
        }
    }
}

struct StationResultLabel: View {
    let station: Station
    var isSelected = false
    var isExcluded = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(station.name).foregroundStyle(isExcluded ? .secondary : .primary)
                if isExcluded {
                    Text("Selected at the other end").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(station.rawValue).font(.subheadline.monospaced()).foregroundStyle(.secondary)
            if isSelected {
                Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
