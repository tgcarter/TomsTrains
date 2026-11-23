import SwiftUI

struct DepartureBoardView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var board = DepartureBoard()
    @Binding var settings: RouteSettings
    let tracker: TrainTracker
    let isVisible: Bool
    @State private var selectedDeparture: Departure?
    @State private var selectedNotice: StationNotice.Group?

    var body: some View {
        NavigationStack {
            List {
                DepartureBoardHeader(title: settings.selection(at: board.now).title, trailingSpace: 108)
                if let error = board.errorMessage, !board.showsInitialLoading {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(error, systemImage: "wifi.exclamationmark")
                                .foregroundStyle(.orange)
                            if !board.departures.isEmpty {
                                Text("Showing the last received board. Status may have changed.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let notices = board.snapshot?.stationNotices, !notices.isEmpty {
                    Section("Travel Disruption") {
                        ForEach(StationNotice.grouped(notices)) { notice in
                            Button { selectedNotice = notice } label: { StationNoticeRow(notice: notice) }
                                .buttonStyle(.plain)
                        }
                    }
                }

                if !tracker.journeys.isEmpty {
                    Section(tracker.journeys.count == 1 ? "Tracked Train" : "Tracked Trains") {
                        ForEach(tracker.journeys) { journey in
                            Button { selectedDeparture = journey.departure } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    DepartureRow(departure: journey.departure, isNext: false, showsJourneyStatus: true)
                                    if journey.departure.isCancelledAtDestination {
                                        if let reason = journey.departure.disruptionReason {
                                            Text(reason).font(.caption).foregroundStyle(.secondary)
                                        }
                                    } else if !journey.hasArrived {
                                        trackedPosition(journey.departure)
                                    }
                                    if let error = tracker.errors[journey.id] {
                                        Label(error, systemImage: "wifi.exclamationmark")
                                            .font(.caption).foregroundStyle(.orange)
                                    }
                                    if let observed = journey.departure.observedAt {
                                        Text("Updated \(RailTime.string(observed))")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions(allowsFullSwipe: false) {
                                Button("Stop Tracking", systemImage: "pin.slash", role: .destructive) {
                                    tracker.removeFromHistory(journey.departure)
                                }
                            }
                        }
                    }
                }

                Section {
                    NavigationLink {
                        TrackedJourneyHistoryView(tracker: tracker)
                    } label: {
                        Label("Previously tracked", systemImage: "clock.arrow.circlepath")
                    }
                }

                Section {
                    if board.canLoadEarlier {
                        BoardPageButton(title: "See Earlier", isLoading: board.isLoadingEarlier) {
                            await board.loadEarlier()
                        }
                    }

                    if board.hasLoadedEarlier {
                        if let error = board.earlierError {
                            Text(error).font(.footnote).foregroundStyle(.orange)
                        } else if board.earlier.isEmpty {
                            Text("No earlier services available").font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(board.visibleEarlier) { departure in
                            Button { selectedDeparture = departure } label: {
                                DepartureRow(departure: departure, isNext: false, isEarlier: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Shows train details")
                        }
                    }

                    let upcoming = upcomingDepartures
                    if board.showsInitialLoading {
                        DepartureLoadingHeader()
                        ForEach(0..<3) { index in
                            DepartureSkeletonRow(isNext: index == 0)
                                .accessibilityHidden(true)
                        }
                    } else if upcoming.isEmpty && board.earlier.isEmpty {
                        ContentUnavailableView(board.errorMessage == nil ? "No Upcoming Trains" : "TomsTrains Unavailable",
                            systemImage: board.errorMessage == nil ? "tram" : "wifi.exclamationmark",
                            description: Text(board.errorMessage == nil
                                ? "No more matching services before the overnight reset."
                                : "Pull down to try again."))
                    } else {
                        let earliest = upcoming.first { !$0.isCancelledAtDestination }?.id
                        ForEach(upcoming) { departure in
                            Button {
                                selectedDeparture = departure
                            } label: {
                                DepartureRow(departure: departure, isNext: departure.id == earliest)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Shows train details")
                        }
                    }
                    if board.canLoadLater {
                        BoardPageButton(title: "See Later", isLoading: board.isLoading) {
                            await board.loadLater()
                        }
                    }
                    if board.canShowTomorrow || board.tomorrowError != nil {
                        BoardPageButton(title: "See Tomorrow’s Services", isLoading: board.isLoadingTomorrow) {
                            await board.loadTomorrow()
                        }
                    }
                    if let error = board.tomorrowError {
                        Text(error).font(.footnote).foregroundStyle(.orange)
                    }
                    if board.showsTomorrow {
                        Text("Tomorrow’s Services").font(.headline)
                        if board.tomorrowDepartures.isEmpty && board.tomorrowError == nil {
                            Text("No matching services available for tomorrow.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(board.tomorrowDepartures) { departure in
                            Button { selectedDeparture = departure } label: {
                                DepartureRow(departure: departure, isNext: false)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Shows train details")
                        }
                    }
                    if board.showsTomorrow && board.canLoadLaterTomorrow {
                        BoardPageButton(title: "See Later", isLoading: board.isLoadingTomorrow) {
                            await board.loadLaterTomorrow()
                        }
                    }
                } header: {
                    Text(settings.selection(at: board.now).subtitle)
                } footer: {
                    BoardFooter(
                        updatedAt: board.snapshot?.fetchedAt,
                        manualReversalUntil: settings.isManual(at: board.now) ? settings.manualUntil : nil
                    )
                }
            }
            .contentMargins(.top, 0, for: .scrollContent)
            .overlay(alignment: .topTrailing) {
                DepartureBoardControls(isLoading: board.isLoading,
                    refresh: { Task { await refresh(resetPagination: true) } },
                    reverse: {
                        settings.reverse(at: Date())
                    })
                    .padding(.trailing, 20)
            }
            .toolbar(.hidden, for: .navigationBar)


            .refreshable { await refresh(resetPagination: true) }
            .sheet(item: $selectedDeparture) { departure in
                DepartureDetailView(departure: tracker.journeys.first(where: { $0.id == departure.id })?.departure ?? board.snapshot?.departures.first(where: { $0.id == departure.id }) ?? departure, tracker: tracker)
            }
            .sheet(item: $selectedNotice) { StationNoticeSheet(notice: $0) }
            .onChange(of: settings) { previous, updated in
                let now = Date()
                if previous.selection(at: now).key != updated.selection(at: now).key {
                    board.snapshot = nil
                    board.errorMessage = nil
                }
            }
            .task(id: RefreshTrigger(active: scenePhase == .active && isVisible, settings: settings)) {
                guard scenePhase == .active, isVisible else { return }
                await refresh()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(max(0.1, min(30, settings.nextTransition(after: Date()).timeIntervalSinceNow)))) }
                    catch { return }
                    await refresh()
                }
            }
        }
    }
    private var upcomingDepartures: [Departure] {
        let earlierIDs = board.hasLoadedEarlier ? Set(board.earlier.map(\.id)) : []
        return board.departures.filter { !earlierIDs.contains($0.id) }
    }

    private func refresh(resetPagination: Bool = false) async {
        tracker.pruneExpired(settings: settings)
        await board.refresh(settings: settings, resetPagination: resetPagination)
        guard !Task.isCancelled else { return }
        for departure in board.snapshot?.departures ?? [] { tracker.receive(departure) }
        if resetPagination {
            await tracker.refresh()
            await tracker.autoTrack(at: Date())
        }
    }

    @ViewBuilder private func trackedPosition(_ departure: Departure) -> some View {
        if departure.isBetweenStations, let last = departure.lastReportedStop, let next = departure.nextReportedStop {
            Label("Between \(last.name) and \(next.name)", systemImage: "tram.fill")
                .font(.subheadline).foregroundStyle(.blue)
        } else if let last = departure.lastReportedStop {
            Label("Last reported at \(last.name)", systemImage: "tram.fill")
                .font(.subheadline).foregroundStyle(.blue)
        } else {
            Label("Tracking to \(departure.callingAt.first?.shortName ?? departure.destination)", systemImage: "pin.fill")
                .font(.subheadline).foregroundStyle(.blue)
        }
        if let next = departure.nextReportedStop {
            Text("Next: \(next.name) · \(next.timeLabel)").font(.caption).foregroundStyle(.secondary)
        }
    }

    private struct RefreshTrigger: Equatable {
        let active: Bool
        let settings: RouteSettings
    }
}


#Preview { DepartureBoardView(settings: .constant(RouteSettings()), tracker: TrainTracker(), isVisible: true) }
