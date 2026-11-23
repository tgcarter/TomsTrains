import SwiftUI

struct LiveStationBoardView: View {
    let isVisible: Bool
    private let provider = LiveStationBoardProvider()

    @Environment(\.scenePhase) private var scenePhase
    @State private var draftQuery: String?
    @State private var directory = StationSearchDirectory()
    @State private var searches = LiveBoardSearches.load()
    @State private var showsFilterPicker = false
    @State private var snapshot: LiveStationBoard?
    @State private var now = Date()
    @State private var failure: (BoardRequest, String)?
    @State private var requestID: UUID?
    @State private var pages = LiveBoardPages()
    @State private var isRefreshingManually = false
    @State private var selectedTrain: LiveStationTrain?
    @State private var selectedNotice: StationNotice.Group?

    private var station: Station? { searches.station }
    private var filterStation: Station? { searches.filterStation }
    private var mode: LiveBoardMode { searches.mode }
    private var filterTitle: String { mode == .departures ? "Going To" : "Earlier Stop" }

    private var request: BoardRequest? {
        station.map { BoardRequest(station: $0, mode: mode, filter: filterStation) }
    }

    private var matchingSnapshot: LiveStationBoard? {
        guard let snapshot, snapshot.station == station, snapshot.mode == mode,
              snapshot.filterStation == filterStation else { return nil }
        return snapshot
    }

    private var currentBoard: LiveStationBoard? {
        guard let board = matchingSnapshot, board.isFresh(at: now) else { return nil }
        return board
    }

    private var boardMessage: String? {
        if let failure, failure.0 == request {
            return currentBoard == nil ? failure.1 : "Couldn’t refresh. Showing the last update."
        }
        if matchingSnapshot != nil && currentBoard == nil {
            return "The last station board is out of date. Pull down to try again."
        }
        return nil
    }

    private var loadedPages: [LiveStationBoard] {
        [pages[.earlier]?.board, pages[.later]?.board].compactMap(\.self)
            .filter { $0.station == station && $0.mode == mode && $0.filterStation == filterStation && $0.isFresh(at: now) }
    }

    private var nextExpiry: Date? {
        (loadedPages + [currentBoard].compactMap(\.self)).map(\.expiresAt).min()
    }

    private var visibleTrains: [LiveStationTrain] {
        let current = currentBoard?.trains ?? []
        let extras = loadedPages.flatMap(\.trains)
        return extras.isEmpty ? current : LiveStationTrain.ordered(extras + current)
    }

