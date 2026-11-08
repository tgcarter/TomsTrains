import SwiftUI

struct AutoTrackingEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: AutoTrackingRule
    let tracker: TrainTracker
    private let days = [(2, "Monday"), (3, "Tuesday"), (4, "Wednesday"), (5, "Thursday"),
                        (6, "Friday"), (7, "Saturday"), (1, "Sunday")]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Auto-Track This Train", isOn: $draft.isEnabled)
                    LabeledContent("From", value: draft.origin.shortName)
                    LabeledContent("To", value: draft.destination.shortName)
                    DatePicker("Scheduled Departure", selection: Binding {
                        draft.scheduled(on: Date()) ?? Date()
                    } set: { date in
                        let parts = JourneyDirection.londonCalendar.dateComponents([.hour, .minute], from: date)
                        draft.departureMinutes = parts.hour! * 60 + parts.minute!
                    }, displayedComponents: .hourAndMinute)
                } footer: {
                    Text("Matches this route and scheduled departure time. A changed timetable will not select a different train automatically.")
                }
                Section("Repeat On") {
                    ForEach(days, id: \.0) { day, name in
                        Toggle(name, isOn: Binding {
                            draft.weekdays.contains(day)
                        } set: { selected in
                            if selected { draft.weekdays.insert(day) } else { draft.weekdays.remove(day) }
                        })
                    }
                }
                Section {
                    Text("Checks when you open the app and while it stays open. Days and times use UK local time. Each scheduled train is tracked independently. Tracking ends at its destination.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if tracker.autoRules.contains(where: { $0.id == draft.id }) {
                        Button("Remove Auto-Tracking", role: .destructive) {
                            tracker.removeAutomatic(id: draft.id)
                            dismiss()
                        }
                    }
                }
            }
            .environment(\.timeZone, JourneyDirection.londonCalendar.timeZone)
            .navigationTitle("Auto-Tracking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        tracker.configureAutomatic(draft)
                        dismiss()
                    }.disabled(!draft.isValid)
                }
            }
        }
    }
}
