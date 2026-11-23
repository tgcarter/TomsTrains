import SwiftUI

struct TrackedJourneyHistoryView: View {
    let tracker: TrainTracker

    var body: some View {
        List(tracker.previouslyTracked) { journey in
            let service = journey.departure
            NavigationLink {
                TrackedJourneyHistoryDetails(id: journey.id, tracker: tracker)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(service.routeLabel).font(.headline)
                    Text("\(historyDate(service.scheduled)) · \(RailTime.string(service.scheduled))")
                        .font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        if service.isCancelledAtDestination {
                            Label("Cancelled", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        } else if journey.hasArrived {
                            Label(journey.reportedArrival.map { "Arrived \(RailTime.string($0))" } ?? "Arrived",
                                systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else if tracker.contains(service) {
                            Label("Tracking", systemImage: "pin.fill")
                                .foregroundStyle(.tint)
                        } else {
                            Text("No arrival report").foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        OperatorLogo(name: service.operatorName, code: service.operatorCode, height: 26)
                    }
                    .labelStyle(CompactStatusLabelStyle())
                    .font(.caption)
                }
                .padding(.vertical, 4)
            }
            .swipeActions(allowsFullSwipe: false) {
                Button(tracker.contains(service) ? "Stop Tracking" : "Remove", systemImage: "trash", role: .destructive) {
                    tracker.removeFromHistory(service)
                }
            }
        }
        .overlay {
            if tracker.previouslyTracked.isEmpty {
                ContentUnavailableView("No Tracked Journeys", systemImage: "clock.arrow.circlepath",
                    description: Text("Trains you track on Commute are saved here."))
            }
        }
        .navigationTitle("Previously tracked")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

private struct TrackedJourneyHistoryDetails: View {
    let id: String
    let tracker: TrainTracker

    var body: some View {
        Group {
            if let journey = tracker.previouslyTracked.first(where: { $0.id == id }) {
                let service = journey.departure
                let actual = journey.reportedArrival
                List {
                    Section {
                        Text(service.routeLabel).font(.title2.bold())
                        LabeledContent("Date", value: historyDate(service.scheduled))
                        LabeledContent("Scheduled departure", value: RailTime.string(service.scheduled))
                        LabeledContent("Scheduled arrival", value: time(service.scheduledArrival, for: service))
                        LabeledContent("Actual arrival", value: time(actual, for: service))
                        if actual == nil, let departed = journey.reportedDepartureFromDestination {
                            let destination = service.callingAt.first?.shortName ?? service.destination
                            LabeledContent("Departed \(destination)", value: time(departed, for: service))
                        }
                        if let actual, let scheduled = service.scheduledArrival,
                           case .delayed(let minutes) = ServiceStatus.timing(scheduled: scheduled, reported: actual) {
                            LabeledContent("Arrival delay", value: "\(minutes) min")
                        }
                        if service.isCancelledAtDestination {
                            LabeledContent("Status", value: "Cancelled")
                        }
                        LabeledContent("Operator", value: service.operatorName)
                    }
                    Section("Delay Repay") {
                        let links = DelayRepay.links(for: service)
                        ForEach(links) { link in
                            Link(destination: link.url) {
                                Label(link.title, systemImage: "arrow.up.right.square")
                            }
                        }
                        if links.isEmpty {
                            Link(destination: DelayRepay.directory) {
                                Label("Find your operator’s claim page", systemImage: "arrow.up.right.square")
                            }
                        }
                    }
                    JourneyRouteSection(stops: service.routeStops ?? [], position: service.routePosition,
                        isCancelled: service.isCancelledAtDestination)
                }
            } else {
                ContentUnavailableView("Journey Removed", systemImage: "clock.arrow.circlepath")
            }
        }
        .navigationTitle("Tracked journey")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func time(_ date: Date?, for service: Departure) -> String {
        guard let date else { return "Not reported" }
        if JourneyDirection.londonCalendar.isDate(date, inSameDayAs: service.scheduled) {
            return RailTime.string(date)
        }
        return "\(historyDate(date)) · \(RailTime.string(date))"
    }
}

private func historyDate(_ date: Date) -> String {
    var format = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
    format.timeZone = JourneyDirection.londonCalendar.timeZone
    return date.formatted(format)
}
