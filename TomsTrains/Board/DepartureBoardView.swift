import SwiftUI

struct DepartureBoardView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var board = DepartureBoard()
    @State private var tracker = TrainTracker()
    @State private var settings = RouteSettings.load()
    @State private var showingSettings = false
    @State private var selectedDeparture: Departure?
    @State private var selectedNotice: StationNotice.Group?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    EmptyView()
                } header: {
                    DepartureBoardHeader(title: settings.selection(at: board.now).title)
                        .foregroundStyle(.primary)
                        .textCase(nil)
                        .listRowInsets(EdgeInsets())
                }
                .listSectionMargins(.top, 0)
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
                                    trackedPosition(journey.departure)
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
                                    tracker.toggle(journey.departure)
                                }
                            }
                        }
                    }
                }

                Section {
                    if board.canLoadEarlier {
                    Button {
                        Task { await board.loadEarlier() }
                    } label: {
                        HStack {
                            Text("See Earlier")
                            Spacer()
                            if board.isLoadingEarlier { ProgressView() }
                        }
                    }
                    .disabled(board.isLoadingEarlier)
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

                    if board.showsInitialLoading {
                        DepartureLoadingHeader()
                        ForEach(0..<3) { index in
                            DepartureSkeletonRow(isNext: index == 0)
                                .accessibilityHidden(true)
                        }
                    } else if upcomingDepartures.isEmpty && board.earlier.isEmpty {
                        ContentUnavailableView(board.errorMessage == nil ? "No Upcoming Trains" : "TomsTrains Unavailable",
                            systemImage: board.errorMessage == nil ? "tram" : "wifi.exclamationmark",
                            description: Text(board.errorMessage == nil
                                ? "No more matching services before the overnight reset."
                                : "Pull down to try again."))
                    } else {
                        ForEach(upcomingDepartures) { departure in
                            Button {
                                selectedDeparture = departure
                            } label: {
                                DepartureRow(departure: departure, isNext: departure.id == upcomingDepartures.first(where: { !$0.isCancelledAtDestination })?.id)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Shows train details")
                        }
                    }
                    if board.canLoadLater {
                        Button {
                            Task { await board.loadLater() }
                        } label: {
                            HStack {
                                Text("See Later")
                                Spacer()
                                if board.isLoading { ProgressView() }
                            }
                        }
                        .disabled(board.isLoading)
                    }
                    if board.canShowTomorrow || board.tomorrowError != nil {
                        Button {
                            Task { await board.loadTomorrow() }
                        } label: {
                            HStack {
                                Text("See Tomorrow’s Services")
                                Spacer()
                                if board.isLoadingTomorrow { ProgressView() }
                            }
                        }
                        .disabled(board.isLoadingTomorrow)
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
                        Button {
                            Task { await board.loadLaterTomorrow() }
                        } label: {
                            HStack {
                                Text("See Later")
                                Spacer()
                                if board.isLoadingTomorrow { ProgressView() }
                            }
                        }
                        .disabled(board.isLoadingTomorrow)
                    }
                } header: {
                    Text(settings.selection(at: board.now).subtitle)
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 8) {
                                if let snapshot = board.snapshot {
                                    Text("Updated \(RailTime.string(snapshot.fetchedAt))")
                                        .fixedSize()
                                }
                                Spacer(minLength: 0)
                                NationalRailAttribution().fixedSize(horizontal: true, vertical: false)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                if let snapshot = board.snapshot {
                                    Text("Updated \(RailTime.string(snapshot.fetchedAt))")
                                }
                                NationalRailAttribution()
                            }
                        }
                        if settings.isManual(at: board.now), let until = settings.manualUntil {
                            Text("Manually reversed · automatic from \(RailTime.string(until))")
                        }
                    }
                }
            }
            .contentMargins(.top, 0, for: .scrollContent)
            .overlay(alignment: .topTrailing) {
                DepartureBoardControls(isLoading: board.isLoading,
                    refresh: { Task { await refresh(resetPagination: true) } },
                    reverse: {
                        settings.reverse(at: Date())
                        persistSettings()
                    }, settings: { showingSettings = true })
                    .padding(.trailing, 20)
            }
            .toolbar(.hidden, for: .navigationBar)


            .refreshable { await refresh(resetPagination: true) }
            .sheet(item: $selectedDeparture) { departure in
                DepartureDetailView(departure: tracker.journeys.first(where: { $0.id == departure.id })?.departure ?? board.snapshot?.departures.first(where: { $0.id == departure.id }) ?? departure, tracker: tracker)
            }
            .sheet(item: $selectedNotice) { StationNoticeSheet(notice: $0) }
            .sheet(isPresented: $showingSettings) {
                SettingsView(draft: settings, tracker: tracker) { updated in
                    settings = updated
                    persistSettings()
                }
            }
            .task(id: RefreshTrigger(scenePhase: scenePhase, settings: settings)) {
                guard scenePhase == .active else { return }
                await refresh()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(max(0.1, min(30, settings.nextTransition(after: Date()).timeIntervalSinceNow)))) }
                    catch { return }
                    await refresh()
                }
            }
        }
        .tint(.blue)
        .preferredColorScheme(settings.appearance.colorScheme)
    }
    private var upcomingDepartures: [Departure] {
        let earlierIDs = board.hasLoadedEarlier ? Set(board.earlier.map(\.id)) : []
        return board.departures.filter { !earlierIDs.contains($0.id) }
    }

    private func refresh(resetPagination: Bool = false) async {
        await board.refresh(settings: settings, resetPagination: resetPagination)
        for departure in board.snapshot?.departures ?? [] { tracker.receive(departure) }
        await tracker.refresh()
        await tracker.autoTrack(at: Date())
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
        let scenePhase: ScenePhase
        let settings: RouteSettings
    }
    private func persistSettings() {
        settings.save()
        board.settings = settings
        board.now = Date()
        board.resetEarlier()
        board.snapshot = nil
        board.errorMessage = nil
    }
}


#Preview { DepartureBoardView() }
