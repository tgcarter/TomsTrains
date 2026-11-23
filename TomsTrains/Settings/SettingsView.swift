import SwiftUI

struct SettingsView: View {
    @Binding var settings: RouteSettings
    let tracker: TrainTracker
    @State private var selectedAutoRule: AutoTrackingRule?
    @State private var timesConflict = false

    var body: some View {
        NavigationStack {
            Form {
                DepartureBoardHeader(title: "Settings")
                Section {
                    NavigationLink {
                        StationPicker(title: "Starting Stations",
                                      selection: .multiple(routeBinding(\.starts), excluding: settings.ends))
                    } label: {
                        stationSummary("Starting Stations", stations: settings.starts)
                    }
                    NavigationLink {
                        StationPicker(title: "Destinations",
                                      selection: .multiple(routeBinding(\.ends), excluding: settings.starts))
                    } label: {
                        stationSummary("Destinations", stations: settings.ends)
                    }
                    Button("Reset Stations", systemImage: "arrow.counterclockwise") {
                        let defaults = RouteSettings()
                        var updated = settings
                        updated.starts = defaults.starts
                        updated.ends = defaults.ends
                        applyRoute(updated)
                    }
                    .accessibilityHint("Restores St Neots as the starting station and King’s Cross and St Pancras as destinations.")
                } header: { Text("Your Route") } footer: {
                    Text("Choose one or more stations at each end. Only direct trains are shown. The return journey reverses these stations.")
                }
                Section {
                    DatePicker("Return Journey From", selection: timeBinding(\.swapMinutes), displayedComponents: .hourAndMinute)
                    DatePicker("Start Again At", selection: timeBinding(\.resetMinutes), displayedComponents: .hourAndMinute)
                } header: { Text("Automatic Direction") } footer: {
                    if timesConflict {
                        Text("Choose different times for Return Journey From and Start Again At.")
                            .foregroundStyle(.red)
                    } else {
                        Text("Times use UK local time. Manual reversal lasts until the next scheduled change.")
                    }
                }
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
                Section {
                    Picker("Theme", selection: $settings.appearance) {
                        ForEach(AppAppearance.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Appearance")
                } footer: {
                    BoardFooter(attributionOnlyAlignment: .center)
                }
            }
            .sheet(item: $selectedAutoRule) { rule in
                AutoTrackingEditor(draft: rule, tracker: tracker)
            }
            .contentMargins(.top, 0, for: .scrollContent)
            .toolbar(.hidden, for: .navigationBar)
            .environment(\.timeZone, JourneyDirection.londonCalendar.timeZone)
        }
    }

    private func stationSummary(_ title: String, stations: [Station]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Text(stations.map(\.shortName).joined(separator: ", "))
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func applyRoute(_ updated: RouteSettings) {
        guard updated != settings, updated.isValid else { return }
        var route = updated
        route.resumeAutomatic()
        settings = route
    }

    private func routeBinding<Value>(_ keyPath: WritableKeyPath<RouteSettings, Value>) -> Binding<Value> {
        Binding {
            settings[keyPath: keyPath]
        } set: { value in
            var updated = settings
            updated[keyPath: keyPath] = value
            applyRoute(updated)
        }
    }

    private func timeBinding(_ keyPath: WritableKeyPath<RouteSettings, Int>) -> Binding<Date> {
        Binding {
            let minutes = settings[keyPath: keyPath]
            return JourneyDirection.londonCalendar.date(bySettingHour: minutes / 60,
                minute: minutes % 60, second: 0, of: Date())!
        } set: { date in
            let parts = JourneyDirection.londonCalendar.dateComponents([.hour, .minute], from: date)
            var updated = settings
            updated[keyPath: keyPath] = parts.hour! * 60 + parts.minute!
            timesConflict = updated.swapMinutes == updated.resetMinutes
            applyRoute(updated)
        }
    }
}