    var body: some View {
        let expiry = nextExpiry
        NavigationStack {
            List {
                DepartureBoardHeader(title: "Live", trailingSpace: 64)
                StationSearch(draft: $draftQuery, directory: directory, displayedStation: station,
                    clearSelection: clearSearch, isActive: isVisible && scenePhase == .active,
                    selection: .single { searches.select($0) }) { choose in
                    if station != nil {
                        Section {
                            Picker("Board", selection: $searches.mode) {
                                ForEach(LiveBoardMode.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            Button { showsFilterPicker = true } label: {
                                HStack {
                                    Text(filterTitle).foregroundStyle(.primary)
                                    Spacer()
                                    Text(filterStation?.name ?? "Any Station").foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Choose an optional station filter")
                        }
                        boardContent
                    } else {
                        Section {
                            if searches.recentStations.isEmpty {
                                Text("Stations you choose will appear here.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            } else {
                                ForEach(searches.recentStations) { result in
                                    Button { choose(result) } label: {
                                        StationResultLabel(station: result)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } header: {
                            Text("Recent Searches")
                        } footer: {
                            BoardFooter()
                        }
                    }
                }
            }
            .contentMargins(.top, 0, for: .scrollContent)
            .overlay(alignment: .topTrailing) {
                DepartureBoardControls(isLoading: isRefreshingManually,
                    refresh: { Task { await refreshCurrentView() } })
                    .padding(.trailing, 20)
            }
            .toolbar(.hidden, for: .navigationBar)
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await refreshCurrentView() }
            .onChange(of: searches) { _, updated in updated.save() }
            .onChange(of: request) { pages = LiveBoardPages() }
            .task(id: expiry) {
                guard let expiry else { return }
                do { try await Task.sleep(for: .seconds(max(0, expiry.timeIntervalSinceNow))) }
                catch { return }
                guard !Task.isCancelled else { return }
                updateBoardClock()
            }
            .task(id: isVisible && scenePhase == .active ? request : nil) {
                guard isVisible, scenePhase == .active, let request else { return }
                while !Task.isCancelled {
                    await refresh(request)
                    do { try await Task.sleep(for: .seconds(30)) }
                    catch { return }
                }
            }
            .sheet(item: $selectedTrain) { train in
                if let station {
                    LiveStationTrainDetails(train: visibleTrains.first { $0.id == train.id } ?? train,
                        mode: mode, station: station, filter: filterStation, provider: provider)
                }
            }
            .sheet(item: $selectedNotice) { StationNoticeSheet(notice: $0) }
            .sheet(isPresented: $showsFilterPicker) {
                NavigationStack {
                    StationPicker(title: filterTitle, selection: .single { searches.filterStation = $0 },
                        currentStation: filterStation, hiddenStation: station,
                        clearSelection: { searches.filterStation = nil },
                        guidance: mode == .departures ? "Search for a station the train calls at after leaving here."
                            : "Search for a station the train calls at before arriving here.")
                }
            }
        }
    }

    @ViewBuilder private var boardContent: some View {
        let message = boardMessage
        if let message {
            Section {
                Label(message, systemImage: "wifi.exclamationmark")
                    .font(.footnote).foregroundStyle(.secondary)
                if currentBoard == nil, let request {
                    Button("Try Again") { Task { await refresh(request) } }
                }
            }
        }
        if let board = currentBoard {
            if !board.notices.isEmpty {
                Section("Travel Disruption") {
                    ForEach(StationNotice.grouped(board.notices)) { notice in
                        Button { selectedNotice = notice } label: { StationNoticeRow(notice: notice) }
                            .buttonStyle(.plain)
                    }
                }
            }
            Section {
                if board.servicesUnavailable {
                    ContentUnavailableView("Board Unavailable", systemImage: "tram")
                } else {
                    if let request { pageButton(.earlier, for: request) }
                    let trains = visibleTrains
                    if trains.isEmpty {
                        let period = loadedPages.isEmpty ? "in the next hour" : "in this time range"
                        ContentUnavailableView("No Matching \(mode.rawValue)", systemImage: "clock",
                            description: Text("No services found \(period)."))
                    } else {
                        ForEach(trains) { train in
                            Button { selectedTrain = train } label: {
                                LiveStationTrainRow(train: train, mode: mode)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Shows train details")
                        }
                    }
                    if let request { pageButton(.later, for: request) }
                }
            } footer: {
                BoardFooter(updatedAt: board.updatedAt)
            }
        } else if message == nil {
            ProgressView("Loading \(mode.rawValue.lowercased())…")
        }
    }

    private func clearSearch() {
        searches.clearSelection()
        snapshot = nil
        failure = nil
        requestID = nil
    }

    private struct BoardRequest: Equatable {
        let station: Station
        let mode: LiveBoardMode
        let filter: Station?
    }

    private func updateBoardClock() {
        let date = Date()
        now = date
        pages.expire(at: date)
    }

    private func refreshCurrentView() async {
        guard !isRefreshingManually else { return }
        isRefreshingManually = true
        defer { isRefreshingManually = false }
        pages = LiveBoardPages()
        if (draftQuery ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let request {
            await refresh(request)
        } else {
            await directory.load()
        }
    }

    @ViewBuilder private func pageButton(_ window: LiveBoardWindow, for selection: BoardRequest) -> some View {
        let earlier = window == .earlier
        let page = pages[window]
        if let board = page?.board {
            if board.trains.isEmpty {
                Text(earlier ? "No earlier services available" : "No later services available")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } else {
            BoardPageButton(title: earlier ? "See Earlier" : "See Later", isLoading: page?.isLoading == true) {
                await loadPage(window, for: selection)
            }
            if case .failed = page {
                Text(earlier ? "Couldn’t load earlier services." : "Couldn’t load later services.")
                    .font(.footnote).foregroundStyle(.orange)
            }
        }
    }

    private func loadPage(_ window: LiveBoardWindow, for selection: BoardRequest) async {
        guard request == selection, let id = pages.begin(window) else { return }
        defer { pages.finish(window, id: id, with: nil) }
        do {
            let board = try await provider.board(for: selection.station, mode: selection.mode,
                filter: selection.filter, window: window, at: Date())
            guard !Task.isCancelled, request == selection else { return }
            updateBoardClock()
            guard !board.servicesUnavailable, board.isFresh(at: now) else { throw RailAPIError.unavailable }
            pages.finish(window, id: id, with: .loaded(board))
        } catch {
            guard !Task.isCancelled, request == selection else { return }
            pages.finish(window, id: id, with: .failed)
        }
    }

    private func refresh(_ selection: BoardRequest) async {
        let id = UUID()
        requestID = id
        updateBoardClock()
        do {
            let updated = try await provider.board(for: selection.station, mode: selection.mode,
                filter: selection.filter, at: now)
            guard !Task.isCancelled, requestID == id, request == selection else { return }
            updateBoardClock()
            guard updated.isFresh(at: now) else { throw RailAPIError.unavailable }
            snapshot = updated
            failure = nil
        } catch {
            guard !Task.isCancelled, requestID == id, request == selection else { return }
            updateBoardClock()
            let message: String
            if case RailAPIError.missingKey = error, selection.mode == .arrivals {
                message = "National Rail arrivals access isn’t configured in this build."
            } else {
                message = (error as? RailAPIError)?.errorDescription ?? "Couldn’t load the station board."
            }
            failure = (selection, message)
        }
    }
}

private struct LiveStationTrainRow: View {
    let train: LiveStationTrain
    let mode: LiveBoardMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(RailTime.string(train.boardTime))
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .strikethrough(train.status == .cancelled)
                Text(train.headline).font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }
            HStack {
                Label(train.statusLabel(for: mode), systemImage: train.status.symbol)
                    .labelStyle(CompactStatusLabelStyle())
                    .font(.caption).foregroundStyle(train.status.color)
                if let platform = train.platform, !platform.isEmpty {
                    Text("Platform \(platform)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                OperatorLogo(name: train.operatorName, code: train.operatorCode)
            }
        }
        .trainBoardRowStyle(isPast: train.actual != nil)
    }
}

private struct LiveStationTrainDetails: View {
    let train: LiveStationTrain
    let mode: LiveBoardMode
    let station: Station
    let filter: Station?
    let provider: LiveStationBoardProvider

    @Environment(\.dismiss) private var dismiss
    @State private var refreshedTrain: LiveStationTrain?
    @State private var refreshFailed = false

    private var report: LiveStationTrain {
        guard let refreshedTrain, refreshedTrain.observedAt >= train.observedAt else { return train }
        return refreshedTrain
    }

    var body: some View {
        let train = report
        let position = train.position
        NavigationStack {
            List {
                ServiceSummaryView(train: train, mode: mode, station: station,
                    locationError: refreshFailed ? "Live update unavailable · showing last report" : nil)
                JourneyRouteSection(stops: train.stops, position: position,
                    isCancelled: train.status == .cancelled, marksBoardStation: true)
            }
            .contentMargins(.vertical, 8, for: .scrollContent)
            .navigationTitle("Train Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .pollingTrainDetails(when: mode == .departures || (train.actual == nil && train.scheduled >= Date().addingTimeInterval(-600)),
                refresh: refreshDetails)
        }
    }

    @MainActor
    private func refreshDetails() async {
        do {
            let update = try await provider.details(for: report, at: station, filter: filter, now: Date())
            guard !Task.isCancelled else { return }
            if update.observedAt >= report.observedAt { refreshedTrain = update }
            refreshFailed = false
        } catch {
            guard !Task.isCancelled else { return }
            refreshFailed = true
        }
    }
}
