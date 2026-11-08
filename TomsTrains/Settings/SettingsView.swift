import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: RouteSettings
    var tracker: TrainTracker? = nil
    @State private var selectedAutoRule: AutoTrackingRule?
    let save: (RouteSettings) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink { StationPicker(title: "Starting Stations", selected: $draft.starts, excluded: draft.ends) } label: {
                        stationSummary("Starting Stations", stations: draft.starts)
                    }
                    NavigationLink { StationPicker(title: "Destinations", selected: $draft.ends, excluded: draft.starts) } label: {
                        stationSummary("Destinations", stations: draft.ends)
                    }
                    Button("Reset Stations", systemImage: "arrow.counterclockwise") {
                        let defaults = RouteSettings()
                        draft.starts = defaults.starts
                        draft.ends = defaults.ends
                    }
                    .accessibilityHint("Restores St Neots as the starting station and King’s Cross and St Pancras as destinations. Tap Save to apply.")
                } header: { Text("Your Route") } footer: {
                    Text("Choose one or more stations at each end. Only direct trains are shown. The return journey reverses these stations.")
                }
                Section {
                    DatePicker("Return Journey From", selection: timeBinding(\.swapMinutes), displayedComponents: .hourAndMinute)
                    DatePicker("Start Again At", selection: timeBinding(\.resetMinutes), displayedComponents: .hourAndMinute)
                } header: { Text("Automatic Direction") } footer: {
                    Text("Times use UK local time. Manual reversal lasts until the next scheduled change.")
                }
                if let tracker {
                    Section("Auto-Tracking") {
                        ForEach(tracker.autoRules) { rule in
                            Button { selectedAutoRule = rule } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(rule.origin.shortName) to \(rule.destination.shortName)")
                                    Text("\(rule.scheduled(on: Date()).map(RailTime.string) ?? "") · \(rule.isEnabled ? "Enabled" : "Paused")")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if tracker.autoRules.isEmpty {
                            Text("Track a train, then choose Configure Auto-Tracking in its details.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let error = tracker.autoTrackingError {
                            Text(error).font(.footnote).foregroundStyle(.orange)
                        }
                    }
                }
                Section("Appearance") {
                    Picker("Theme", selection: $draft.appearance) {
                        ForEach(AppAppearance.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if !draft.isValid {
                    Text("Choose at least one different station at each end and two different swap times.")
                        .font(.footnote).foregroundStyle(.red)
                }
                NationalRailAttribution(alignment: .center)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .sheet(item: $selectedAutoRule) { rule in
                if let tracker {
                    AutoTrackingEditor(draft: rule, tracker: tracker)
                }
            }
            .toolbar(.visible, for: .navigationBar)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.timeZone, TimeZone(identifier: "Europe/London")!)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if draft.starts != RouteSettings.load().starts || draft.ends != RouteSettings.load().ends
                            || draft.swapMinutes != RouteSettings.load().swapMinutes || draft.resetMinutes != RouteSettings.load().resetMinutes {
                            draft.resumeAutomatic()
                        }
                        save(draft)
                        dismiss()
                    }.disabled(!draft.isValid)
                }
            }
        }
        .preferredColorScheme(draft.appearance.colorScheme)
    }

    private func stationSummary(_ title: String, stations: [Station]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Text(stations.map(\.shortName).joined(separator: ", "))
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }
    private func timeBinding(_ keyPath: WritableKeyPath<RouteSettings, Int>) -> Binding<Date> {
        Binding {
            JourneyDirection.londonCalendar.date(bySettingHour: draft[keyPath: keyPath] / 60,
                minute: draft[keyPath: keyPath] % 60, second: 0, of: Date())!
        } set: { date in
            let parts = JourneyDirection.londonCalendar.dateComponents([.hour, .minute], from: date)
            draft[keyPath: keyPath] = parts.hour! * 60 + parts.minute!
        }
    }
}
